import Foundation
import Darwin

enum MiniViewerControllerError: Error, LocalizedError {
    case sourceNotFound
    case iconDirectoryNotFound
    case appSupportDirectoryUnavailable
    case failedToCompileHelper(String)
    case failedToLaunchHelper(String)

    var errorDescription: String? {
        switch self {
        case .sourceNotFound:
            return "Mini viewer Swift source not found"
        case .iconDirectoryNotFound:
            return "Mini viewer icon directory not found"
        case .appSupportDirectoryUnavailable:
            return "Failed to resolve application support directory"
        case let .failedToCompileHelper(message):
            return message
        case let .failedToLaunchHelper(message):
            return message
        }
    }
}

final class MiniViewerController {
    private let sessionDetectionService: SessionDetectionService
    private let gitDiffStatsService: GitDiffStatsService
    private let coreActionsService: CoreActionsService
    private let settings: SettingsStore
    private let fileManager: FileManager

    private let queue = DispatchQueue(label: "MiniViewerController.queue", qos: .userInteractive)
    private let payloadQueue = DispatchQueue(label: "MiniViewerController.payloadQueue", qos: .utility)

    private var side: MiniViewerSide
    private var uiElementSize: UIElementSize
    private var useSlowerCompatibleProjectSwitching: Bool
    private var isVisible = true

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var updaterTimer: DispatchSourceTimer?
    private var payloadRefreshInFlight = false
    private var payloadRefreshPending = false
    private var payloadRefreshGeneration: UInt64 = 0

    private var diffCache: [String: CachedGitDiffStats] = [:]

    init(
        sessionDetectionService: SessionDetectionService = SessionDetectionService(),
        gitDiffStatsService: GitDiffStatsService = GitDiffStatsService(),
        coreActionsService: CoreActionsService = CoreActionsService(),
        settings: SettingsStore = .shared,
        fileManager: FileManager = .default
    ) {
        self.sessionDetectionService = sessionDetectionService
        self.gitDiffStatsService = gitDiffStatsService
        self.coreActionsService = coreActionsService
        self.settings = settings
        self.fileManager = fileManager

        side = settings.miniViewerSide
        uiElementSize = settings.miniViewerUIElementSize
        useSlowerCompatibleProjectSwitching = settings.useSlowerCompatibleProjectSwitching
    }

    func setSide(_ side: MiniViewerSide) {
        queue.async {
            self.side = side
            self.settings.miniViewerSide = side
            self.requestPayloadRefreshLocked()
        }
    }

    func setUIElementSize(_ value: UIElementSize) {
        queue.async {
            self.uiElementSize = value
            self.settings.miniViewerUIElementSize = value
            self.requestPayloadRefreshLocked()
        }
    }

    func setUseSlowerCompatibleProjectSwitching(_ enabled: Bool) {
        queue.async {
            self.useSlowerCompatibleProjectSwitching = enabled
            self.settings.useSlowerCompatibleProjectSwitching = enabled
        }
    }

    var isRunning: Bool {
        queue.sync {
            isProcessRunningLocked()
        }
    }

    func show() throws {
        try queue.sync {
            if isProcessRunningLocked() {
                isVisible = true
                sendVisibilityUpdateLocked()
            } else {
                isVisible = true
                try startMiniViewerLocked()
            }
        }
    }

    func prepareForFastToggle() throws {
        try queue.sync {
            if isProcessRunningLocked() {
                isVisible = false
                sendVisibilityUpdateLocked()
            } else {
                isVisible = false
                try startMiniViewerLocked()
            }
        }
    }

    func toggle() throws {
        try queue.sync {
            if isProcessRunningLocked() {
                isVisible.toggle()
                sendVisibilityUpdateLocked()
            } else {
                isVisible = true
                try startMiniViewerLocked()
            }
        }
    }

    func shutdown() {
        queue.sync {
            stopMiniViewerLocked()
        }
    }

