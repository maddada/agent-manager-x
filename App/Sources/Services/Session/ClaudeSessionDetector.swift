import Foundation

final class ClaudeSessionDetector: AgentSessionDetecting {
    let agentType: AgentType = .claude

    private let processService: ProcessIntrospectionService
    private let shell: ShellCommandRunning

    init(
        processService: ProcessIntrospectionService,
        shell: ShellCommandRunning
    ) {
        self.processService = processService
        self.shell = shell
    }

    func detectSessions() -> [Session] {
        let processes = findClaudeProcesses()
        guard !processes.isEmpty else {
            return []
        }

        var sessions: [Session] = []
        var matchedPIDs: Set<Int> = []

        for process in processes {
            guard let activeFile = process.activeSessionFile else {
                continue
            }

            let projectPath = process.cwd ?? "/"
            guard var session = parseClaudeSessionFile(
                at: activeFile,
                projectPath: projectPath,
                process: process
            ) else {
                continue
            }

            let projectDirectory = URL(fileURLWithPath: activeFile).deletingLastPathComponent()
            session = withSubagentCount(session, projectDirectory: projectDirectory)

            sessions.append(session)
            matchedPIDs.insert(process.pid)
        }

        let unmatched = processes.filter { !matchedPIDs.contains($0.pid) }
        if unmatched.isEmpty {
            return dedupeSessionsByPID(sessions)
        }

        var candidateProjects: [String: [AgentProcess]] = [:]
        for process in unmatched {
            guard let cwd = process.cwd else {
                continue
            }

            let exact = SessionParsingSupport.convertPathToClaudeDirectoryName(cwd)
            candidateProjects[exact, default: []].append(process)

            let normalized = exact.replacingOccurrences(of: "_", with: "-")
            if normalized != exact {
                candidateProjects[normalized, default: []].append(process)
            }
        }

        if !candidateProjects.isEmpty {
            let projectRoots = claudeProjectRoots()
            for root in projectRoots {
                guard FileManager.default.fileExists(atPath: root.path) else {
                    continue
                }

                for (dirName, projectProcesses) in candidateProjects {
                    let projectDirectory = root.appendingPathComponent(dirName, isDirectory: true)
                    guard FileManager.default.fileExists(atPath: projectDirectory.path) else {
                        continue
                    }

                    let jsonlFiles = recentProjectJSONLFiles(in: projectDirectory)
                    for (index, process) in projectProcesses.enumerated() {
                        let projectPath = process.cwd ?? SessionParsingSupport.convertClaudeDirectoryNameToPath(dirName)
                        if let session = findSessionForProcess(
                            files: jsonlFiles,
                            projectDirectory: projectDirectory,
                            projectPath: projectPath,
                            process: process,
                            index: index
                        ) {
                            sessions.append(session)
                            matchedPIDs.insert(process.pid)
                        }
                    }
                }
            }
        }

        for process in unmatched where !matchedPIDs.contains(process.pid) {
            sessions.append(buildFallbackSession(process: process))
        }

        return dedupeSessionsByPID(sessions)
    }

