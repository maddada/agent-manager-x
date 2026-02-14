import Foundation

struct AgentProcess {
    let pid: Int
    let cpuUsage: Double
    let memoryBytes: Int64
    let cwd: String?
    let parentPID: Int
    let processGroupID: Int
    let commandLine: String
    let activeSessionFile: String?
    let dataHome: String?
}

struct ClaudeMessageData {
    let sessionID: String?
    let gitBranch: String?
    let lastTimestamp: String?
    let lastMessage: String?
    let lastUserMessage: String?
    let lastRole: String?
    let lastMessageType: String?
    let hasToolUse: Bool
    let hasToolResult: Bool
    let isLocalCommand: Bool
    let isInterrupted: Bool
    let hasPendingTask: Bool
    let lastTaskSignalAt: String?
}

struct CodexSessionFile {
    let path: String
    let modified: Date
    let cwd: String?
    let sessionID: String?
    let lastMessage: String?
    let lastRole: String?
    let lastActivityAt: String?
    let hasPendingTask: Bool
    let lastTaskSignalAt: Date?
}

struct OpenCodeProject: Decodable {
    let id: String
    let worktree: String
    let sandboxes: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        worktree = try container.decodeIfPresent(String.self, forKey: .worktree) ?? ""
        sandboxes = try container.decodeIfPresent([String].self, forKey: .sandboxes) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case worktree
        case sandboxes
    }
}

struct OpenCodeTime: Decodable {
    let created: UInt64
    let updated: UInt64

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        created = try container.decodeIfPresent(UInt64.self, forKey: .created) ?? 0
        updated = try container.decodeIfPresent(UInt64.self, forKey: .updated) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case created
        case updated
    }
}

struct OpenCodeSession: Decodable {
    let id: String
    let projectID: String
    let directory: String
    let title: String
    let time: OpenCodeTime

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        projectID = try container.decodeIfPresent(String.self, forKey: .projectID) ?? ""
        directory = try container.decodeIfPresent(String.self, forKey: .directory) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        time = try container.decodeIfPresent(OpenCodeTime.self, forKey: .time) ?? OpenCodeTime(created: 0, updated: 0)
    }

    init(id: String, projectID: String, directory: String, title: String, time: OpenCodeTime) {
        self.id = id
        self.projectID = projectID
        self.directory = directory
        self.title = title
        self.time = time
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case projectID
        case directory
        case title
        case time
    }
}

extension OpenCodeTime {
    init(created: UInt64, updated: UInt64) {
        self.created = created
        self.updated = updated
    }
}

struct OpenCodeMessage: Decodable {
    let id: String
    let sessionID: String
    let role: String
    let time: OpenCodeTime

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID
        case role
        case time
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? ""
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? ""
        time = try container.decodeIfPresent(OpenCodeTime.self, forKey: .time) ?? OpenCodeTime(created: 0, updated: 0)
    }
}

struct OpenCodePart: Decodable {
    let partType: String
    let text: String?

    private enum CodingKeys: String, CodingKey {
        case partType = "type"
        case text
    }
}

protocol AgentSessionDetecting {
    var agentType: AgentType { get }
    func detectSessions() -> [Session]
}

enum SessionParsingSupport {
    static let now: () -> Date = { Date() }

    static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let localClaudeCommands: Set<String> = [
        "/clear", "/compact", "/help", "/config", "/cost", "/doctor", "/init", "/login",
        "/logout", "/memory", "/model", "/permissions", "/pr-comments", "/review", "/status",
        "/terminal-setup", "/vim"
    ]

    static func parseISODate(_ string: String?) -> Date? {
        guard let string else { return nil }
        if let date = isoFormatterWithFractional.date(from: string) {
            return date
        }
        return isoFormatter.date(from: string)
    }

    static func formatISODate(_ date: Date) -> String {
        isoFormatterWithFractional.string(from: date)
    }

