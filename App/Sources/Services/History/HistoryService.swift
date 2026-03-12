import Foundation

final class HistoryService {
    private struct MetadataCacheEntry {
        let modifiedDate: Date
        let projectPath: String
        let conversation: HistoryConversation
    }

    private struct DetailsCacheEntry {
        let modifiedDate: Date
        let conversation: HistoryConversation
    }

    private var metadataCache: [String: MetadataCacheEntry] = [:]
    private var detailsCache: [String: DetailsCacheEntry] = [:]
    private static let minimumFileSize: Int64 = 1024
    private(set) var hadOlderHistoryInLastLoad = false

    func loadAllProjects(modifiedSince: Date?) -> [HistoryProject] {
        hadOlderHistoryInLastLoad = false
        let claudeEntries = scanClaudeDirectories(modifiedSince: modifiedSince)
        let codexEntries = scanCodexDirectories(modifiedSince: modifiedSince)
        let all = claudeEntries + codexEntries
        return groupByProject(all)
    }

    func loadConversationDetails(for conversation: HistoryConversation) -> HistoryConversation? {
        let url = URL(fileURLWithPath: conversation.filePath)
        guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return nil
        }

        let modifiedDate = attrs.contentModificationDate ?? conversation.lastActivityAt
        let fileSize = Int64(attrs.fileSize ?? Int(conversation.fileSize))

        if let cached = detailsCache[conversation.filePath], cached.modifiedDate == modifiedDate {
            return cached.conversation
        }

        let parsed: HistoryConversation?
        switch conversation.agentType {
        case .claude:
            parsed = parseClaudeSessionDetailsFile(
                url: url,
                modifiedDate: modifiedDate,
                fileSize: fileSize
            )
        case .codex:
            parsed = parseCodexSessionDetailsFile(
                url: url,
                modifiedDate: modifiedDate,
                fileSize: fileSize
            )?.conversation
        case .opencode:
            parsed = nil
        }