    private func findClaudeProcesses() -> [AgentProcess] {
        let snapshots = processService.listProcesses()
        guard !snapshots.isEmpty else {
            return []
        }

        let byPID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.pid, $0) })

        let claudeCandidates = snapshots.filter { snapshot in
            let first = snapshot.firstArguments(maxCount: 1).first?.lowercased() ?? ""
            let isClaude = first == "claude" || first.hasSuffix("/claude")
            return isClaude && !snapshot.commandLine.localizedCaseInsensitiveContains("agent-manager-x")
        }

        let claudePIDSet = Set(claudeCandidates.map(\.pid))

        return claudeCandidates.compactMap { snapshot in
            if claudePIDSet.contains(snapshot.parentPID) {
                return nil
            }

            if let parent = byPID[snapshot.parentPID],
               parent.commandLine.localizedCaseInsensitiveContains("claude-code-acp") {
                return nil
            }

            let cwd = processService.workingDirectory(pid: snapshot.pid)
            let activeFile = processService.newestOpenFile(
                pid: snapshot.pid,
                pathContains: "/.claude",
                suffix: ".jsonl",
                excludingFilenamePrefix: "agent-"
            )

            return AgentProcess(
                pid: snapshot.pid,
                cpuUsage: snapshot.cpuUsage,
                memoryBytes: snapshot.memoryBytes,
                cwd: cwd,
                parentPID: snapshot.parentPID,
                processGroupID: snapshot.processGroupID,
                commandLine: snapshot.commandLine,
                activeSessionFile: activeFile,
                dataHome: nil
            )
        }
    }

    private func findSessionForProcess(
        files: [String],
        projectDirectory: URL,
        projectPath: String,
        process: AgentProcess,
        index: Int
    ) -> Session? {
        guard let primaryFile = files[safe: index],
              var session = parseClaudeSessionFile(at: primaryFile, projectPath: projectPath, process: process)
        else {
            return nil
        }

        session = withSubagentCount(session, projectDirectory: projectDirectory)

        let now = Date()
        let recentThreshold: TimeInterval = 10

        for candidate in files where candidate != primaryFile {
            let modified = SessionParsingSupport.modifiedDate(for: candidate)
            if now.timeIntervalSince(modified) > recentThreshold {
                continue
            }

            guard let other = parseClaudeSessionFile(at: candidate, projectPath: projectPath, process: process) else {
                continue
            }

            guard other.id == session.id else {
                continue
            }

            if SessionParsingSupport.statusPriority(other.status) < SessionParsingSupport.statusPriority(session.status) {
                session = Session(
                    id: session.id,
                    agentType: session.agentType,
                    projectName: session.projectName,
                    projectPath: session.projectPath,
                    gitBranch: session.gitBranch,
                    githubUrl: session.githubUrl,
                    status: other.status,
                    lastMessage: session.lastMessage,
                    lastMessageRole: session.lastMessageRole,
                    lastActivityAt: session.lastActivityAt,
                    pid: session.pid,
                    cpuUsage: session.cpuUsage,
                    memoryBytes: session.memoryBytes,
                    activeSubagentCount: session.activeSubagentCount,
                    isBackground: false
                )
            }
        }

        if session.status == .waiting,
           process.cpuUsage > 15,
           let age = SessionParsingSupport.ageSeconds(from: session.lastActivityAt),
           age <= 30 {
            session = Session(
                id: session.id,
                agentType: session.agentType,
                projectName: session.projectName,
                projectPath: session.projectPath,
                gitBranch: session.gitBranch,
                githubUrl: session.githubUrl,
                status: .processing,
                lastMessage: session.lastMessage,
                lastMessageRole: session.lastMessageRole,
                lastActivityAt: session.lastActivityAt,
                pid: session.pid,
                cpuUsage: session.cpuUsage,
                memoryBytes: session.memoryBytes,
                activeSubagentCount: session.activeSubagentCount,
                isBackground: false
            )
        }

        return session
    }

    private func parseClaudeSessionFile(at path: String, projectPath: String, process: AgentProcess) -> Session? {
        let url = URL(fileURLWithPath: path)
        guard let data = SessionParsingSupport.parseClaudeMessageData(url: url),
              let sessionID = data.sessionID
        else {
            return nil
        }

        let fileAge = Date().timeIntervalSince(SessionParsingSupport.modifiedDate(for: path))
        let fileRecentlyModified = fileAge < 3

        let messageAge = SessionParsingSupport.ageSeconds(from: data.lastTimestamp)
        let messageIsStale = (messageAge ?? .infinity) > 30

        var status = SessionParsingSupport.determineClaudeStatus(
            lastMessageType: data.lastMessageType,
            hasToolUse: data.hasToolUse,
            hasToolResult: data.hasToolResult,
            isLocalCommand: data.isLocalCommand,
            isInterrupted: data.isInterrupted,
            fileRecentlyModified: fileRecentlyModified,
            messageIsStale: messageIsStale
        )

        status = SessionParsingSupport.applyIdleStaleUpgrade(baseStatus: status, timestamp: data.lastTimestamp)

        var lastMessage = data.lastMessage
        var lastRole = data.lastRole

        if SessionParsingSupport.shouldShowLastUserMessage(status: status, lastMessage: lastMessage),
           let userMessage = data.lastUserMessage {
            lastMessage = userMessage
            lastRole = "user"
        }

        if let message = lastMessage {
            lastMessage = SessionParsingSupport.truncate(message, maxChars: 5000)
        }

        let projectName = SessionParsingSupport.projectName(from: projectPath)
        let githubURL = SessionParsingSupport.gitHubURL(for: projectPath, shell: shell)

        return Session(
            id: sessionID,
            agentType: .claude,
            projectName: projectName,
            projectPath: projectPath,
            gitBranch: data.gitBranch,
            githubUrl: githubURL,
            status: status,
            lastMessage: lastMessage,
            lastMessageRole: SessionParsingSupport.messageRole(from: lastRole),
            lastActivityAt: data.lastTimestamp ?? SessionParsingSupport.formatISODate(Date()),
            pid: process.pid,
            cpuUsage: process.cpuUsage,
            memoryBytes: process.memoryBytes,
            activeSubagentCount: 0,
            isBackground: false
        )
    }

    private func withSubagentCount(_ session: Session, projectDirectory: URL) -> Session {
        let count = countActiveSubagents(projectDirectory: projectDirectory, parentSessionID: session.id)
        return Session(
            id: session.id,
            agentType: session.agentType,
            projectName: session.projectName,
            projectPath: session.projectPath,
            gitBranch: session.gitBranch,
            githubUrl: session.githubUrl,
            status: session.status,
            lastMessage: session.lastMessage,
            lastMessageRole: session.lastMessageRole,
            lastActivityAt: session.lastActivityAt,
            pid: session.pid,
            cpuUsage: session.cpuUsage,
            memoryBytes: session.memoryBytes,
            activeSubagentCount: count,
            isBackground: session.isBackground
        )
    }

    private func countActiveSubagents(projectDirectory: URL, parentSessionID: String) -> Int {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: projectDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        let threshold: TimeInterval = 30
        let now = Date()

        return entries
            .filter { $0.lastPathComponent.hasPrefix("agent-") && $0.pathExtension == "jsonl" }
            .filter { url in
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return now.timeIntervalSince(modified) < threshold
            }
            .filter { url in
                subagentSessionID(from: url) == parentSessionID
            }
            .count
    }

    private func subagentSessionID(from fileURL: URL) -> String? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).prefix(5)
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }

            if let value = json["sessionId"] as? String {
                return value
            }
        }

        return nil
    }

    private func recentProjectJSONLFiles(in projectDirectory: URL) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: projectDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries
            .filter {
                $0.pathExtension == "jsonl" && !$0.lastPathComponent.hasPrefix("agent-")
            }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
            .map(\.path)
    }

    private func buildFallbackSession(process: AgentProcess) -> Session {
        let projectPath = fallbackProjectPath(for: process)
        let activityDate = observedActivityDate(for: process)

        return Session(
            id: "claude-\(process.pid)",
            agentType: .claude,
            projectName: SessionParsingSupport.projectName(from: projectPath),
            projectPath: projectPath,
            gitBranch: nil,
            githubUrl: nil,
            status: fallbackStatus(for: process, activityDate: activityDate),
            lastMessage: nil,
            lastMessageRole: nil,
            lastActivityAt: SessionParsingSupport.formatISODate(activityDate ?? Date()),
            pid: process.pid,
            cpuUsage: process.cpuUsage,
            memoryBytes: process.memoryBytes,
            activeSubagentCount: 0,
            isBackground: false
        )
    }

    private func fallbackProjectPath(for process: AgentProcess) -> String {
        if let cwd = process.cwd?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cwd.isEmpty {
            return cwd
        }

        if let inferred = inferredProjectPathFromActiveFile(process.activeSessionFile) {
            return inferred
        }

        return "/"
    }

    private func inferredProjectPathFromActiveFile(_ activeFile: String?) -> String? {
        guard let activeFile else {
            return nil
        }

        let components = URL(fileURLWithPath: activeFile).pathComponents
        guard let projectsIndex = components.lastIndex(of: "projects"),
              components.indices.contains(projectsIndex + 1)
        else {
            return nil
        }

        let encodedDirectory = components[projectsIndex + 1]
        guard encodedDirectory.hasPrefix("-") else {
            return nil
        }

        let inferred = SessionParsingSupport.convertClaudeDirectoryNameToPath(encodedDirectory)
        return inferred.isEmpty ? nil : inferred
    }

    private func observedActivityDate(for process: AgentProcess) -> Date? {
        guard let activeFile = process.activeSessionFile,
              FileManager.default.fileExists(atPath: activeFile)
        else {
            return nil
        }

        let modified = SessionParsingSupport.modifiedDate(for: activeFile)
        return modified == .distantPast ? nil : modified
    }

    private func fallbackStatus(for process: AgentProcess, activityDate: Date?) -> SessionStatus {
        if process.cpuUsage > 15 {
            return .processing
        }

        guard let activityDate else {
            return process.cpuUsage > 5 ? .thinking : .waiting
        }

        let age = Date().timeIntervalSince(activityDate)
        if age >= 10 * 60 {
            return .stale
        }
        if age >= 5 * 60 {
            return .idle
        }

        if process.cpuUsage > 5 {
            return .thinking
        }

        return .waiting
    }

    private func claudeProjectRoots() -> [URL] {
        guard let home = FileManager.default.homeDirectoryForCurrentUser as URL? else {
            return []
        }

        var roots: [URL] = [
            home.appendingPathComponent(".claude/projects", isDirectory: true)
        ]

        let profileRoots = [
            home.appendingPathComponent(".claude-profiles/work", isDirectory: true),
            home.appendingPathComponent(".claude-profiles/personal", isDirectory: true)
        ]

        for profileRoot in profileRoots {
            let projectsDir = profileRoot.appendingPathComponent("projects", isDirectory: true)
            if FileManager.default.fileExists(atPath: projectsDir.path) {
                roots.append(projectsDir)
            } else {
                roots.append(profileRoot)
            }
        }

        var seen: Set<String> = []
        return roots.filter { seen.insert($0.path).inserted }
    }

    private func dedupeSessionsByPID(_ sessions: [Session]) -> [Session] {
        var bestByPID: [Int: Session] = [:]

        for session in sessions {
            guard let current = bestByPID[session.pid] else {
                bestByPID[session.pid] = session
                continue
            }

            if isBetter(candidate: session, than: current) {
                bestByPID[session.pid] = session
            }
        }

        return Array(bestByPID.values)
    }

    private func isBetter(candidate: Session, than current: Session) -> Bool {
        let candidatePriority = SessionParsingSupport.statusPriority(candidate.status)
        let currentPriority = SessionParsingSupport.statusPriority(current.status)
        if candidatePriority != currentPriority {
            return candidatePriority < currentPriority
        }

        if candidate.sortableLastActivityDate != current.sortableLastActivityDate {
            return candidate.sortableLastActivityDate > current.sortableLastActivityDate
        }

        if candidate.lastMessage != nil, current.lastMessage == nil {
            return true
        }
        if candidate.lastMessage == nil, current.lastMessage != nil {
            return false
        }

        return candidate.id > current.id
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
