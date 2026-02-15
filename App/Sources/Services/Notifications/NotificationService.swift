import Foundation

enum NotificationServiceError: Error, LocalizedError {
    case invalidSettingsFormat
    case notificationSystemNotInstalled
    case notificationSoundNotFound

    var errorDescription: String? {
        switch self {
        case .invalidSettingsFormat:
            return "settings.json is not a valid JSON object"
        case .notificationSystemNotInstalled:
            return "Notification system not installed"
        case .notificationSoundNotFound:
            return "Notification sound file not found"
        }
    }
}

final class NotificationService {
    private let fileManager: FileManager
    private let homeDirectoryURL: URL
    private let notificationScriptFilename = "notify-local-tts.sh"
    private let afplayExecutablePath = "/usr/bin/afplay"
    private var previewProcess: Process?

    init(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.homeDirectoryURL = homeDirectoryURL
    }

    func checkNotificationSystemInstalled() throws -> Bool {
        let claudeInstalled = try checkClaudeNotificationSystemInstalled()
        let codexInstalled = try checkCodexNotificationSystemInstalled()
        return claudeInstalled && codexInstalled
    }

    func installNotificationSystem() throws {
        try installClaudeNotificationSystem()
        try installCodexNotificationSystem()
    }

    func uninstallNotificationSystem() throws {
        try uninstallClaudeNotificationSystem()
        try uninstallCodexNotificationSystem()
    }

    func checkBellMode() throws -> Bool {
        let scriptPaths = installedNotificationScriptPaths()
        guard !scriptPaths.isEmpty else {
            return false
        }

        return try scriptPaths.allSatisfy { path in
            guard fileManager.fileExists(atPath: path.path) else {
                return false
            }
            let content = try String(contentsOf: path, encoding: .utf8)
            return isBellScript(content)
        }
    }

    func setBellMode(enabled: Bool, bellSoundPath: String? = nil) throws {
        guard try checkNotificationSystemInstalled() else {
            throw NotificationServiceError.notificationSystemNotInstalled
        }

        let soundPath = bellSoundPath ?? NotificationScripts.defaultBellSoundPath
        let claudeScript = enabled ? NotificationScripts.claudeBellScript(soundPath: soundPath) : NotificationScripts.claudeVoiceScript
        try writeExecutableScript(claudeScript, to: claudeScriptPath)

        for root in codexDirectoryPaths {
            let hooksDirectory = codexHooksDirectoryPath(for: root)
            try ensureDirectoryExists(at: hooksDirectory)

            let codexScript = enabled ? NotificationScripts.codexBellScript(soundPath: soundPath) : NotificationScripts.codexVoiceScript
            try writeExecutableScript(codexScript, to: codexScriptPath(for: root))
        }
    }

    func playNotificationSoundPreview(soundPath: String) throws {
        guard fileManager.fileExists(atPath: soundPath) else {
            throw NotificationServiceError.notificationSoundNotFound
        }

        stopNotificationSoundPreview()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: afplayExecutablePath)
        process.arguments = [soundPath]
        process.terminationHandler = { [weak self] _ in
            self?.previewProcess = nil
        }