        guard let parsed else { return nil }
        detailsCache[conversation.filePath] = DetailsCacheEntry(
            modifiedDate: modifiedDate,
            conversation: parsed
        )
        return parsed
    }

    func clearCache() {
        metadataCache = [:]
        detailsCache = [:]
    }

    // MARK: - Claude scanning

    private func scanClaudeDirectories(modifiedSince: Date?) -> [(projectPath: String, conversation: HistoryConversation)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
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
            }
        }

        var seen: Set<String> = []
        let deduped = roots.filter { seen.insert($0.path).inserted }

        var results: [(projectPath: String, conversation: HistoryConversation)] = []
        for root in deduped {
            results.append(contentsOf: scanClaudeProjectsRoot(root, modifiedSince: modifiedSince))
        }
        return results
    }

    private func scanClaudeProjectsRoot(
        _ root: URL,
        modifiedSince: Date?
    ) -> [(projectPath: String, conversation: HistoryConversation)] {
        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [(projectPath: String, conversation: HistoryConversation)] = []

        for projectDir in projectDirs {
            let isDir = (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }

            guard let files = try? FileManager.default.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            let projectPath = SessionParsingSupport.convertClaudeDirectoryNameToPath(projectDir.lastPathComponent)

            for file in files {
                guard file.pathExtension == "jsonl" else { continue }

                let fileName = file.deletingPathExtension().lastPathComponent
                if fileName.hasPrefix("agent-") { continue }

                guard let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
                    continue
                }

                let fileSize = Int64(attrs.fileSize ?? 0)
                guard fileSize >= Self.minimumFileSize else { continue }

                let modifiedDate = attrs.contentModificationDate ?? .distantPast
                if let modifiedSince, modifiedDate < modifiedSince {
                    hadOlderHistoryInLastLoad = true
                    continue
                }

                if let cached = metadataCache[file.path], cached.modifiedDate == modifiedDate {
                    results.append((projectPath: cached.projectPath, conversation: cached.conversation))
                    continue
                }

                if let conversation = parseClaudeSessionMetadataFile(
                    url: file,
                    modifiedDate: modifiedDate,
                    fileSize: fileSize
                ) {
                    metadataCache[file.path] = MetadataCacheEntry(
                        modifiedDate: modifiedDate,
                        projectPath: projectPath,
                        conversation: conversation
                    )
                    detailsCache.removeValue(forKey: file.path)
                    results.append((projectPath: projectPath, conversation: conversation))
                }
            }
        }

        return results
    }

    private func parseClaudeSessionMetadataFile(
        url: URL,
        modifiedDate: Date,
        fileSize: Int64
    ) -> HistoryConversation? {
        let lines = SessionParsingSupport.parseJSONLines(url: url)
        guard !lines.isEmpty else { return nil }

        var sessionID: String?
        var gitBranch: String?
        var summaryPreview: String?

        for entry in lines {
            let type = (entry["type"] as? String)?.lowercased() ?? ""

            if sessionID == nil {
                sessionID = entry["sessionId"] as? String
            }
            if gitBranch == nil {
                gitBranch = entry["gitBranch"] as? String
            }

            guard summaryPreview == nil else { continue }
            guard type == "user" else { continue }

            guard let messageBody = entry["message"] as? [String: Any],
                  let content = messageBody["content"],
                  let role = messageBody["role"] as? String else {
                continue
            }
            guard role == "user" else { continue }

            if SessionParsingSupport.isLocalClaudeCommand(content: content) { continue }
            if SessionParsingSupport.isInterruptedRequest(content: content) { continue }
            if SessionParsingSupport.hasBlock(ofType: "tool_result", in: content) { continue }

            guard let text = SessionParsingSupport.extractText(from: content),
                  !SessionParsingSupport.shouldSuppressPreviewMessage(text) else {
                continue
            }

            summaryPreview = text
        }

        guard let summaryPreview else { return nil }

        return HistoryConversation(
            filePath: url.path,
            agentType: .claude,
            sessionID: sessionID ?? url.deletingPathExtension().lastPathComponent,
            gitBranch: gitBranch,
            lastActivityAt: modifiedDate,
            fileSize: fileSize,
            summaryPreview: summaryPreview
        )
    }

    private func parseClaudeSessionDetailsFile(
        url: URL,
        modifiedDate: Date,
        fileSize: Int64
    ) -> HistoryConversation? {
        let lines = SessionParsingSupport.parseJSONLines(url: url)
        guard !lines.isEmpty else { return nil }

        var sessionID: String?
        var gitBranch: String?
        var lastTimestamp: Date?
        var userMessages: [HistoryMessage] = []
        var lastAssistantReply: HistoryMessage?

        for entry in lines {
            let type = (entry["type"] as? String)?.lowercased() ?? ""
            let timestamp = entry["timestamp"] as? String
            let timestampDate = SessionParsingSupport.parseISODate(timestamp)

            if sessionID == nil {
                sessionID = entry["sessionId"] as? String
            }
            if gitBranch == nil {
                gitBranch = entry["gitBranch"] as? String
            }
            if let timestampDate {
                lastTimestamp = timestampDate
            }

            guard let messageBody = entry["message"] as? [String: Any],
                  let content = messageBody["content"],
                  let role = messageBody["role"] as? String else {
                continue
            }

            if SessionParsingSupport.isLocalClaudeCommand(content: content) { continue }
            if SessionParsingSupport.isInterruptedRequest(content: content) { continue }
            if SessionParsingSupport.hasBlock(ofType: "tool_result", in: content) { continue }

            guard let text = SessionParsingSupport.extractText(from: content),
                  !SessionParsingSupport.shouldSuppressPreviewMessage(text) else {
                continue
            }

            let message = HistoryMessage(
                role: role == "user" ? .user : .assistant,
                text: text,
                timestamp: timestampDate
            )

            switch type {
            case "user":
                if role == "user" {
                    userMessages.append(message)
                }
            case "assistant":
                if role == "assistant" {
                    lastAssistantReply = message
                }
            default:
                break
            }
        }

        guard !userMessages.isEmpty else { return nil }

        return HistoryConversation(
            filePath: url.path,
            agentType: .claude,
            sessionID: sessionID ?? url.deletingPathExtension().lastPathComponent,
            gitBranch: gitBranch,
            lastActivityAt: lastTimestamp ?? modifiedDate,
            fileSize: fileSize,
            userMessages: userMessages,
            lastAssistantReply: lastAssistantReply
        )
    }

    // MARK: - Codex scanning

    private func scanCodexDirectories(modifiedSince: Date?) -> [(projectPath: String, conversation: HistoryConversation)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent(".codex/sessions", isDirectory: true),
            home.appendingPathComponent(".codex-profiles/work/sessions", isDirectory: true),
            home.appendingPathComponent(".codex-profiles/personal/sessions", isDirectory: true)
        ]

        var seen: Set<String> = []
        var results: [(projectPath: String, conversation: HistoryConversation)] = []

        for root in roots {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            guard seen.insert(root.path).inserted else { continue }
            scanCodexDirectoryRecursively(root, modifiedSince: modifiedSince, into: &results)
        }

        return results
    }

    private func scanCodexDirectoryRecursively(
        _ directory: URL,
        modifiedSince: Date?,
        into results: inout [(projectPath: String, conversation: HistoryConversation)]
    ) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])

            if values?.isDirectory == true {
                scanCodexDirectoryRecursively(entry, modifiedSince: modifiedSince, into: &results)
                continue
            }

            guard entry.pathExtension == "jsonl" else { continue }

            let fileName = entry.deletingPathExtension().lastPathComponent
            if fileName.hasPrefix("agent-") { continue }

            let fileSize = Int64(values?.fileSize ?? 0)
            guard fileSize >= Self.minimumFileSize else { continue }

            let modifiedDate = values?.contentModificationDate ?? .distantPast
            if let modifiedSince, modifiedDate < modifiedSince {
                hadOlderHistoryInLastLoad = true
                continue
            }

            if let cached = metadataCache[entry.path], cached.modifiedDate == modifiedDate {
                results.append((projectPath: cached.projectPath, conversation: cached.conversation))
                continue
            }

            if let parsed = parseCodexSessionMetadataFile(url: entry, modifiedDate: modifiedDate, fileSize: fileSize) {
                metadataCache[entry.path] = MetadataCacheEntry(
                    modifiedDate: modifiedDate,
                    projectPath: parsed.projectPath,
                    conversation: parsed.conversation
                )
                detailsCache.removeValue(forKey: entry.path)
                results.append(parsed)
            }
        }
    }

    private func parseCodexSessionMetadataFile(
        url: URL,
        modifiedDate: Date,
        fileSize: Int64
    ) -> (projectPath: String, conversation: HistoryConversation)? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        var sessionID: String?
        var cwdMeta: String?
        var cwdTurn: String?
        var cwdEnv: String?
        var summaryPreview: String?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let lineType = json["type"] as? String ?? ""
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
                if let payload = json["payload"] as? [String: Any],
                   (payload["type"] as? String) == "message" {
                    let role = payload["role"] as? String
                    if let messageText = extractCodexText(from: payload) {
                        if let cwd = extractCWDTag(messageText) {
                            cwdEnv = cwd
                        }
                        if summaryPreview == nil,
                           role == "user",
                           let normalized = normalizeCodexText(messageText) {
                            summaryPreview = normalized
                        }
                    }
                }
            case "event_msg":
                if let payload = json["payload"] as? [String: Any],
                   summaryPreview == nil {
                    let payloadType = payload["type"] as? String ?? ""
                    if payloadType == "user_message",
                       let message = payload["message"] as? String {
                        if let cwd = extractCWDTag(message) {
                            cwdEnv = cwd
                        }
                        if let normalized = normalizeCodexText(message) {
                            summaryPreview = normalized
                        }
                    }
                }
            default:
                break
            }

            if summaryPreview != nil && selectBestCWD(cwdTurn: cwdTurn, cwdEnv: cwdEnv, cwdMeta: cwdMeta) != nil {
                break
            }
        }

        guard let summaryPreview else { return nil }

        let cwd = selectBestCWD(cwdTurn: cwdTurn, cwdEnv: cwdEnv, cwdMeta: cwdMeta)
        let projectPath = cwd ?? "/"

        let conversation = HistoryConversation(
            filePath: url.path,
            agentType: .codex,
            sessionID: sessionID ?? url.deletingPathExtension().lastPathComponent,
            gitBranch: nil,
            lastActivityAt: modifiedDate,
            fileSize: fileSize,
            summaryPreview: summaryPreview
        )

        return (projectPath: projectPath, conversation: conversation)
    }

    private func parseCodexSessionDetailsFile(
        url: URL,
        modifiedDate: Date,
        fileSize: Int64
    ) -> (projectPath: String, conversation: HistoryConversation)? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        var sessionID: String?
        var cwdMeta: String?
        var cwdTurn: String?
        var cwdEnv: String?
        var lastTimestamp: Date?
        var userMessages: [HistoryMessage] = []
        var lastAssistantReply: HistoryMessage?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let lineType = json["type"] as? String ?? ""
            let timestamp = json["timestamp"] as? String
            let timestampDate = SessionParsingSupport.parseISODate(timestamp)

            if let timestampDate {
                lastTimestamp = timestampDate
            }

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
                if let payload = json["payload"] as? [String: Any],
                   (payload["type"] as? String) == "message" {
                    let role = payload["role"] as? String
                    if let messageText = extractCodexText(from: payload) {
                        if let cwd = extractCWDTag(messageText) {
                            cwdEnv = cwd
                        }
                        if let normalized = normalizeCodexText(messageText) {
                            if role == "user" {
                                userMessages.append(HistoryMessage(role: .user, text: normalized, timestamp: timestampDate))
                            } else if role == "assistant" {
                                lastAssistantReply = HistoryMessage(role: .assistant, text: normalized, timestamp: timestampDate)
                            }
                        }
                    }
                }
            case "event_msg":
                if let payload = json["payload"] as? [String: Any] {
                    let payloadType = payload["type"] as? String ?? ""
                    if payloadType == "user_message",
                       let message = payload["message"] as? String {
                        if let cwd = extractCWDTag(message) {
                            cwdEnv = cwd
                        }
                        if let normalized = normalizeCodexText(message) {
                            userMessages.append(HistoryMessage(role: .user, text: normalized, timestamp: timestampDate))
                        }
                    }
                }
            default:
                break
            }
        }

        guard !userMessages.isEmpty else { return nil }

        let cwd = selectBestCWD(cwdTurn: cwdTurn, cwdEnv: cwdEnv, cwdMeta: cwdMeta)
        let projectPath = cwd ?? "/"

        let conversation = HistoryConversation(
            filePath: url.path,
            agentType: .codex,
            sessionID: sessionID ?? url.deletingPathExtension().lastPathComponent,
            gitBranch: nil,
            lastActivityAt: lastTimestamp ?? modifiedDate,
            fileSize: fileSize,
            userMessages: userMessages,
            lastAssistantReply: lastAssistantReply
        )

        return (projectPath: projectPath, conversation: conversation)
    }

    private func extractCodexText(from payload: [String: Any]) -> String? {
        guard let content = payload["content"] as? [Any] else { return nil }
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
        return chunks.isEmpty ? nil : chunks.joined(separator: "\n")
    }

    private func normalizeCodexText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !SessionParsingSupport.shouldSuppressPreviewMessage(trimmed) else { return nil }
        return trimmed
    }

    private func extractCWDTag(_ text: String) -> String? {
        guard let startRange = text.range(of: "<cwd>") else { return nil }
        let from = text[startRange.upperBound...]
        guard let endRange = from.range(of: "</cwd>") else { return nil }
        let value = from[..<endRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func selectBestCWD(cwdTurn: String?, cwdEnv: String?, cwdMeta: String?) -> String? {
        for candidate in [cwdTurn, cwdEnv, cwdMeta] {
            guard let candidate else { continue }
            let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty && value != "/" {
                return value
            }
        }
        return nil
    }

    // MARK: - Grouping

    private func groupByProject(
        _ entries: [(projectPath: String, conversation: HistoryConversation)]
    ) -> [HistoryProject] {
        var byPath: [String: [HistoryConversation]] = [:]
        for entry in entries {
            byPath[entry.projectPath, default: []].append(entry.conversation)
        }

        return byPath.map { path, convos in
            let sorted = convos.sorted { $0.lastActivityAt > $1.lastActivityAt }
            return HistoryProject(projectPath: path, conversations: sorted)
        }
    }
}
