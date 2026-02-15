import Foundation

final class CodexSessionDetector: AgentSessionDetecting {
    let agentType: AgentType = .codex

    private let processService: ProcessIntrospectionService

    init(processService: ProcessIntrospectionService) {
        self.processService = processService
    }

    func detectSessions() -> [Session] {
        let processes = findCodexProcesses()
        guard !processes.isEmpty else {
            return []
        }

        var sessions: [Session] = []
        var unresolvedProcesses: [AgentProcess] = []

        for process in processes {
            if let activePath = process.activeSessionFile,
               let activeFile = loadDirectSessionFile(path: activePath),
               let session = buildSession(from: activeFile, process: process) {
                sessions.append(session)
                continue
            }

            unresolvedProcesses.append(process)
        }

        guard !unresolvedProcesses.isEmpty else {
            return sessions
        }

        let roots = codexSessionRoots(from: unresolvedProcesses)
        guard !roots.isEmpty else {
            return sessions + unresolvedProcesses.map { buildFallbackSession(process: $0) }
        }

        let parseLimit = codexSessionParseLimit(processCount: unresolvedProcesses.count)
        let sessionFiles = collectCodexSessionFiles(from: roots, parseLimit: parseLimit)

        var filesByCWD: [String: [Int]] = [:]
        for (index, file) in sessionFiles.enumerated() {
            guard let cwd = file.cwd else { continue }
            filesByCWD[cwd, default: []].append(index)
        }
        for key in filesByCWD.keys {
            filesByCWD[key]?.sort { lhs, rhs in
                sessionFiles[lhs].modified > sessionFiles[rhs].modified
            }
        }

        var usedIndices: Set<Int> = []

        for process in unresolvedProcesses {
            var assignedIndex: Int?

            if let cwd = process.cwd,
               var queue = filesByCWD[cwd] {
                while let idx = queue.first {
                    queue.removeFirst()
                    if !usedIndices.contains(idx) {
                        // Only match files modified after this process started.
                        if let startDate = process.startDate {
                            let cutoff = startDate.addingTimeInterval(-5)
                            if sessionFiles[idx].modified < cutoff {
                                continue
                            }
                        }
                        assignedIndex = idx
                        break
                    }
                }
                filesByCWD[cwd] = queue
            }

            if let index = assignedIndex {
                usedIndices.insert(index)
                if let session = buildSession(from: sessionFiles[index], process: process) {
                    sessions.append(session)
                    continue
                }
            }

            sessions.append(buildFallbackSession(process: process))
        }

        return sessions
    }

    private func findCodexProcesses() -> [AgentProcess] {
        let snapshots = processService.listProcesses()

        return snapshots.compactMap { snapshot in
            let args = snapshot.firstArguments(maxCount: 3).map { $0.lowercased() }
            guard let first = args.first else {
                return nil
            }

            let isCodex = first == "codex" || first.hasSuffix("/codex")
            guard isCodex else {
                return nil
            }

            let isAppServer = args.dropFirst().first == "app-server"
            if isAppServer {
                return nil
            }

            let cwd = processService.workingDirectory(pid: snapshot.pid)
            let activeSessionFile = processService.newestOpenFile(
                pid: snapshot.pid,
                pathContains: "/sessions/",
                suffix: ".jsonl"
            )

            let dataHome = activeSessionFile.flatMap(inferDataHome(fromSessionPath:))

            return AgentProcess(
                pid: snapshot.pid,
                cpuUsage: snapshot.cpuUsage,
                memoryBytes: snapshot.memoryBytes,
                cwd: cwd,
                parentPID: snapshot.parentPID,
                processGroupID: snapshot.processGroupID,
                commandLine: snapshot.commandLine,
                activeSessionFile: activeSessionFile,
                dataHome: dataHome,
                startDate: SessionParsingSupport.processStartDate(elapsed: snapshot.elapsed)
            )
        }
    }

    private func inferDataHome(fromSessionPath path: String) -> String? {
        guard let range = path.range(of: "/sessions/") else {
            return nil
        }
        let prefix = String(path[..<range.lowerBound])
        return prefix.isEmpty ? nil : prefix
    }