    static func ageSeconds(from timestamp: String?) -> TimeInterval? {
        guard let date = parseISODate(timestamp) else {
            return nil
        }
        return now().timeIntervalSince(date)
    }

    static func statusPriority(_ status: SessionStatus) -> Int {
        switch status {
        case .thinking, .processing: return 0
        case .waiting: return 1
        case .idle: return 2
        case .stale: return 3
        }
    }

    static func messageRole(from raw: String?) -> SessionMessageRole? {
        guard let raw = raw?.lowercased() else { return nil }
        return SessionMessageRole(rawValue: raw)
    }

    static func extractText(from content: Any?) -> String? {
        guard let content else { return nil }

        if let value = content as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : value
        }

        if let array = content as? [Any] {
            for item in array {
                if let dict = item as? [String: Any],
                   let text = dict["text"] as? String,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
            }
        }

        return nil
    }

    static func shouldSuppressPreviewMessage(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }

        let lowered = trimmed.lowercased()
        return lowered.hasPrefix("<environment_context>") ||
            lowered.hasPrefix("<permissions instructions>") ||
            lowered.hasPrefix("# agents.md instructions") ||
            lowered.hasPrefix("<turn_aborted")
    }

    static func hasBlock(ofType blockType: String, in content: Any?) -> Bool {
        guard let array = content as? [Any] else { return false }
        return array.contains { item in
            guard let dict = item as? [String: Any] else {
                return false
            }
            return (dict["type"] as? String) == blockType
        }
    }

    static func isInterruptedRequest(content: Any?) -> Bool {
        let text = extractText(from: content) ?? ""
        return text.contains("[Request interrupted by user]")
    }

    static func isLocalClaudeCommand(content: Any?) -> Bool {
        let text = (extractText(from: content) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("/") else {
            return false
        }

        return localClaudeCommands.contains { command in
            text == command || text.hasPrefix("\(command) ")
        }
    }

    static func truncate(_ value: String, maxChars: Int) -> String {
        guard value.count > maxChars else {
            return value
        }
        return String(value.prefix(maxChars)) + "..."
    }

    static func gitHubURL(for projectPath: String, shell: ShellCommandRunning) -> String? {
        let result = shell.run(
            executable: "/usr/bin/git",
            arguments: ["remote", "get-url", "origin"],
            currentDirectory: projectPath,
            environment: [:],
            timeout: 1.5
        )

        guard result.isSuccess else {
            return nil
        }

        let remote = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remote.isEmpty else {
            return nil
        }

        if remote.hasPrefix("git@github.com:") {
            var slug = remote.replacingOccurrences(of: "git@github.com:", with: "")
            if slug.hasSuffix(".git") {
                slug.removeLast(4)
            }
            return "https://github.com/\(slug)"
        }

        if remote.hasPrefix("https://github.com/") {
            if remote.hasSuffix(".git") {
                return String(remote.dropLast(4))
            }
            return remote
        }

        return nil
    }

    static func parseJSONLines(url: URL) -> [[String: Any]] {
        guard
            let data = try? Data(contentsOf: url),
            let text = String(data: data, encoding: .utf8)
        else {
            return []
        }

        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let jsonData = line.data(using: .utf8) else { return nil }
                return (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any]
            }
    }

    static func parseClaudeMessageData(url: URL) -> ClaudeMessageData? {
        let lines = parseJSONLines(url: url)
        guard !lines.isEmpty else { return nil }

        let recent = Array(lines.suffix(250))

        var sessionID: String?
        var gitBranch: String?
        var lastTimestamp: String?

        var lastRole: String?
        var lastMessageType: String?
        var hasToolUse = false
        var hasToolResult = false
        var isLocalCommand = false
        var isInterrupted = false

        var lastMessage: String?
        var lastUserMessage: String?
        var lastTaskStartedAt: Date?
        var lastTaskCompletedAt: Date?
        var lastTaskSignalAt: Date?
        var lastTaskSignalTimestamp: String?

        for entry in recent {
            let type = (entry["type"] as? String)?.lowercased() ?? ""
            let timestamp = entry["timestamp"] as? String
            let timestampDate = parseISODate(timestamp)

            func markSignal() {
                guard let timestampDate else { return }
                lastTaskSignalAt = timestampDate
                if let timestamp {
                    lastTaskSignalTimestamp = timestamp
                }
            }

            switch type {
            case "user":
                if let messageBody = entry["message"] as? [String: Any],
                   let content = messageBody["content"] {
                    // User tool_result lines are intermediate task activity, not a new prompt.
                    if hasBlock(ofType: "tool_result", in: content) {
                        markSignal()
                    } else if let timestampDate {
                        lastTaskStartedAt = timestampDate
                        markSignal()
                    }
                }
            case "assistant":
                if let messageBody = entry["message"] as? [String: Any],
                   let content = messageBody["content"] {
                    if hasBlock(ofType: "thinking", in: content) || hasBlock(ofType: "tool_use", in: content) {
                        markSignal()
                    }

                    if let text = extractText(from: content),
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       !shouldSuppressPreviewMessage(text),
                       let timestampDate {
                        lastTaskCompletedAt = timestampDate
                    }
                }
            case "progress":
                markSignal()
            case "system":
                if let subtype = (entry["subtype"] as? String)?.lowercased(),
                   (subtype.contains("stop") || subtype.contains("complete")),
                   let timestampDate {
                    lastTaskCompletedAt = timestampDate
                }
            default:
                continue
            }
        }

        for message in recent.reversed() {
            if sessionID == nil {
                sessionID = message["sessionId"] as? String
            }
            if gitBranch == nil {
                gitBranch = message["gitBranch"] as? String
            }
            if lastTimestamp == nil {
                lastTimestamp = message["timestamp"] as? String
            }

            if lastRole == nil,
               let messageBody = message["message"] as? [String: Any],
               let content = messageBody["content"] {
                lastRole = messageBody["role"] as? String
                lastMessageType = message["type"] as? String
                hasToolUse = hasBlock(ofType: "tool_use", in: content)
                hasToolResult = hasBlock(ofType: "tool_result", in: content)
                isLocalCommand = isLocalClaudeCommand(content: content)
                isInterrupted = isInterruptedRequest(content: content)
            }

            if let messageBody = message["message"] as? [String: Any],
               let text = extractText(from: messageBody["content"]),
               !SessionParsingSupport.shouldSuppressPreviewMessage(text) {
                if lastMessage == nil {
                    lastMessage = text
                }
                if (messageBody["role"] as? String) == "user", lastUserMessage == nil {
                    lastUserMessage = text
                }
            }

            if sessionID != nil, lastRole != nil, lastMessage != nil, lastUserMessage != nil {
                break
            }
        }

        let hasPendingTask: Bool
        if let lastTaskStartedAt {
            hasPendingTask = isDate(lastTaskStartedAt, newerThan: lastTaskCompletedAt)
        } else {
            hasPendingTask = false
        }

        return ClaudeMessageData(
            sessionID: sessionID,
            gitBranch: gitBranch,
            lastTimestamp: lastTimestamp,
            lastMessage: lastMessage,
            lastUserMessage: lastUserMessage,
            lastRole: lastRole,
            lastMessageType: lastMessageType,
            hasToolUse: hasToolUse,
            hasToolResult: hasToolResult,
            isLocalCommand: isLocalCommand,
            isInterrupted: isInterrupted,
            hasPendingTask: hasPendingTask,
            lastTaskSignalAt: lastTaskSignalTimestamp
        )
    }

    private static func isDate(_ candidate: Date, newerThan baseline: Date?) -> Bool {
        guard let baseline else {
            return true
        }
        return candidate > baseline
    }

    static func determineClaudeStatus(
        lastMessageType: String?,
        hasToolUse: Bool,
        hasToolResult: Bool,
        isLocalCommand: Bool,
        isInterrupted: Bool,
        fileRecentlyModified: Bool,
        messageIsStale: Bool
    ) -> SessionStatus {
        if messageIsStale && !fileRecentlyModified {
            switch lastMessageType {
            case "assistant", "user": return .waiting
            default: return .idle
            }
        }

        switch lastMessageType {
        case "assistant":
            if hasToolUse {
                return fileRecentlyModified ? .processing : .waiting
            }
            return fileRecentlyModified ? .processing : .waiting
        case "user":
            if isLocalCommand || isInterrupted {
                return .waiting
            }
            if hasToolResult {
                return fileRecentlyModified ? .thinking : .waiting
            }
            return fileRecentlyModified ? .thinking : .waiting
        default:
            return fileRecentlyModified ? .thinking : .idle
        }
    }

    static func applyIdleStaleUpgrade(baseStatus: SessionStatus, timestamp: String?) -> SessionStatus {
        guard baseStatus == .waiting || baseStatus == .idle,
              let age = ageSeconds(from: timestamp)
        else {
            return baseStatus
        }

        if age >= 10 * 60 {
            return .stale
        }
        if age >= 5 * 60 {
            return .idle
        }
        return baseStatus
    }

    static func shouldShowLastUserMessage(status: SessionStatus, lastMessage: String?) -> Bool {
        guard status == .thinking || status == .processing else {
            return false
        }

        guard let message = lastMessage?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return true
        }

        return message.isEmpty || message == "(no content)" || message == "no content"
    }

    static func projectName(from path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        return name.isEmpty ? "Unknown" : name
    }

    static func convertPathToClaudeDirectoryName(_ path: String) -> String {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var result = "-"
        var index = trimmed.startIndex

        while index < trimmed.endIndex {
            let character = trimmed[index]
            if character == "/" {
                let nextIndex = trimmed.index(after: index)
                if nextIndex < trimmed.endIndex, trimmed[nextIndex] == "." {
                    result += "--"
                    index = trimmed.index(after: nextIndex)
                    continue
                }
                result += "-"
            } else {
                result.append(character)
            }
            index = trimmed.index(after: index)
        }

        return result
    }

    static func convertClaudeDirectoryNameToPath(_ directoryName: String) -> String {
        let name = directoryName.hasPrefix("-") ? String(directoryName.dropFirst()) : directoryName
        let parts = name.split(separator: "-", omittingEmptySubsequences: false).map(String.init)

        guard !parts.isEmpty else {
            return ""
        }

        if let index = parts.firstIndex(where: { $0 == "Projects" || $0 == "UnityProjects" }) {
            let pathParts = parts[...index]
            let projectParts = parts[(index + 1)...]

            var components: [String] = Array(pathParts)
            var projectSegments: [String] = []
            var current = ""
            var inHiddenFolder = false

            for part in projectParts {
                if part.isEmpty {
                    if !current.isEmpty {
                        projectSegments.append(current)
                        current = ""
                    }
                    inHiddenFolder = true
                    continue
                }

                if inHiddenFolder {
                    if current.isEmpty {
                        current = ".\(part)"
                    } else {
                        projectSegments.append(current)
                        current = part
                    }
                } else {
                    if current.isEmpty {
                        current = part
                    } else {
                        current += "-\(part)"
                    }
                }
            }

            if !current.isEmpty {
                projectSegments.append(current)
            }

            components.append(contentsOf: projectSegments)
            return "/" + components.joined(separator: "/")
        }

        return "/" + name.replacingOccurrences(of: "-", with: "/")
    }

    static func newestFile(in directory: URL, withExtension ext: String) -> URL? {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let candidates = items.filter { $0.pathExtension == ext }

        return candidates.max { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }
    }

    static func modifiedDate(for path: String) -> Date {
        ((try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date) ?? .distantPast
    }
}

extension Session {
    var sortableLastActivityDate: Date {
        SessionParsingSupport.parseISODate(lastActivityAt) ?? .distantPast
    }
}
