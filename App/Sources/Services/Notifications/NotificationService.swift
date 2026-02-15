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
    private let notificationConfigFilename = "notification.conf"
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
        guard fileManager.fileExists(atPath: claudeNotificationConfigPath.path) else {
            return false
        }

        let content = try String(contentsOf: claudeNotificationConfigPath, encoding: .utf8)
        return content.contains("mode=bell")
    }

    func setBellMode(enabled: Bool, bellSoundPath: String? = nil) throws {
        guard try checkNotificationSystemInstalled() else {
            throw NotificationServiceError.notificationSystemNotInstalled
        }

        let soundPath = bellSoundPath ?? NotificationScripts.defaultBellSoundPath
        let configContent = notificationConfigContent(
            mode: enabled ? "bell" : "voice",
            soundPath: soundPath
        )

        try configContent.write(to: claudeNotificationConfigPath, atomically: true, encoding: .utf8)

        for root in codexDirectoryPaths {
            try configContent.write(
                to: codexNotificationConfigPath(for: root),
                atomically: true,
                encoding: .utf8
            )
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
        try writeExecutableScript(NotificationScripts.claudeUnifiedScript, to: claudeScriptPath)

        let configContent = notificationConfigContent(
            mode: "voice",
            soundPath: NotificationScripts.defaultBellSoundPath
        )
        try configContent.write(to: claudeNotificationConfigPath, atomically: true, encoding: .utf8)

        try backupFileIfExists(at: claudeSettingsPath)
        var settings = try readClaudeSettingsJSONIfPresent() ?? [:]
        ensureNotificationStopHook(in: &settings)
        try writeClaudeSettingsJSON(settings)

        for profileSettingsPath in claudeProfileSettingsPaths {
            try backupFileIfExists(at: profileSettingsPath)
            var profileSettings = try readSettingsJSON(at: profileSettingsPath)
            ensureNotificationStopHook(in: &profileSettings)
            try writeSettingsJSON(profileSettings, to: profileSettingsPath)
        }

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
            try writeExecutableScript(NotificationScripts.codexUnifiedScript, to: scriptPath)

            let notifConfigPath = codexNotificationConfigPath(for: root)
            let notifConfigContent = notificationConfigContent(
                mode: "voice",
                soundPath: NotificationScripts.defaultBellSoundPath
            )
            try notifConfigContent.write(to: notifConfigPath, atomically: true, encoding: .utf8)

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

        for profileSettingsPath in claudeProfileSettingsPaths {
            try backupFileIfExists(at: profileSettingsPath)
            var profileSettings = try readSettingsJSON(at: profileSettingsPath)
            removeNotificationStopHooks(from: &profileSettings)
            try writeSettingsJSON(profileSettings, to: profileSettingsPath)
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

        if fileManager.fileExists(atPath: claudeNotificationConfigPath.path) {
            try fileManager.removeItem(at: claudeNotificationConfigPath)
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

            let notifConfigPath = codexNotificationConfigPath(for: root)
            if fileManager.fileExists(atPath: notifConfigPath.path) {
                try fileManager.removeItem(at: notifConfigPath)
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

    private var claudeNotificationConfigPath: URL {
        claudeHooksDirectoryPath.appendingPathComponent(notificationConfigFilename)
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

    private var claudeProfileSettingsPaths: [URL] {
        claudeProfileDirectoryPaths.compactMap { dir in
            let path = dir.appendingPathComponent("settings.json")
            return fileManager.fileExists(atPath: path.path) ? path : nil
        }
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

    private func codexNotificationConfigPath(for root: URL) -> URL {
        codexHooksDirectoryPath(for: root).appendingPathComponent(notificationConfigFilename)
    }

    private func notificationConfigContent(mode: String, soundPath: String) -> String {
        "mode=\(mode)\nsound_path=\(soundPath)\n"
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
        try writeSettingsJSON(settings, to: claudeSettingsPath)
    }

    private func readSettingsJSON(at path: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: path)
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        guard let settings = raw as? [String: Any] else {
            throw NotificationServiceError.invalidSettingsFormat
        }
        return settings
    }

    private func writeSettingsJSON(_ settings: [String: Any], to path: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: path, options: .atomic)
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
    static let claudeUnifiedScript = #"""
#!/bin/bash
# Notification script for Claude Code
# Reads mode from notification.conf, extracts Summary from transcript,
# and either speaks it (voice) or plays a bell sound (bell).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/notification.conf"

MODE="voice"
SOUND_PATH="/System/Library/Sounds/Glass.aiff"

if [ -f "$CONFIG_FILE" ]; then
    while IFS='=' read -r key value; do
        case "$key" in
            mode) MODE="$value" ;;
            sound_path) SOUND_PATH="$value" ;;
        esac
    done < "$CONFIG_FILE"
fi

# Read hook metadata from stdin
INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# Extract the last assistant message text from the JSONL transcript
CONTENT=$(jq -s -r '
    [.[] | select(.type == "assistant")] | last |
    .message.content |
    if type == "array" then
        map(select(.type == "text") | .text) | join("\n")
    elif type == "string" then
        .
    else
        empty
    end
' "$TRANSCRIPT_PATH")

# Look for last Summary: line (case insensitive)
SUMMARY=$(echo "$CONTENT" | grep -i "^Summary:" | tail -1 | sed 's/^[Ss]ummary:[[:space:]]*//')

if [ -n "$SUMMARY" ]; then
    if [ "$MODE" = "bell" ]; then
        if [ -f "$SOUND_PATH" ]; then
            afplay "$SOUND_PATH"
        else
            afplay /System/Library/Sounds/Glass.aiff
        fi
    else
        say "$SUMMARY"
    fi
fi
"""#

    static let codexUnifiedScript = #"""
#!/bin/bash
# Notification script for Codex CLI
# Reads mode from notification.conf, extracts Summary from payload,
# and either speaks it (voice) or plays a bell sound (bell).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/notification.conf"

MODE="voice"
SOUND_PATH="/System/Library/Sounds/Glass.aiff"

if [ -f "$CONFIG_FILE" ]; then
    while IFS='=' read -r key value; do
        case "$key" in
            mode) MODE="$value" ;;
            sound_path) SOUND_PATH="$value" ;;
        esac
    done < "$CONFIG_FILE"
fi

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
    if [ "$MODE" = "bell" ]; then
        if [ -f "$SOUND_PATH" ]; then
            afplay "$SOUND_PATH"
        else
            afplay /System/Library/Sounds/Glass.aiff
        fi
    else
        say "$SUMMARY"
    fi
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
}