    private func codexSessionRoots(from processes: [AgentProcess]) -> [URL] {
        if let rootsFromProcess = dedupePaths(
            processes
                .compactMap(\.dataHome)
                .map { resolveProfileSessionsDirectory(URL(fileURLWithPath: $0)) }
        ), !rootsFromProcess.isEmpty {
            return rootsFromProcess
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaults = [
            home.appendingPathComponent(".codex/sessions", isDirectory: true),
            resolveProfileSessionsDirectory(home.appendingPathComponent(".codex-profiles/work", isDirectory: true)),
            resolveProfileSessionsDirectory(home.appendingPathComponent(".codex-profiles/personal", isDirectory: true))
        ]

        return dedupePaths(defaults) ?? []
    }

    private func resolveProfileSessionsDirectory(_ root: URL) -> URL {
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        if FileManager.default.fileExists(atPath: sessions.path) {
            return sessions
        }
        return root
    }

    private func dedupePaths(_ paths: [URL]) -> [URL]? {
        var seen: Set<String> = []
        let deduped = paths.filter { seen.insert($0.path).inserted }
        return deduped.isEmpty ? nil : deduped
    }

    private func codexSessionParseLimit(processCount: Int) -> Int {
        let filesPerProcess = 12
        let maxParseFiles = 120
        let minParseFiles = max(processCount, 2)
        return min(max(processCount * filesPerProcess, minParseFiles), maxParseFiles)
    }

    private func collectCodexSessionFiles(from roots: [URL], parseLimit: Int) -> [CodexSessionFile] {
        let maxCandidates = max(parseLimit * 3, parseLimit)
        let perRootLimit = roots.isEmpty ? maxCandidates : Int(ceil(Double(maxCandidates) / Double(roots.count)))

        var candidates: [(path: String, modified: Date)] = []
        var seen: Set<String> = []

        for root in roots {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            searchCodexFilesRecursively(
                directory: root,
                maxCandidates: perRootLimit,
                seen: &seen,
                into: &candidates
            )
        }

        candidates.sort { $0.modified > $1.modified }

        let selected = candidates.prefix(parseLimit)
        return selected.compactMap { parseCodexSessionFile(path: $0.path, modified: $0.modified) }
    }

    private func searchCodexFilesRecursively(
        directory: URL,
        maxCandidates: Int,
        seen: inout Set<String>,
        into candidates: inout [(path: String, modified: Date)]
    ) {
        guard candidates.count < maxCandidates,
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                  options: [.skipsHiddenFiles]
              )
        else {
            return
        }

        let sorted = entries.sorted { $0.lastPathComponent > $1.lastPathComponent }

        for entry in sorted {
            if candidates.count >= maxCandidates {
                return
            }

            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            if values?.isDirectory == true {
                searchCodexFilesRecursively(
                    directory: entry,
                    maxCandidates: maxCandidates,
                    seen: &seen,
                    into: &candidates
                )
                continue
            }

            guard entry.pathExtension == "jsonl" else { continue }
            guard seen.insert(entry.path).inserted else { continue }

            let modified = values?.contentModificationDate ?? .distantPast
            candidates.append((path: entry.path, modified: modified))
        }
    }

    private func loadDirectSessionFile(path: String) -> CodexSessionFile? {
        let modified = SessionParsingSupport.modifiedDate(for: path)
        return parseCodexSessionFile(path: path, modified: modified)
    }