        try process.run()
        previewProcess = process
    }

    func stopNotificationSoundPreview() {
        guard let process = previewProcess else {
            return
        }

        if process.isRunning {
            process.terminate()
        }
        previewProcess = nil
    }

    private func checkClaudeNotificationSystemInstalled() throws -> Bool {
        guard fileManager.fileExists(atPath: claudeSettingsPath.path) else {
            return false
        }

        let settings = try readClaudeSettingsJSON()
        return stopHooksContainsNotificationScript(settings)
    }

    private func checkCodexNotificationSystemInstalled() throws -> Bool {
        for root in codexDirectoryPaths {
            let configPath = codexConfigPath(for: root)
            let scriptPath = codexScriptPath(for: root)

            guard fileManager.fileExists(atPath: configPath.path),
                  fileManager.fileExists(atPath: scriptPath.path) else {
                return false
            }

            let content = try String(contentsOf: configPath, encoding: .utf8)
            guard codexNotifyContainsNotificationScript(in: content) else {
                return false
            }
        }

        return true
    }

    private func installClaudeNotificationSystem() throws {
        try ensureDirectoryExists(at: claudeHooksDirectoryPath)
        try writeExecutableScript(NotificationScripts.claudeVoiceScript, to: claudeScriptPath)

        try backupFileIfExists(at: claudeSettingsPath)
        var settings = try readClaudeSettingsJSONIfPresent() ?? [:]
        ensureNotificationStopHook(in: &settings)
        try writeClaudeSettingsJSON(settings)

        try backupFileIfExists(at: claudeMDPath)
        try appendVoiceInstructionsIfNeeded(at: claudeMDPath)

        for profileMDPath in claudeProfileMDPaths {
            try backupFileIfExists(at: profileMDPath)
            try appendVoiceInstructionsIfNeeded(at: profileMDPath)
        }
    }

    private func installCodexNotificationSystem() throws {
        for root in codexDirectoryPaths {
            let hooksDirectory = codexHooksDirectoryPath(for: root)
            try ensureDirectoryExists(at: hooksDirectory)

            let scriptPath = codexScriptPath(for: root)
            try writeExecutableScript(NotificationScripts.codexVoiceScript, to: scriptPath)

            let configPath = codexConfigPath(for: root)
            var configContent = ""
            if fileManager.fileExists(atPath: configPath.path) {
                try backupFileIfExists(at: configPath)
                configContent = try String(contentsOf: configPath, encoding: .utf8)
            } else {
                let directory = configPath.deletingLastPathComponent()
                try ensureDirectoryExists(at: directory)
            }

            let updatedConfigContent = ensureCodexNotifyCommand(in: configContent, scriptPath: scriptPath)
            if updatedConfigContent != configContent {
                try updatedConfigContent.write(to: configPath, atomically: true, encoding: .utf8)
            }
        }

        for agentsPath in codexAGENTSPaths {
            try backupFileIfExists(at: agentsPath)
            try appendVoiceInstructionsIfNeeded(at: agentsPath)
        }
    }

    private func uninstallClaudeNotificationSystem() throws {
        if fileManager.fileExists(atPath: claudeSettingsPath.path) {
            try backupFileIfExists(at: claudeSettingsPath)
            var settings = try readClaudeSettingsJSON()
            removeNotificationStopHooks(from: &settings)
            try writeClaudeSettingsJSON(settings)
        }

        if fileManager.fileExists(atPath: claudeMDPath.path) {
            try backupFileIfExists(at: claudeMDPath)
            let content = try String(contentsOf: claudeMDPath, encoding: .utf8)
            let updated = removeVoiceNotificationsSection(from: content)
            if updated != content {
                try updated.write(to: claudeMDPath, atomically: true, encoding: .utf8)
            }
        }

        for profileMDPath in claudeProfileMDPaths where fileManager.fileExists(atPath: profileMDPath.path) {
            try backupFileIfExists(at: profileMDPath)
            let content = try String(contentsOf: profileMDPath, encoding: .utf8)
            let updated = removeVoiceNotificationsSection(from: content)
            if updated != content {
                try updated.write(to: profileMDPath, atomically: true, encoding: .utf8)
            }
        }

        if fileManager.fileExists(atPath: claudeScriptPath.path) {
            try fileManager.removeItem(at: claudeScriptPath)
        }
    }

    private func uninstallCodexNotificationSystem() throws {
        for root in codexDirectoryPaths {
            let configPath = codexConfigPath(for: root)
            if fileManager.fileExists(atPath: configPath.path) {
                try backupFileIfExists(at: configPath)
                let content = try String(contentsOf: configPath, encoding: .utf8)
                let updated = removeCodexNotifyCommand(from: content)
                if updated != content {
                    try normalizedTextFileContent(updated).write(to: configPath, atomically: true, encoding: .utf8)
                }
            }

            let scriptPath = codexScriptPath(for: root)
            if fileManager.fileExists(atPath: scriptPath.path) {
                try fileManager.removeItem(at: scriptPath)
            }
        }

        for agentsPath in codexAGENTSPaths where fileManager.fileExists(atPath: agentsPath.path) {
            try backupFileIfExists(at: agentsPath)
            let content = try String(contentsOf: agentsPath, encoding: .utf8)
            let updated = removeVoiceNotificationsSection(from: content)
            if updated != content {
                try updated.write(to: agentsPath, atomically: true, encoding: .utf8)
            }
        }
    }

    private func appendVoiceInstructionsIfNeeded(at path: URL) throws {
        let content = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
        let updated = upsertVoiceNotificationsSection(in: content)
        if updated != content {
            try updated.write(to: path, atomically: true, encoding: .utf8)
        }
    }

    private var claudeDirectoryPath: URL {
        homeDirectoryURL.appendingPathComponent(".claude", isDirectory: true)
    }

    private var claudeHooksDirectoryPath: URL {
        claudeDirectoryPath.appendingPathComponent("hooks", isDirectory: true)
    }

    private var claudeScriptPath: URL {
        claudeHooksDirectoryPath.appendingPathComponent(notificationScriptFilename)
    }

    private var claudeSettingsPath: URL {
        claudeDirectoryPath.appendingPathComponent("settings.json")
    }

    private var claudeMDPath: URL {
        claudeDirectoryPath.appendingPathComponent("CLAUDE.md")
    }

    private var claudeProfileDirectoryPaths: [URL] {
        [
            homeDirectoryURL.appendingPathComponent(".claude-profiles/personal", isDirectory: true),
            homeDirectoryURL.appendingPathComponent(".claude-profiles/work", isDirectory: true)
        ].filter { fileManager.fileExists(atPath: $0.path) }
    }

    private var claudeProfileMDPaths: [URL] {
        claudeProfileDirectoryPaths.map { $0.appendingPathComponent("CLAUDE.md") }
    }

    private var codexDirectoryPaths: [URL] {
        [
            homeDirectoryURL.appendingPathComponent(".codex", isDirectory: true),
            homeDirectoryURL.appendingPathComponent(".codex-profiles/work", isDirectory: true),
            homeDirectoryURL.appendingPathComponent(".codex-profiles/personal", isDirectory: true)
        ].filter { fileManager.fileExists(atPath: $0.path) }
    }

    private var codexAGENTSPaths: [URL] {
        codexDirectoryPaths.map { $0.appendingPathComponent("AGENTS.md") }
    }

    private func codexHooksDirectoryPath(for root: URL) -> URL {
        root.appendingPathComponent("hooks", isDirectory: true)
    }

    private func codexScriptPath(for root: URL) -> URL {
        codexHooksDirectoryPath(for: root).appendingPathComponent(notificationScriptFilename)
    }

    private func codexConfigPath(for root: URL) -> URL {
        root.appendingPathComponent("config.toml")
    }

    private func installedNotificationScriptPaths() -> [URL] {
        var paths: [URL] = []
        var seen = Set<String>()

        if fileManager.fileExists(atPath: claudeScriptPath.path), seen.insert(claudeScriptPath.path).inserted {
            paths.append(claudeScriptPath)
        }

        for path in codexDirectoryPaths.map(codexScriptPath(for:)) where fileManager.fileExists(atPath: path.path) {
            if seen.insert(path.path).inserted {
                paths.append(path)
            }
        }

        return paths
    }

    private func isBellScript(_ content: String) -> Bool {
        content.contains("afplay") && !content.contains("say \"$SUMMARY\"")
    }

    private func readClaudeSettingsJSONIfPresent() throws -> [String: Any]? {
        guard fileManager.fileExists(atPath: claudeSettingsPath.path) else {
            return nil
        }
        return try readClaudeSettingsJSON()
    }

    private func readClaudeSettingsJSON() throws -> [String: Any] {
        let data = try Data(contentsOf: claudeSettingsPath)
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        guard let settings = raw as? [String: Any] else {
            throw NotificationServiceError.invalidSettingsFormat
        }
        return settings
    }

    private func writeClaudeSettingsJSON(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: claudeSettingsPath, options: .atomic)
    }

    private func writeExecutableScript(_ content: String, to path: URL) throws {
        try content.write(to: path, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    }

    private func backupFileIfExists(at path: URL) throws {
        guard fileManager.fileExists(atPath: path.path) else {
            return
        }

        let backupPath = path.appendingPathExtension("amx-backup")
        if fileManager.fileExists(atPath: backupPath.path) {
            try fileManager.removeItem(at: backupPath)
        }

        try fileManager.copyItem(at: path, to: backupPath)
    }

    private func ensureDirectoryExists(at path: URL) throws {
        if fileManager.fileExists(atPath: path.path) {
            return
        }

        try fileManager.createDirectory(at: path, withIntermediateDirectories: true)
    }

    private func stopHooksContainsNotificationScript(_ settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any],
              let stopHooks = hooks["Stop"] as? [Any] else {
            return false
        }

        return stopHooks.contains(where: hookContainsNotificationScript)
    }

    private func ensureNotificationStopHook(in settings: inout [String: Any]) {
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var stopHooks = hooks["Stop"] as? [Any] ?? []

        if !stopHooks.contains(where: hookContainsNotificationScript) {
            let hookEntry: [String: Any] = [
                "matcher": "",
                "hooks": [
                    [
                        "type": "command",
                        "command": claudeScriptPath.path,
                        "async": true
                    ]
                ]
            ]
            stopHooks.append(hookEntry)
        }

        hooks["Stop"] = stopHooks
        settings["hooks"] = hooks
    }

    private func removeNotificationStopHooks(from settings: inout [String: Any]) {
        guard var hooks = settings["hooks"] as? [String: Any],
              var stopHooks = hooks["Stop"] as? [Any] else {
            return
        }

        stopHooks.removeAll(where: hookContainsNotificationScript)
        hooks["Stop"] = stopHooks
        settings["hooks"] = hooks
    }

    private func hookContainsNotificationScript(_ entry: Any) -> Bool {
        guard let dictionary = entry as? [String: Any],
              let hooks = dictionary["hooks"] as? [[String: Any]] else {
            return false
        }

        for hook in hooks {
            if let command = hook["command"] as? String,
               command.contains("notify-local-tts.sh") {
                return true
            }
        }

        return false
    }

    private func codexNotifyContainsNotificationScript(in content: String) -> Bool {
        guard let notifyBlock = codexNotifyBlock(in: content) else {
            return false
        }

        return notifyBlock.contains(notificationScriptFilename)
    }

    private func ensureCodexNotifyCommand(in content: String, scriptPath: URL) -> String {
        let notifyLine = "notify = [\"\(escapeTOMLString(scriptPath.path))\"]"

        if let range = codexNotifyBlockRange(in: content) {
            var updated = content
            updated.replaceSubrange(range, with: notifyLine + "\n")
            return normalizedTextFileContent(updated)
        }

        if content.isEmpty {
            return notifyLine + "\n"
        }

        return normalizedTextFileContent(notifyLine + "\n" + content)
    }

    private func removeCodexNotifyCommand(from content: String) -> String {
        guard let range = codexNotifyBlockRange(in: content) else {
            return content
        }

        let notifyBlock = String(content[range])
        guard notifyBlock.contains(notificationScriptFilename) else {
            return content
        }

        var updated = content
        updated.removeSubrange(range)

        while updated.hasPrefix("\n\n") {
            updated.removeFirst()
        }

        return updated
    }

    private func codexNotifyBlock(in content: String) -> String? {
        guard let range = codexNotifyBlockRange(in: content) else {
            return nil
        }
        return String(content[range])
    }

    private func codexNotifyBlockRange(in content: String) -> Range<String.Index>? {
        let pattern = #"(?ms)^notify\s*=\s*\[(.*?)\]\s*(?:\n|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: nsRange),
              let range = Range(match.range, in: content) else {
            return nil
        }

        return range
    }

    private func escapeTOMLString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func normalizedTextFileContent(_ content: String) -> String {
        guard !content.isEmpty else {
            return content
        }

        if content.hasSuffix("\n") {
            return content
        }

        return content + "\n"
    }

    private func upsertVoiceNotificationsSection(in content: String) -> String {
        let sectionHeader = "## Voice Notifications"
        let sectionContent = NotificationScripts.voiceInstructionsSection

        // Remove any standalone summary section first to avoid duplication,
        // since the voice notifications section includes the summary instruction.
        let cleaned = removeMarkdownSection(from: content, header: "## Add a brief summary to your final message")

        guard let sectionRange = cleaned.range(of: sectionHeader) else {
            guard !cleaned.isEmpty else {
                return sectionContent
            }

            if cleaned.hasSuffix("\n\n") {
                return cleaned + sectionContent
            }

            if cleaned.hasSuffix("\n") {
                return cleaned + "\n" + sectionContent
            }

            return cleaned + "\n\n" + sectionContent
        }

        let searchRange = sectionRange.upperBound..<cleaned.endIndex
        let sectionEnd = cleaned.range(of: "\n## ", range: searchRange)?.lowerBound ?? cleaned.endIndex

        var updated = cleaned
        updated.replaceSubrange(sectionRange.lowerBound..<sectionEnd, with: sectionContent)
        return updated
    }

    private func removeVoiceNotificationsSection(from content: String) -> String {
        let result = removeMarkdownSection(from: content, header: "## Voice Notifications")

        guard result != content else {
            return content
        }

        // Restore standalone summary section so the AI keeps adding Summary lines
        // even when voice notifications are uninstalled.
        return appendSectionIfMissing(
            in: result,
            header: "## Add a brief summary to your final message",
            section: NotificationScripts.standaloneSummarySection
        )
    }

    private func removeMarkdownSection(from content: String, header: String) -> String {
        guard let sectionRange = content.range(of: header) else {
            return content
        }

        let sectionStart = sectionRange.lowerBound
        let searchRange = sectionRange.upperBound..<content.endIndex
        let sectionEnd = content.range(of: "\n## ", range: searchRange)?.lowerBound ?? content.endIndex

        var actualStart = sectionStart
        while actualStart > content.startIndex {
            let previousIndex = content.index(before: actualStart)
            if content[previousIndex] == "\n" {
                actualStart = previousIndex
            } else {
                break
            }
        }

        return String(content[..<actualStart]) + String(content[sectionEnd...])
    }

    private func appendSectionIfMissing(in content: String, header: String, section: String) -> String {
        guard content.range(of: header) == nil else {
            return content
        }

        if content.isEmpty {
            return section
        }

        if content.hasSuffix("\n\n") {
            return content + section
        }

        if content.hasSuffix("\n") {
            return content + "\n" + section
        }

        return content + "\n\n" + section
    }
}