    private func startMiniViewerLocked() throws {
        if isProcessRunningLocked() {
            return
        }

        stopMiniViewerLocked()

        let binaryPath = try miniViewerBinaryPathLocked()
        let iconDirectoryPath = try miniViewerIconDirectoryPathLocked()

        let child = Process()
        child.executableURL = binaryPath
        child.arguments = []

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()

        child.standardInput = stdinPipe
        child.standardOutput = stdoutPipe
        child.standardError = FileHandle.nullDevice

        var environment = ProcessInfo.processInfo.environment
        environment["MINI_VIEWER_ICON_DIR"] = iconDirectoryPath.path
        environment["MINI_VIEWER_SIDE"] = side.rawValue
        environment["MINI_VIEWER_UI_ELEMENT_SIZE"] = uiElementSize.rawValue
        child.environment = environment

        do {
            try child.run()
        } catch {
            throw MiniViewerControllerError.failedToLaunchHelper("Failed to spawn native mini viewer: \(error)")
        }

        process = child
        stdinHandle = stdinPipe.fileHandleForWriting
        stdoutHandle = stdoutPipe.fileHandleForReading
        stdoutBuffer.removeAll(keepingCapacity: true)

        stdoutHandle?.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }

            if chunk.isEmpty {
                self.queue.async {
                    self.handleStdoutEOFLocked()
                }
                return
            }