    private func parseCodexSessionFile(path: String, modified: Date) -> CodexSessionFile? {
        let url = URL(fileURLWithPath: path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        var sessionID: String?
        var cwdMeta: String?
        var cwdTurn: String?
        var cwdEnv: String?
        var lastMessage: String?
        var lastRole: String?
        var lastActivityAt: String?
        var lastUserMessageAt: Date?
        var lastTaskStartedAt: Date?
        var lastTaskSignalAt: Date?
        var lastInterruptAt: Date?
        var lastTerminalEventAt: Date?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            guard
                let data = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }

            let lineType = json["type"] as? String ?? ""
            let timestamp = json["timestamp"] as? String
            let timestampDate = SessionParsingSupport.parseISODate(timestamp)

            switch lineType {
            case "session_meta":
                if let payload = json["payload"] as? [String: Any] {
                    if sessionID == nil {
                        sessionID = payload["id"] as? String
                    }
                    if cwdMeta == nil {
                        cwdMeta = payload["cwd"] as? String
                    }
                }
            case "turn_context":
                if let payload = json["payload"] as? [String: Any],
                   let cwd = payload["cwd"] as? String,
                   !cwd.isEmpty {
                    cwdTurn = cwd
                }
            case "response_item":
                if let payload = json["payload"] as? [String: Any] {
                    let payloadType = payload["type"] as? String ?? ""

                    switch payloadType {
                    case "function_call", "function_call_output", "reasoning":
                        if let timestampDate {
                            lastTaskSignalAt = timestampDate
                        }
                        if let timestamp {
                            lastActivityAt = timestamp
                        }
                    default:
                        break
                    }

                    if payloadType == "message" {
                        let role = payload["role"] as? String
                        if let text = extractTextFromCodexPayload(payload) {
                            if let cwd = extractCWDFromEnvironmentContext(text) {
                                cwdEnv = cwd
                            }
                            if let normalized = normalizeCodexMessage(text),
                               let role,
                               role == "assistant" || role == "user" {
                                lastMessage = normalized
                                lastRole = role
                                if let timestamp {
                                    lastActivityAt = timestamp
                                }
                            }
                        }
                    }
                }
            case "event_msg":
                if let payload = json["payload"] as? [String: Any] {
                    let payloadType = payload["type"] as? String ?? ""

                    switch payloadType {
                    case "user_message":
                        if let message = payload["message"] as? String {
                            if let cwd = extractCWDFromEnvironmentContext(message) {
                                cwdEnv = cwd
                            }
                            if let normalized = normalizeCodexMessage(message) {
                                lastMessage = normalized
                                lastRole = "user"
                            }
                        }

                        if let timestampDate {
                            lastUserMessageAt = timestampDate
                            lastTaskSignalAt = timestampDate
                        }
                        if let timestamp {
                            lastActivityAt = timestamp
                        }
                    case "task_started":
                        if let timestampDate {
                            lastTaskStartedAt = timestampDate
                            lastTaskSignalAt = timestampDate
                        }
                        if let timestamp {
                            lastActivityAt = timestamp
                        }
                    case "agent_reasoning", "agent_message":
                        if let timestampDate {
                            lastTaskSignalAt = timestampDate
                        }
                        if let timestamp {
                            lastActivityAt = timestamp
                        }
                    case "task_complete":
                        if let timestampDate {
                            lastTerminalEventAt = max(lastTerminalEventAt ?? .distantPast, timestampDate)
                        }
                        if let timestamp {
                            lastActivityAt = timestamp
                        }
                    case "turn_aborted":
                        if let timestampDate {
                            lastInterruptAt = timestampDate
                            lastTerminalEventAt = max(lastTerminalEventAt ?? .distantPast, timestampDate)
                        }
                        if let timestamp {
                            lastActivityAt = timestamp
                        }
                    case "thread_rolled_back", "item_completed":
                        if let timestampDate {
                            lastTerminalEventAt = max(lastTerminalEventAt ?? .distantPast, timestampDate)
                        }
                        if let timestamp {
                            lastActivityAt = timestamp
                        }
                    default:
                        break
                    }
                }
            default:
                continue
            }
        }

        let pendingTrigger = [lastTaskStartedAt, lastUserMessageAt, lastTaskSignalAt].compactMap { $0 }.max()
        let hasPendingTask: Bool
        if let pendingTrigger {
            hasPendingTask = isDate(pendingTrigger, newerThan: lastTerminalEventAt)
        } else {
            hasPendingTask = false
        }

        let cwd = selectBestCodexCWD(cwdTurn: cwdTurn, cwdEnv: cwdEnv, cwdMeta: cwdMeta)

