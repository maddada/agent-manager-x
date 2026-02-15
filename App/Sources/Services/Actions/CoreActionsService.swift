import Foundation

enum CoreActionsError: Error, LocalizedError {
    case invalidConfiguration(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            return message
        case let .commandFailed(message):
            return message
        }
    }
}

final class CoreActionsService {
    private let settings: SettingsStore
    private let shell: ShellCommandRunning
    private let processService: ProcessIntrospectionService

    init(
        settings: SettingsStore = .shared,
        shell: ShellCommandRunning = ShellCommandRunner(),
        processService: ProcessIntrospectionService = ProcessIntrospectionService()
    ) {
        self.settings = settings
        self.shell = shell
        self.processService = processService
    }

    func killSession(pid: Int) throws {
        let descendants = processService.descendantPIDs(of: pid)
        for childPID in descendants {
            _ = processService.kill(pid: childPID, signal: 9)
        }

        _ = processService.kill(pid: pid, signal: 9)

        if let snapshot = processService.listProcesses().first(where: { $0.pid == pid }) {
            _ = processService.killProcessGroup(groupID: snapshot.processGroupID, signal: 9)
        }

        Thread.sleep(forTimeInterval: 0.05)

        if processService.processIsRunning(pid: pid) {
            let retryDescendants = processService.descendantPIDs(of: pid)
            for childPID in retryDescendants {
                _ = processService.kill(pid: childPID, signal: 9)
            }

            _ = processService.kill(pid: pid, signal: 9)
            Thread.sleep(forTimeInterval: 0.05)

            if processService.processIsRunning(pid: pid) {
                throw CoreActionsError.commandFailed("Process \(pid) is still running after kill attempts")
            }
        }
    }

    func openInEditor(
        path: String,
        editor overrideEditor: DefaultEditor? = nil,
        useSlowerCompatibleProjectSwitching: Bool = false,
        projectName: String? = nil
    ) throws {
        let selectedEditor = overrideEditor ?? settings.defaultEditor

        if !useSlowerCompatibleProjectSwitching,
           let openArguments = preferredAppOpenArguments(for: selectedEditor, path: path) {
            var environment: [String: String] = [:]
            let trimmedProjectName = projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedProjectName.isEmpty {
                environment["AMX_PROJECT_NAME"] = trimmedProjectName
            }

            if (try? spawn(
                executable: "/usr/bin/open",
                arguments: openArguments,
                enrichPath: false,
                additionalEnvironment: environment,
                lookupExecutableInPath: false
            )) != nil {
                return
            }
        }

        switch selectedEditor {
        case .zed:
            try spawn(executable: "zed", arguments: [path])
        case .code:
            try spawn(executable: "code", arguments: [path])
        case .cursor:
            try spawn(executable: "cursor", arguments: [path])
        case .sublime:
            try spawn(executable: "subl", arguments: [path])
        case .neovim:
            try spawn(executable: "nvim", arguments: [path])
        case .webstorm:
            try spawn(executable: "webstorm", arguments: [path])
        case .idea:
            try spawn(executable: "idea", arguments: [path])
        case .custom:
            let command = settings.customEditorCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else {
                throw CoreActionsError.invalidConfiguration("Custom editor command is empty")
            }
            try spawnCustomCommand(command, path: path)
        }
    }

    private func preferredAppOpenArguments(for editor: DefaultEditor, path: String) -> [String]? {
        switch editor {
        case .code:
            return ["-b", "com.microsoft.VSCode", path]
        case .cursor:
            return ["-a", "Cursor", path]
        default:
            return nil
        }
    }

    func openInTerminal(path: String, terminal overrideTerminal: DefaultTerminal? = nil) throws {
        let selectedTerminal = overrideTerminal ?? settings.defaultTerminal

        switch selectedTerminal {
        case .ghostty:
            try spawn(executable: "/usr/bin/open", arguments: ["-a", "Ghostty", path], enrichPath: false)
        case .iterm:
            let script = """
            tell application "iTerm"
                activate
                create window with default profile
                tell current session of current window
                    write text "cd '\(escapeShellSingleQuoted(path))'"
                end tell
            end tell
            """
            try runAppleScript(script)
        case .kitty:
            try spawn(executable: "kitty", arguments: ["--directory", path])
        case .terminal:
            let script = """
            tell application "Terminal"
                activate
                do script "cd '\(escapeShellSingleQuoted(path))'"
            end tell
            """
            try runAppleScript(script)
        case .warp:
            try spawn(executable: "/usr/bin/open", arguments: ["-a", "Warp", path], enrichPath: false)
        case .alacritty:
            try spawn(executable: "alacritty", arguments: ["--working-directory", path])
        case .hyper:
            try spawn(executable: "/usr/bin/open", arguments: ["-a", "Hyper", path], enrichPath: false)
        case .custom:
            let command = settings.customTerminalCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else {
                throw CoreActionsError.invalidConfiguration("Custom terminal command is empty")
            }

            if (try? spawn(executable: "/usr/bin/open", arguments: ["-a", command, path], enrichPath: false)) == nil {
                try spawnCustomCommand(command, path: path)
            }
        }
    }