            self.queue.async {
                self.consumeStdoutDataLocked(chunk)
            }
        }

        // Push the first snapshot immediately so the helper does not wait for the periodic ticker.
        requestPayloadRefreshLocked()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(3))
        timer.setEventHandler { [weak self] in
            self?.requestPayloadRefreshLocked()
        }
        timer.resume()
        updaterTimer = timer
    }

    private func stopMiniViewerLocked() {
        updaterTimer?.cancel()
        updaterTimer = nil

        stdoutHandle?.readabilityHandler = nil

        try? stdinHandle?.close()
        try? stdoutHandle?.close()
        stdinHandle = nil
        stdoutHandle = nil
        stdoutBuffer.removeAll(keepingCapacity: false)
        payloadRefreshPending = false
        payloadRefreshInFlight = false
        payloadRefreshGeneration &+= 1

        if let process {
            if process.isRunning {
                process.terminate()
                _ = waitForProcessToExit(process, timeout: 1.0)

                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                }
            }

            self.process = nil
        }
    }

    private func handleStdoutEOFLocked() {
        stopMiniViewerLocked()
    }

    private func isProcessRunningLocked() -> Bool {
        guard let process else {
            return false
        }

        if process.isRunning {
            return true
        }

        stopMiniViewerLocked()
        return false
    }

    private func waitForProcessToExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(max(0.05, timeout))
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }

        return !process.isRunning
    }

    private func requestPayloadRefreshLocked() {
        guard isProcessRunningLocked() else {
            return
        }

        payloadRefreshPending = true
        runPayloadRefreshIfNeededLocked()
    }

    private func runPayloadRefreshIfNeededLocked() {
        guard payloadRefreshPending,
              !payloadRefreshInFlight else {
            return
        }

        guard isProcessRunningLocked() else {
            payloadRefreshPending = false
            return
        }

        payloadRefreshPending = false
        payloadRefreshInFlight = true
        let generation = payloadRefreshGeneration

        payloadQueue.async { [weak self] in
            guard let self else { return }

            let projects = self.collectProjectPayload()

            self.queue.async {
                self.payloadRefreshInFlight = false

                guard generation == self.payloadRefreshGeneration else {
                    self.runPayloadRefreshIfNeededLocked()
                    return
                }

                self.writePayloadLocked(projects: projects)
                self.runPayloadRefreshIfNeededLocked()
            }
        }
    }

    private func sendVisibilityUpdateLocked() {
        let command = MiniViewerVisibilityCommand(command: "setVisibility", isVisible: isVisible)
        writeJSONToHelperLocked(command)
    }

    private func writePayloadLocked(projects: [MiniViewerProjectPayload]) {
        let payload = MiniViewerPayload(
            side: side,
            uiElementSize: uiElementSize,
            isVisible: isVisible,
            projects: projects
        )
        writeJSONToHelperLocked(payload)
    }

    private func writeJSONToHelperLocked<T: Encodable>(_ value: T) {
        guard isProcessRunningLocked(),
              let stdinHandle else {
            return
        }

        do {
            var data = try JSONEncoder().encode(value)
            data.append(0x0A)
            try stdinHandle.write(contentsOf: data)
        } catch {
            stopMiniViewerLocked()
        }
    }

    private func collectProjectPayload() -> [MiniViewerProjectPayload] {
        let response = sessionDetectionService.getAllSessions()

        let visibleSessions: [Session]
        if response.backgroundSessions.isEmpty {
            visibleSessions = response.sessions.filter { !$0.isBackground }
        } else {
            visibleSessions = response.sessions
        }

        var projects: [MiniViewerProjectPayload] = []
        var indexByPath: [String: Int] = [:]

        for session in visibleSessions {
            let projectPath = session.projectPath
            let branch = normalizedBranch(session.gitBranch)
            let miniSession = MiniViewerSessionPayload(from: session)

            let projectIndex: Int
            if let existingIndex = indexByPath[projectPath] {
                projectIndex = existingIndex
            } else {
                projectIndex = projects.count
                projects.append(
                    MiniViewerProjectPayload(
                        projectName: miniSession.projectName,
                        projectPath: projectPath,
                        gitBranch: branch,
                        diffAdditions: 0,
                        diffDeletions: 0,
                        sessions: []
                    )
                )
                indexByPath[projectPath] = projectIndex
            }

            if projects[projectIndex].gitBranch == nil {
                projects[projectIndex].gitBranch = branch
            }

            projects[projectIndex].sessions.append(miniSession)
        }

        for index in projects.indices {
            let stats = gitDiffStats(for: projects[index].projectPath)
            projects[index].diffAdditions = stats.additions
            projects[index].diffDeletions = stats.deletions
        }

        return projects
    }

    private func normalizedBranch(_ branch: String?) -> String? {
        guard let branch else {
            return nil
        }

        let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func gitDiffStats(for projectPath: String) -> (additions: Int, deletions: Int) {
        let now = Date()

        if let cached = diffCache[projectPath],
           now.timeIntervalSince(cached.fetchedAt) < CachedGitDiffStats.ttl {
            return (cached.additions, cached.deletions)
        }

        let stats = gitDiffStatsService.diffStats(for: projectPath)
        diffCache[projectPath] = CachedGitDiffStats(
            additions: stats.additions,
            deletions: stats.deletions,
            fetchedAt: now
        )

        return (stats.additions, stats.deletions)
    }

    private func consumeStdoutDataLocked(_ data: Data) {
        stdoutBuffer.append(data)

        while let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer.subdata(in: 0..<newlineIndex)
            stdoutBuffer.removeSubrange(0...newlineIndex)

            guard !lineData.isEmpty else {
                continue
            }

            guard let action = try? JSONDecoder().decode(MiniViewerAction.self, from: lineData) else {
                continue
            }

            handleMiniViewerActionLocked(action)
        }
    }

    private func handleMiniViewerActionLocked(_ action: MiniViewerAction) {
        switch action.action {
        case "focusSession":
            if openInPreferredEditor(projectPath: action.projectPath, projectName: action.projectName) {
                return
            }

            if coreActionsService.focusSession(pid: Int(action.pid), projectPath: action.projectPath) {
                return
            }

            try? coreActionsService.openInTerminal(path: action.projectPath, terminal: .terminal)
        case "endSession":
            try? coreActionsService.killSession(pid: Int(action.pid))
        default:
            break
        }
    }

    private func openInPreferredEditor(projectPath: String, projectName: String) -> Bool {
        do {
            try coreActionsService.openInEditor(
                path: projectPath,
                useSlowerCompatibleProjectSwitching: useSlowerCompatibleProjectSwitching,
                projectName: projectName
            )
            return true
        } catch {
            return false
        }
    }

    private func miniViewerSourcePathLocked() throws -> URL {
        if let bundled = Bundle.main.url(forResource: "MiniViewer", withExtension: "swift", subdirectory: "native-mini-viewer"),
           fileManager.fileExists(atPath: bundled.path) {
            return bundled
        }

        let sourceURL = URL(fileURLWithPath: #filePath)
        let repoRoot = sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let devPath = repoRoot
            .appendingPathComponent("App", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("native-mini-viewer", isDirectory: true)
            .appendingPathComponent("MiniViewer.swift")

        if fileManager.fileExists(atPath: devPath.path) {
            return devPath
        }

        throw MiniViewerControllerError.sourceNotFound
    }

    private func miniViewerIconDirectoryPathLocked() throws -> URL {
        let sourcePath = try miniViewerSourcePathLocked()
        let iconDirectory = sourcePath
            .deletingLastPathComponent()
            .appendingPathComponent("icons", isDirectory: true)

        if fileManager.fileExists(atPath: iconDirectory.path) {
            return iconDirectory
        }

        throw MiniViewerControllerError.iconDirectoryNotFound
    }

    private func miniViewerBinaryPathLocked() throws -> URL {
        let sourcePath = try miniViewerSourcePathLocked()
        let appSupport = try appSupportDirectoryLocked()

        let outputDirectory = appSupport.appendingPathComponent("native-mini-viewer", isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let binaryPath = outputDirectory.appendingPathComponent("mini-viewer-helper")

        let sourceModified = (try? sourcePath.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let binaryModified = (try? binaryPath.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let shouldCompile = !fileManager.fileExists(atPath: binaryPath.path) || sourceModified > binaryModified

        if shouldCompile {
            let compiler = Process()
            compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            compiler.arguments = ["swiftc", "-O", sourcePath.path, "-o", binaryPath.path]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            compiler.standardOutput = stdoutPipe
            compiler.standardError = stderrPipe

            do {
                try compiler.run()
            } catch {
                throw MiniViewerControllerError.failedToCompileHelper(
                    "Failed to launch Swift compiler for mini viewer: \(error)"
                )
            }

            compiler.waitUntilExit()
            guard compiler.terminationStatus == 0 else {
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrText = String(decoding: stderrData, as: UTF8.self)
                let detail = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
                if detail.isEmpty {
                    throw MiniViewerControllerError.failedToCompileHelper(
                        "Failed to compile native mini viewer (swiftc exited with an error)"
                    )
                }
                throw MiniViewerControllerError.failedToCompileHelper(
                    "Failed to compile native mini viewer: \(detail)"
                )
            }
        }

        return binaryPath
    }

    private func appSupportDirectoryLocked() throws -> URL {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw MiniViewerControllerError.appSupportDirectoryUnavailable
        }

        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.madda.agentmanagerx"
        let directory = base.appendingPathComponent(bundleIdentifier, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct CachedGitDiffStats {
    static let ttl: TimeInterval = 12

    let additions: Int
    let deletions: Int
    let fetchedAt: Date
}

private struct MiniViewerSessionPayload: Codable {
    let id: String
    let agentType: AgentType
    let projectName: String
    let projectPath: String
    let status: SessionStatus
    let lastMessage: String?
    let lastActivityAt: String
    let pid: UInt32
    let cpuUsage: Float
    let memoryBytes: UInt64
    let activeSubagentCount: Int

    init(from session: Session) {
        id = session.id
        agentType = session.agentType
        projectName = session.projectName
        projectPath = session.projectPath
        status = session.status
        lastMessage = session.lastMessage
        lastActivityAt = session.lastActivityAt
        pid = UInt32(max(0, session.pid))
        cpuUsage = Float(session.cpuUsage)
        memoryBytes = UInt64(max(0, session.memoryBytes))
        activeSubagentCount = session.activeSubagentCount
    }
}

private struct MiniViewerProjectPayload: Codable {
    let projectName: String
    let projectPath: String
    var gitBranch: String?
    var diffAdditions: Int
    var diffDeletions: Int
    var sessions: [MiniViewerSessionPayload]
}

private struct MiniViewerPayload: Codable {
    let side: MiniViewerSide
    let uiElementSize: UIElementSize
    let isVisible: Bool
    let projects: [MiniViewerProjectPayload]
}

private struct MiniViewerAction: Codable {
    let action: String
    let pid: UInt32
    let projectPath: String
    let projectName: String
}

private struct MiniViewerVisibilityCommand: Codable {
    let command: String
    let isVisible: Bool
}