        return CodexSessionFile(
            path: path,
            modified: modified,
            cwd: cwd,
            sessionID: sessionID,
            lastMessage: lastMessage,
            lastRole: lastRole,
            lastActivityAt: lastActivityAt,
            hasPendingTask: hasPendingTask,
            lastTaskSignalAt: lastTaskSignalAt,
            lastInterruptAt: lastInterruptAt,
            lastTerminalEventAt: lastTerminalEventAt
        )
    }

    private func extractTextFromCodexPayload(_ payload: [String: Any]) -> String? {
        guard let content = payload["content"] as? [Any] else {
            return nil
        }

        var chunks: [String] = []
        for item in content {
            guard let dict = item as? [String: Any] else { continue }
            let type = dict["type"] as? String ?? ""
            if (type == "output_text" || type == "input_text"),
               let text = dict["text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chunks.append(text)
            }
        }

        guard !chunks.isEmpty else {
            return nil
        }
        return chunks.joined(separator: "\n")
    }

    private func normalizeCodexMessage(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !SessionParsingSupport.shouldSuppressPreviewMessage(trimmed) else {
            return nil
        }

        return SessionParsingSupport.truncate(trimmed, maxChars: 5000)
    }

    private func extractCWDFromEnvironmentContext(_ text: String) -> String? {
        guard let startRange = text.range(of: "<cwd>") else {
            return nil
        }
        let from = text[startRange.upperBound...]
        guard let endRange = from.range(of: "</cwd>") else {
            return nil
        }
        let value = from[..<endRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func selectBestCodexCWD(cwdTurn: String?, cwdEnv: String?, cwdMeta: String?) -> String? {
        for candidate in [cwdTurn, cwdEnv, cwdMeta] {
            guard let candidate else { continue }
            let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty && value != "/" {
                return value
            }
        }

        for candidate in [cwdTurn, cwdEnv, cwdMeta] {
            guard let candidate else { continue }
            let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }

        return nil
    }

    private func buildSession(from file: CodexSessionFile, process: AgentProcess) -> Session? {
        let projectPath = file.cwd ?? process.cwd ?? "/"
        let projectName = SessionParsingSupport.projectName(from: projectPath)

        let status = determineCodexStatus(
            cpuUsage: process.cpuUsage,
            lastRole: file.lastRole,
            modified: file.modified,
            hasPendingTask: file.hasPendingTask,
            lastTaskSignalAt: file.lastTaskSignalAt,
            lastInterruptAt: file.lastInterruptAt,
            lastTerminalEventAt: file.lastTerminalEventAt
        )

        let lastActivityAt = file.lastActivityAt ?? SessionParsingSupport.formatISODate(file.modified)

        let sessionID = URL(fileURLWithPath: file.path).deletingPathExtension().lastPathComponent
        let resolvedID: String
        if !sessionID.isEmpty {
            resolvedID = sessionID
        } else if let fileSessionID = file.sessionID, !fileSessionID.isEmpty {
            resolvedID = fileSessionID
        } else {
            resolvedID = "codex-\(process.pid)"
        }

        let isBackground = isBackgroundSession(
            projectPath: projectPath,
            lastMessage: file.lastMessage,
            cpuUsage: process.cpuUsage
        )

        return Session(
            id: resolvedID,
            agentType: .codex,
            projectName: projectName,
            projectPath: projectPath,
            gitBranch: nil,
            githubUrl: nil,
            status: status,
            lastMessage: file.lastMessage,
            lastMessageRole: SessionParsingSupport.messageRole(from: file.lastRole),
            lastActivityAt: lastActivityAt,
            pid: process.pid,
            cpuUsage: process.cpuUsage,
            memoryBytes: process.memoryBytes,
            activeSubagentCount: 0,
            isBackground: isBackground,
            sessionFilePath: file.path
        )
    }

    private func determineCodexStatus(
        cpuUsage: Double,
        lastRole: String?,
        modified: Date,
        hasPendingTask: Bool,
        lastTaskSignalAt: Date?,
        lastInterruptAt: Date?,
        lastTerminalEventAt: Date?
    ) -> SessionStatus {
        if let lastInterruptAt {
            let interruptAgeSeconds = Date().timeIntervalSince(lastInterruptAt)
            let recentInterrupt = interruptAgeSeconds <= 90
            let terminalAfterInterrupt = (lastTerminalEventAt ?? .distantPast) >= lastInterruptAt
            if recentInterrupt && terminalAfterInterrupt && !hasPendingTask {
                return .waiting
            }
        }

        if hasPendingTask {
            let referenceDate = lastTaskSignalAt ?? modified
            if Date().timeIntervalSince(referenceDate) <= 3 * 60 {
                return .processing
            }
        }

        var status: SessionStatus
        if cpuUsage > 15 {
            status = .processing
        } else if lastRole == "user" {
            let referenceDate = lastTaskSignalAt ?? modified
            let recentUserPrompt = Date().timeIntervalSince(referenceDate) <= 60
            status = recentUserPrompt ? .processing : .waiting
        } else {
            status = .waiting
        }

        guard status == .waiting else {
            return status
        }

        let age = Date().timeIntervalSince(modified)
        if age >= 10 * 60 {
            return .stale
        }
        if age >= 5 * 60 {
            return .idle
        }

        return .waiting
    }

    private func isDate(_ candidate: Date, newerThan baseline: Date?) -> Bool {
        guard let baseline else {
            return true
        }
        return candidate > baseline
    }

    private func isBackgroundSession(projectPath: String, lastMessage: String?, cpuUsage: Double) -> Bool {
        let noMessage = (lastMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard noMessage else {
            return false
        }

        if projectPath == "/" {
            return true
        }

        return cpuUsage <= 1.0
    }

    private func buildFallbackSession(process: AgentProcess) -> Session {
        let projectPath = process.cwd ?? "/"
        let projectName = SessionParsingSupport.projectName(from: projectPath)
        let status: SessionStatus = process.cpuUsage > 15 ? .processing : .stale

        return Session(
            id: "codex-\(process.pid)",
            agentType: .codex,
            projectName: projectName,
            projectPath: projectPath,
            gitBranch: nil,
            githubUrl: nil,
            status: status,
            lastMessage: nil,
            lastMessageRole: nil,
            lastActivityAt: SessionParsingSupport.formatISODate(Date()),
            pid: process.pid,
            cpuUsage: process.cpuUsage,
            memoryBytes: process.memoryBytes,
            activeSubagentCount: 0,
            isBackground: isBackgroundSession(projectPath: projectPath, lastMessage: nil, cpuUsage: process.cpuUsage)
        )
    }
}