private enum NotificationScripts {
    static let claudeVoiceScript = #"""
#!/bin/bash
# Voice notification script for Claude Code
# Reads hook metadata from stdin, loads transcript, and speaks the "Summary:" line via TTS

# Read hook metadata from stdin
INPUT=$(cat)

# Extract transcript_path from the hook metadata
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# Read the last assistant message from the JSONL transcript
# The format uses "type": "assistant" and content is at .message.content
CONTENT=$(tac "$TRANSCRIPT_PATH" | while read -r line; do
    msg_type=$(echo "$line" | jq -r '.type // empty')
    if [ "$msg_type" = "assistant" ]; then
        # Extract content from .message.content array
        echo "$line" | jq -r '
            .message.content |
            if type == "array" then
                map(select(.type == "text") | .text) | join("\n")
            elif type == "string" then
                .
            else
                empty
            end
        '
        break
    fi
done)

# Look for last Summary: line (case insensitive)
SUMMARY=$(echo "$CONTENT" | grep -i "^Summary:" | tail -1 | sed 's/^[Ss]ummary:[[:space:]]*//')

if [ -n "$SUMMARY" ]; then
    say "$SUMMARY"
fi
"""#

    static let codexVoiceScript = #"""
#!/bin/bash
# Voice notification script for Codex CLI
# Reads JSON payload from argv/stdin and speaks the "Summary:" line via TTS

PAYLOAD="$1"

if [ -z "$PAYLOAD" ] && [ ! -t 0 ]; then
    PAYLOAD=$(cat)
fi

if [ -z "$PAYLOAD" ]; then
    exit 0
fi

EVENT_TYPE=$(echo "$PAYLOAD" | jq -r '.type // empty' 2>/dev/null)
if [ "$EVENT_TYPE" != "agent-turn-complete" ]; then
    exit 0
fi

CONTENT=$(echo "$PAYLOAD" | jq -r '."last-assistant-message" // empty' 2>/dev/null)
SUMMARY=$(echo "$CONTENT" | grep -i "^Summary:" | tail -1 | sed 's/^[Ss]ummary:[[:space:]]*//')

if [ -n "$SUMMARY" ]; then
    say "$SUMMARY"
fi
"""#

    static let voiceInstructionsSection = #"""
## Voice Notifications

When completing a task and handing control back to the user, the last line of the output must be:
`Summary: <brief summary>`.
"""#

    static let standaloneSummarySection = #"""
## Add a brief summary to your final message

When completing a task and handing control back to the user, the last line of the output must be:
`Summary: <brief summary>`.
"""#

    static let defaultBellSoundPath = "/System/Library/Sounds/Glass.aiff"

    static func claudeBellScript(soundPath: String) -> String {
        let escapedSoundPath = shellSingleQuoted(soundPath)
        return """
#!/bin/bash
# Voice notification script for Claude Code (Bell Mode)
# Reads hook metadata from stdin, loads transcript, and plays a bell if Summary found

SOUND_PATH='\(escapedSoundPath)'

# Read hook metadata from stdin
INPUT=$(cat)

# Extract transcript_path from the hook metadata
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# Read the last assistant message from the JSONL transcript
CONTENT=$(tac "$TRANSCRIPT_PATH" | while read -r line; do
    msg_type=$(echo "$line" | jq -r '.type // empty')
    if [ "$msg_type" = "assistant" ]; then
        echo "$line" | jq -r '
            .message.content |
            if type == "array" then
                map(select(.type == "text") | .text) | join("\n")
            elif type == "string" then
                .
            else
                empty
            end
        '
        break
    fi
done)

# Look for last Summary: line (case insensitive)
SUMMARY=$(echo "$CONTENT" | grep -i "^Summary:" | tail -1)

if [ -n "$SUMMARY" ]; then
    if [ -f "$SOUND_PATH" ]; then
        afplay "$SOUND_PATH"
    else
        afplay \(defaultBellSoundPath)
    fi
fi
"""
    }

    static func codexBellScript(soundPath: String) -> String {
        let escapedSoundPath = shellSingleQuoted(soundPath)
        return """
#!/bin/bash
# Voice notification script for Codex CLI (Bell Mode)
# Reads JSON payload from argv/stdin and plays a bell if Summary found

SOUND_PATH='\(escapedSoundPath)'

PAYLOAD="$1"

if [ -z "$PAYLOAD" ] && [ ! -t 0 ]; then
    PAYLOAD=$(cat)
fi

if [ -z "$PAYLOAD" ]; then
    exit 0
fi

EVENT_TYPE=$(echo "$PAYLOAD" | jq -r '.type // empty' 2>/dev/null)
if [ "$EVENT_TYPE" != "agent-turn-complete" ]; then
    exit 0
fi

CONTENT=$(echo "$PAYLOAD" | jq -r '."last-assistant-message" // empty' 2>/dev/null)
SUMMARY=$(echo "$CONTENT" | grep -i "^Summary:" | tail -1)

if [ -n "$SUMMARY" ]; then
    if [ -f "$SOUND_PATH" ]; then
        afplay "$SOUND_PATH"
    else
        afplay \(defaultBellSoundPath)
    fi
fi
"""
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\"'\"'")
    }
}