    func runProjectCommand(path: String, command: String, terminal overrideTerminal: DefaultTerminal? = nil) throws {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            throw CoreActionsError.invalidConfiguration("Command cannot be empty")
        }

        let selectedTerminal = overrideTerminal ?? settings.defaultTerminal

        switch selectedTerminal {
        case .iterm:
            try runInITerm(path: path, command: trimmedCommand)
        case .terminal:
            try runInTerminalApp(path: path, command: trimmedCommand)
        case .kitty:
            try spawn(executable: "kitty", arguments: ["--directory", path, "/bin/zsh", "-lc", trimmedCommand])
        case .alacritty:
            try spawn(executable: "alacritty", arguments: ["--working-directory", path, "-e", "/bin/zsh", "-lc", trimmedCommand])
        case .ghostty:
            do {
                try spawn(executable: "ghostty", arguments: ["--working-directory", path, "-e", "/bin/zsh", "-lc", trimmedCommand])
            } catch {
                try runByOpeningTerminalAndTyping(path: path, command: trimmedCommand, terminal: .ghostty)
            }
        case .warp:
            try runByOpeningTerminalAndTyping(path: path, command: trimmedCommand, terminal: .warp)
        case .hyper:
            try runByOpeningTerminalAndTyping(path: path, command: trimmedCommand, terminal: .hyper)
        case .custom:
            try runInCustomTerminal(path: path, command: trimmedCommand)
        }
    }

    @discardableResult
    func focusSession(pid: Int, projectPath: String) -> Bool {
        if let tty = ttyForPID(pid),
           tty != "??",
           !tty.isEmpty {
            if focusITerm(tty: tty) {
                return true
            }

            if focusTerminal(tty: tty) {
                return true
            }
        }

        return focusByPath(projectPath)
    }

    private func spawn(
        executable: String,
        arguments: [String],
        enrichPath: Bool = true,
        additionalEnvironment: [String: String] = [:],
        lookupExecutableInPath: Bool = true
    ) throws {
        let process = Process()
        let pathForExecution = enrichPath ? enrichedPath() : (ProcessInfo.processInfo.environment["PATH"] ?? "")
        let shouldResolveInPath = lookupExecutableInPath && !executable.contains("/")

        if shouldResolveInPath {
            guard let resolvedExecutable = resolveExecutableInPath(executable, path: pathForExecution) else {
                throw CoreActionsError.commandFailed("Failed to run \(executable): command not found in PATH")
            }
            process.executableURL = URL(fileURLWithPath: resolvedExecutable)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        }

        if enrichPath || !additionalEnvironment.isEmpty {
            var environment = ProcessInfo.processInfo.environment
            if enrichPath {
                environment["PATH"] = pathForExecution
            }
            for (key, value) in additionalEnvironment {
                environment[key] = value
            }
            process.environment = environment
        }

        do {
            try process.run()
        } catch {
            throw CoreActionsError.commandFailed("Failed to run \(executable): \(error)")
        }
    }

    private func spawnCustomCommand(_ command: String, path: String) throws {
        let escapedPath = "'\(escapeShellSingleQuoted(path))'"
        let shellCommand: String

        if command.contains("{path}") {
            shellCommand = command.replacingOccurrences(of: "{path}", with: escapedPath)
        } else {
            shellCommand = "\(command) \(escapedPath)"
        }

        try spawn(executable: "/bin/zsh", arguments: ["-lc", shellCommand])
    }

    private func runAppleScript(_ script: String) throws {
        let result = shell.run(
            executable: "/usr/bin/osascript",
            arguments: ["-e", script],
            currentDirectory: nil,
            environment: [:],
            timeout: 3.0
        )

        if !result.isSuccess {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CoreActionsError.commandFailed("AppleScript failed: \(message)")
        }
    }

    private func runInTerminalApp(path: String, command: String) throws {
        let shellLine = "cd '\(escapeShellSingleQuoted(path))' && \(command)"
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapeAppleScriptString(shellLine))"
        end tell
        """
        try runAppleScript(script)
    }

    private func runInITerm(path: String, command: String) throws {
        let shellLine = "cd '\(escapeShellSingleQuoted(path))' && \(command)"
        let script = """
        tell application "iTerm"
            activate
            create window with default profile
            tell current session of current window
                write text "\(escapeAppleScriptString(shellLine))"
            end tell
        end tell
        """
        try runAppleScript(script)
    }

    private func runByOpeningTerminalAndTyping(path: String, command: String, terminal: DefaultTerminal) throws {
        try openInTerminal(path: path, terminal: terminal)
        let shellLine = "cd '\(escapeShellSingleQuoted(path))' && \(command)"
        let script = """
        delay 0.35
        tell application "System Events"
            keystroke "\(escapeAppleScriptString(shellLine))"
            key code 36
        end tell
        """
        try runAppleScript(script)
    }

    private func runInCustomTerminal(path: String, command: String) throws {
        let template = settings.customTerminalCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else {
            throw CoreActionsError.invalidConfiguration("Custom terminal command is empty")
        }

        if template.contains("{command}") {
            let escapedPath = "'\(escapeShellSingleQuoted(path))'"
            let escapedCommand = "'\(escapeShellSingleQuoted(command))'"
            let shellCommand = template
                .replacingOccurrences(of: "{path}", with: escapedPath)
                .replacingOccurrences(of: "{command}", with: escapedCommand)
            try spawn(executable: "/bin/zsh", arguments: ["-lc", shellCommand])
            return
        }

        try runByOpeningTerminalAndTyping(path: path, command: command, terminal: .custom)
    }

    private func ttyForPID(_ pid: Int) -> String? {
        let result = shell.run(
            executable: "/bin/ps",
            arguments: ["-p", String(pid), "-o", "tty="],
            currentDirectory: nil,
            environment: [:],
            timeout: 1.0
        )

        guard result.isSuccess else {
            return nil
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func focusITerm(tty: String) -> Bool {
        let script = """
        tell application "System Events"
            if not (exists process "iTerm2") then
                return "not found"
            end if
        end tell

        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s contains "\(escapeAppleScriptString(tty))" then
                            select s
                            select t
                            set index of w to 1
                            return "found"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "not found"
        """

        return runFocusScript(script)
    }

    private func focusTerminal(tty: String) -> Bool {
        let script = """
        tell application "System Events"
            if not (exists process "Terminal") then
                return "not found"
            end if
        end tell

        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if tty of t contains "\(escapeAppleScriptString(tty))" then
                            set selected of t to true
                            set index of w to 1
                            return "found"
                        end if
                    end try
                end repeat
            end repeat
        end tell
        return "not found"
        """

        return runFocusScript(script)
    }

    private func focusByPath(_ path: String) -> Bool {
        let searchTerm = URL(fileURLWithPath: path).lastPathComponent
        let escapedSearch = escapeAppleScriptString(searchTerm.isEmpty ? path : searchTerm)

        let iTermScript = """
        tell application "System Events"
            if exists process "iTerm2" then
                tell application "iTerm2"
                    activate
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                if name of s contains "\(escapedSearch)" then
                                    select s
                                    select t
                                    set index of w to 1
                                    return "found"
                                end if
                            end repeat
                        end repeat
                    end repeat
                end tell
            end if
        end tell
        return "not found"
        """

        if runFocusScript(iTermScript) {
            return true
        }

        let terminalScript = """
        tell application "System Events"
            if not (exists process "Terminal") then
                return "not found"
            end if
        end tell

        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if custom title of t contains "\(escapedSearch)" then
                            set selected of t to true
                            set index of w to 1
                            return "found"
                        end if
                    end try
                end repeat
            end repeat
        end tell
        return "not found"
        """

        return runFocusScript(terminalScript)
    }

    private func runFocusScript(_ script: String) -> Bool {
        let result = shell.run(
            executable: "/usr/bin/osascript",
            arguments: ["-e", script],
            currentDirectory: nil,
            environment: [:],
            timeout: 3.0
        )

        guard result.isSuccess else {
            return false
        }

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return output != "not found"
    }

    private func enrichedPath() -> String {
        let shellPathResult = shell.run(
            executable: "/bin/zsh",
            arguments: ["-l", "-c", "echo $PATH"],
            currentDirectory: nil,
            environment: [:],
            timeout: 1.5
        )

        let shellPath = shellPathResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !shellPath.isEmpty {
            return shellPath
        }

        let current = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let parts = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "\(home)/.local/bin",
            current
        ].filter { !$0.isEmpty }

        return parts.joined(separator: ":")
    }

    private func resolveExecutableInPath(_ executable: String, path: String) -> String? {
        guard !executable.isEmpty else {
            return nil
        }

        let fileManager = FileManager.default
        for entry in path.split(separator: ":", omittingEmptySubsequences: false) {
            let directory = entry.isEmpty ? fileManager.currentDirectoryPath : String(entry)
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(executable).path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private func escapeShellSingleQuoted(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }

    private func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
