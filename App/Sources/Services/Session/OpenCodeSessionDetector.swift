import Foundation

final class OpenCodeSessionDetector: AgentSessionDetecting {
    let agentType: AgentType = .opencode

    private let processService: ProcessIntrospectionService

    init(processService: ProcessIntrospectionService) {
        self.processService = processService
    }

    func detectSessions() -> [Session] {
        let processes = findOpenCodeProcesses()
        guard !processes.isEmpty else {
            return []
        }

        let storagePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/storage", isDirectory: true)

        guard FileManager.default.fileExists(atPath: storagePath.path) else {
            return []
        }

        var sessions: [Session] = []
        var matchedPIDs: Set<Int> = []

        for process in processes {
            guard let activeFile = process.activeSessionFile,
                  let openSession = loadOpenCodeSession(filePath: activeFile)
            else {
                continue
            }

            let projectPath = process.cwd?.isEmpty == false ? process.cwd! : openSession.directory
            sessions.append(buildSession(storagePath: storagePath, openSession: openSession, process: process, projectPath: projectPath, filePath: activeFile))
            matchedPIDs.insert(process.pid)
        }

        let unmatched = processes.filter { !matchedPIDs.contains($0.pid) }
        guard !unmatched.isEmpty else {
            return sessions
        }

        var cwdToProcess: [String: AgentProcess] = [:]
        for process in unmatched {
            if let cwd = process.cwd {
                cwdToProcess[cwd] = process
            }
        }

        let projects = loadOpenCodeProjects(storagePath: storagePath)

        for project in projects where project.id != "global" {
            guard let process = findMatchingProcess(cwdToProcess: cwdToProcess, project: project) else {
                continue
            }

            matchedPIDs.insert(process.pid)
            if let session = latestSessionForProject(storagePath: storagePath, project: project) {
                let path = process.cwd ?? project.worktree
                sessions.append(buildSession(storagePath: storagePath, openSession: session, process: process, projectPath: path))
            }
        }

        for process in processes where !matchedPIDs.contains(process.pid) {
            guard let cwd = process.cwd,
                  let globalSession = latestSessionInDirectory(
                      directory: storagePath.appendingPathComponent("session/global", isDirectory: true),
                      filterDirectory: cwd
                  )
            else {
                continue
            }

            sessions.append(
                buildSession(
                    storagePath: storagePath,
                    openSession: globalSession,
                    process: process,
                    projectPath: globalSession.directory
                )
            )
        }

        return sessions
    }

    private func findOpenCodeProcesses() -> [AgentProcess] {
        processService.listProcesses().compactMap { snapshot in
            let first = snapshot.firstArguments(maxCount: 1).first?.lowercased() ?? ""
            let executable = snapshot.executableName
            let isOpenCode = executable == "opencode" || first == "opencode" || first.hasSuffix("/opencode")
            guard isOpenCode else {
                return nil
            }

            let cwd = processService.workingDirectory(pid: snapshot.pid)
            let activeFile = processService.newestOpenFile(
                pid: snapshot.pid,
                pathContains: "/opencode/storage/session/",
                suffix: ".json"
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
                dataHome: nil,
                startDate: SessionParsingSupport.processStartDate(elapsed: snapshot.elapsed)
            )
        }
    }

    private func loadOpenCodeProjects(storagePath: URL) -> [OpenCodeProject] {
        let projectDirectory = storagePath.appendingPathComponent("project", isDirectory: true)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: projectDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { file in
                guard let data = try? Data(contentsOf: file) else { return nil }
                return try? JSONDecoder().decode(OpenCodeProject.self, from: data)
            }
    }

    private func loadOpenCodeSession(filePath: String) -> OpenCodeSession? {
        let url = URL(fileURLWithPath: filePath)
        guard url.pathExtension == "json",
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }

        return try? JSONDecoder().decode(OpenCodeSession.self, from: data)
    }

    private func findMatchingProcess(cwdToProcess: [String: AgentProcess], project: OpenCodeProject) -> AgentProcess? {
        for (cwd, process) in cwdToProcess {
            if cwd == project.worktree || cwd.hasPrefix(project.worktree + "/") {
                return process
            }

            if project.sandboxes.contains(where: { sandbox in
                cwd == sandbox || cwd.hasPrefix(sandbox + "/")
            }) {
                return process
            }
        }

        return nil
    }

    private func latestSessionForProject(storagePath: URL, project: OpenCodeProject) -> OpenCodeSession? {
        let directory = storagePath.appendingPathComponent("session/\(project.id)", isDirectory: true)
        return latestSessionInDirectory(directory: directory, filterDirectory: nil)
    }

    private func latestSessionInDirectory(directory: URL, filterDirectory: String?) -> OpenCodeSession? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var latest: OpenCodeSession?

        for file in files where file.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: file),
                let session = try? JSONDecoder().decode(OpenCodeSession.self, from: data)
            else {
                continue
            }

            if let filterDirectory {
                let directory = session.directory
                if !(filterDirectory == directory || filterDirectory.hasPrefix(directory + "/")) {
                    continue
                }
            }

            if latest == nil || session.time.updated > (latest?.time.updated ?? 0) {
                latest = session
            }
        }

        return latest
    }

    private func buildSession(storagePath: URL, openSession: OpenCodeSession, process: AgentProcess, projectPath: String, filePath: String? = nil) -> Session {
        let lastMessage = lastMessageForOpenCodeSession(storagePath: storagePath, sessionID: openSession.id)

        let status = determineOpenCodeStatus(
            cpuUsage: process.cpuUsage,
            lastRole: lastMessage.role,
            updatedMs: openSession.time.updated,
            hasPendingTask: lastMessage.hasPendingTask,
            lastTaskSignalMs: lastMessage.lastTaskSignalMs
        )

        let displayMessage: String?
        if let text = lastMessage.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            displayMessage = text
        } else if !openSession.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            displayMessage = openSession.title
        } else {
            displayMessage = nil
        }

        return Session(
            id: openSession.id,
            agentType: .opencode,
            projectName: SessionParsingSupport.projectName(from: projectPath),
            projectPath: projectPath,
            gitBranch: nil,
            githubUrl: nil,
            status: status,
            lastMessage: displayMessage,
            lastMessageRole: SessionParsingSupport.messageRole(from: lastMessage.role),
            lastActivityAt: timestampMS(toISO: openSession.time.updated),
            pid: process.pid,
            cpuUsage: process.cpuUsage,
            memoryBytes: process.memoryBytes,
            activeSubagentCount: 0,
            isBackground: false,
            sessionFilePath: filePath
        )
    }

    private func determineOpenCodeStatus(
        cpuUsage: Double,
        lastRole: String?,
        updatedMs: UInt64,
        hasPendingTask: Bool,
        lastTaskSignalMs: UInt64?
    ) -> SessionStatus {
        if hasPendingTask {
            let referenceMs = lastTaskSignalMs ?? updatedMs
            let ageSeconds = Int(Date().timeIntervalSince1970) - Int(referenceMs / 1000)
            if ageSeconds <= 3 * 60 {
                return .processing
            }
        }

        var status: SessionStatus
        if cpuUsage > 15 {
            status = .processing
        } else if lastRole == "assistant" {
            status = .waiting
        } else if lastRole == "user" {
            let referenceMs = lastTaskSignalMs ?? updatedMs
            let ageSeconds = Int(Date().timeIntervalSince1970) - Int(referenceMs / 1000)
            status = ageSeconds <= 60 ? .processing : .waiting
        } else {
            status = .waiting
        }

        guard status == .waiting else {
            return status
        }

        let ageSeconds = Int(Date().timeIntervalSince1970) - Int(updatedMs / 1000)
        if ageSeconds >= 10 * 60 {
            return .stale
        }
        if ageSeconds >= 5 * 60 {
            return .idle
        }

        return .waiting
    }

    private func timestampMS(toISO updatedMs: UInt64) -> String {
        let seconds = TimeInterval(updatedMs) / 1000
        return SessionParsingSupport.formatISODate(Date(timeIntervalSince1970: seconds))
    }

    private func lastMessageForOpenCodeSession(
        storagePath: URL,
        sessionID: String
    ) -> (role: String?, text: String?, hasPendingTask: Bool, lastTaskSignalMs: UInt64?) {
        let messageDirectory = storagePath.appendingPathComponent("message/\(sessionID)", isDirectory: true)
        guard let messageFiles = try? FileManager.default.contentsOfDirectory(
            at: messageDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return (nil, nil, false, nil)
        }

        var messages: [OpenCodeMessage] = []
        for file in messageFiles where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let message = try? JSONDecoder().decode(OpenCodeMessage.self, from: data)
            else {
                continue
            }
            messages.append(message)
        }

        messages.sort { $0.time.created > $1.time.created }
        guard !messages.isEmpty else {
            return (nil, nil, false, nil)
        }

        var newestState: OpenCodeMessageState?
        var newestSignalMs: UInt64?
        var previewText: String?
        var latestUserPromptMs: UInt64?
        var latestAssistantCompletionMs: UInt64?

        for message in messages {
            let state = openCodeMessageState(storagePath: storagePath, message: message)

            if newestState == nil {
                newestState = state
                newestSignalMs = max(message.time.created, message.time.updated)
            }

            if previewText == nil, let text = state.text {
                previewText = text
            }

            if latestUserPromptMs == nil,
               (state.role?.lowercased() == "user") {
                latestUserPromptMs = state.createdMs
            }

            if latestAssistantCompletionMs == nil,
               (state.role?.lowercased() == "assistant"),
               (state.text != nil || state.hasStepFinish) {
                latestAssistantCompletionMs = state.createdMs
            }
        }

        let hasPendingTask: Bool = {
            if let newestState {
                let role = newestState.role?.lowercased()
                if role == "user" {
                    return true
                }

                if role == "assistant" {
                    let hasActiveStep = newestState.hasStepStart && !newestState.hasStepFinish
                    let hasRunningTool = newestState.hasTool && !newestState.hasStepFinish
                    let hasReasoningOnly = newestState.hasReasoning &&
                        newestState.text == nil &&
                        !newestState.hasStepFinish
                    if hasActiveStep || hasRunningTool || hasReasoningOnly {
                        return true
                    }
                }
            }

            if let userMs = latestUserPromptMs {
                return userMs > (latestAssistantCompletionMs ?? 0)
            }

            return false
        }()

        return (
            newestState?.role,
            previewText,
            hasPendingTask,
            newestSignalMs ?? latestUserPromptMs ?? latestAssistantCompletionMs
        )
    }

    private func openCodeMessageState(storagePath: URL, message: OpenCodeMessage) -> OpenCodeMessageState {
        let messageID = message.id
        let partDirectory = storagePath.appendingPathComponent("part/\(messageID)", isDirectory: true)
        guard let partFiles = try? FileManager.default.contentsOfDirectory(
            at: partDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return OpenCodeMessageState(
                role: message.role,
                text: nil,
                createdMs: message.time.created,
                hasStepStart: false,
                hasStepFinish: false,
                hasTool: false,
                hasReasoning: false
            )
        }

        var textContent: String?
        var reasoningContent: String?
        var hasStepStart = false
        var hasStepFinish = false
        var hasTool = false
        var hasReasoning = false

        for file in partFiles where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let part = try? JSONDecoder().decode(OpenCodePart.self, from: data)
            else {
                continue
            }

            if part.partType == "text", let text = part.text {
                textContent = text
            } else if part.partType == "reasoning" {
                hasReasoning = true
                if reasoningContent == nil {
                    reasoningContent = part.text
                }
            } else if part.partType == "step-start" {
                hasStepStart = true
            } else if part.partType == "step-finish" {
                hasStepFinish = true
            } else if part.partType == "tool" {
                hasTool = true
            }
        }

        let preview = normalizedOpenCodePreview(textContent ?? reasoningContent)

        return OpenCodeMessageState(
            role: message.role,
            text: preview,
            createdMs: message.time.created,
            hasStepStart: hasStepStart,
            hasStepFinish: hasStepFinish,
            hasTool: hasTool,
            hasReasoning: hasReasoning
        )
    }

    private func normalizedOpenCodePreview(_ content: String?) -> String? {
        guard let content else {
            return nil
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("<") && (trimmed.contains("ultrawork") || trimmed.contains("mode>")) {
            return nil
        }
        if SessionParsingSupport.shouldSuppressPreviewMessage(trimmed) {
            return nil
        }

        return SessionParsingSupport.truncate(content, maxChars: 200)
    }
}

private struct OpenCodeMessageState {
    let role: String?
    let text: String?
    let createdMs: UInt64
    let hasStepStart: Bool
    let hasStepFinish: Bool
    let hasTool: Bool
    let hasReasoning: Bool
}
