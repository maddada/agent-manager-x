import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var backgroundSessions: [Session] = []
    @Published private(set) var totalCount = 0
    @Published private(set) var waitingCount = 0
    @Published private(set) var agentCounts: [AgentType: Int] = [
        .claude: 0,
        .codex: 0,
        .opencode: 0
    ]
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?

    @Published var settingsPresented = false
    @Published var settingsError: String?
    @Published var settingsConfirmation: String?

    @Published var displayMode: DisplayMode
    @Published var theme: ThemePreference
    @Published var backgroundImage: String
    @Published var overlayOpacity: Int
    @Published var overlayColor: String
    @Published var cardClickAction: CardClickAction
    @Published var defaultEditor: DefaultEditor
    @Published var customEditorCommand: String
    @Published var useSlowerCompatibleProjectSwitching: Bool
    @Published var defaultTerminal: DefaultTerminal
    @Published var customTerminalCommand: String
    @Published var globalHotkey: String
    @Published var miniViewerHotkey: String
    @Published var miniViewerSide: MiniViewerSide
    @Published var miniViewerShowOnStart: Bool
    @Published var mainAppUIElementSize: UIElementSize
    @Published var miniViewerUIElementSize: UIElementSize

    @Published private(set) var notificationState = NotificationState()
    @Published private(set) var gitDiffStatsByProjectPath: [String: GitDiffStats] = [:]

    private let settings: SettingsStore
    private let sessionDetectionService: SessionDetectionService
    private let coreActionsService: CoreActionsService
    private let gitDiffStatsService: GitDiffStatsService
    private let menuBarService: MenuBarService
    private let hotkeyManager: GlobalHotkeyManager
    private let miniViewerController: MiniViewerController
    private let notificationService: NotificationService

    private var pollTimer: Timer?
    private var started = false
    private var lastOrderedForegroundSessions: [Session] = []
    private var gitDiffCache: [String: CachedDiffStats] = [:]
    private weak var mainWindow: NSWindow?
    private var confirmationResetTask: DispatchWorkItem?
    private let refreshQueue = DispatchQueue(label: "AppStore.refresh", qos: .userInitiated)
    private let gitDiffStatsQueue = DispatchQueue(label: "AppStore.gitDiffStats", qos: .utility)
    private var isRefreshInFlight = false
    private var hasPendingRefresh = false
    private var gitDiffStatsGeneration = 0

    init(
        settings: SettingsStore = .shared,
        sessionDetectionService: SessionDetectionService = SessionDetectionService(),
        coreActionsService: CoreActionsService? = nil,
        gitDiffStatsService: GitDiffStatsService = GitDiffStatsService(),
        menuBarService: MenuBarService? = nil,
        hotkeyManager: GlobalHotkeyManager = GlobalHotkeyManager(),
        miniViewerController: MiniViewerController? = nil,
        notificationService: NotificationService = NotificationService()
    ) {
        self.settings = settings
        self.sessionDetectionService = sessionDetectionService

        let actions = coreActionsService ?? CoreActionsService(settings: settings)
        self.coreActionsService = actions
        self.gitDiffStatsService = gitDiffStatsService
        self.menuBarService = menuBarService ?? MenuBarService()
        self.hotkeyManager = hotkeyManager

        self.miniViewerController = miniViewerController ?? MiniViewerController(
            sessionDetectionService: sessionDetectionService,
            gitDiffStatsService: gitDiffStatsService,
            coreActionsService: actions,
            settings: settings
        )

        self.notificationService = notificationService

        displayMode = settings.displayMode
        theme = settings.theme
        backgroundImage = settings.backgroundImage
        overlayOpacity = settings.overlayOpacity
        overlayColor = settings.overlayColor
        cardClickAction = settings.cardClickAction
        defaultEditor = settings.defaultEditor
        customEditorCommand = settings.customEditorCommand
        useSlowerCompatibleProjectSwitching = settings.useSlowerCompatibleProjectSwitching
        defaultTerminal = settings.defaultTerminal
        customTerminalCommand = settings.customTerminalCommand
        globalHotkey = settings.globalHotkey
        miniViewerHotkey = settings.miniViewerHotkey
        miniViewerSide = settings.miniViewerSide
        miniViewerShowOnStart = settings.miniViewerShowOnStart
        mainAppUIElementSize = settings.mainAppUIElementSize
        miniViewerUIElementSize = settings.miniViewerUIElementSize
    }

    func start() {
        guard !started else {
            return
        }

        started = true
        configureMenuBarCallbacks()
        configureHotkeys()
        applyMiniViewerSettings()
        refreshNotificationState()
        refresh(showInitialLoading: true)
        startPolling()

        if miniViewerShowOnStart {
            showMiniViewer()
        } else {
            prewarmMiniViewerForFastToggle()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        hotkeyManager.unregisterAppToggleHotkey()
        hotkeyManager.unregisterMiniViewerHotkey()
        hotkeyManager.setCallbacks(onAppToggle: nil, onMiniViewerToggle: nil)
        menuBarService.teardown()
        miniViewerController.shutdown()
        started = false
    }

    func attachMainWindow(_ window: NSWindow?) {
        mainWindow = window
    }

    func refresh(showInitialLoading: Bool = false, fromTimer: Bool = false) {
        if showInitialLoading {
            isLoading = true
        }
        guard !isRefreshInFlight else {
            if !fromTimer {
                hasPendingRefresh = true
            }
            return
        }

        isRefreshInFlight = true
        let detectionService = sessionDetectionService

        refreshQueue.async { [weak self] in
            let response = detectionService.getAllSessions()

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.apply(response: response)
                self.isLoading = false
                self.isRefreshInFlight = false

                guard self.hasPendingRefresh else {
                    return
                }
                self.hasPendingRefresh = false
                self.refresh()
            }
        }
    }

    func idleCount() -> Int {
        sessions.filter { $0.status == .idle }.count
    }

    func staleCount() -> Int {
        sessions.filter { $0.status == .stale }.count
    }

    func killSessions(by type: AgentType) {
        killSessions(sessions.filter { $0.agentType == type })
    }

    func killIdleSessions() {
        killSessions(sessions.filter { $0.status == .idle })
    }

    func killStaleSessions() {
        killSessions(sessions.filter { $0.status == .stale })
    }

    func killBackgroundSession(_ session: Session) {
        do {
            try coreActionsService.killSession(pid: session.pid)
        } catch {
            setActionError(error)
        }
        refresh()
    }

    func killAllBackgroundSessions() {
        killSessions(backgroundSessions)
    }

    func killProjectSessions(_ group: ProjectGroup) {
        killSessions(group.sessions)
    }

    func killSession(_ session: Session) {
        do {
            try coreActionsService.killSession(pid: session.pid)
        } catch {
            setActionError(error)
        }
        refresh()
    }

    func focusSession(_ session: Session) {
        let focused = coreActionsService.focusSession(pid: session.pid, projectPath: session.projectPath)
        if !focused {
            do {
                try coreActionsService.openInTerminal(path: session.projectPath)
            } catch {
                setActionError(error)
            }
        }
    }

    func openSession(_ session: Session) {
        openProject(path: session.projectPath, projectName: session.projectName)
    }

    func openProject(path: String, projectName: String) {
        switch cardClickAction {
        case .editor:
            openInEditor(path: path, projectName: projectName)
        case .terminal:
            openInTerminal(path: path)
        }
    }

    func openSessionInEditor(_ session: Session) {
        openInEditor(path: session.projectPath, projectName: session.projectName)
    }

    func openSessionInTerminal(_ session: Session) {
        openInTerminal(path: session.projectPath)
    }

    func openProjectInTerminal(path: String) {
        openInTerminal(path: path)
    }

    func runProjectCommand(projectPath: String, command: String) {
        do {
            try coreActionsService.runProjectCommand(
                path: projectPath,
                command: command,
                terminal: defaultTerminal
            )
        } catch {
            setActionError(error)
        }
    }

    func projectCommand(for projectPath: String, action: ProjectCommandAction) -> String {
        settings.projectCommand(for: projectPath, action: action)
    }

    func setProjectCommand(_ command: String, for projectPath: String, action: ProjectCommandAction) {
        settings.setProjectCommand(command, for: projectPath, action: action)
        showConfirmation("Saved \(action.label) command.")
    }

    func customName(for sessionID: String) -> String {
        settings.customName(for: sessionID) ?? ""
    }

    func customURL(for sessionID: String) -> String {
        settings.customURL(for: sessionID) ?? ""
    }

    func setCustomName(_ name: String, for sessionID: String) {
        settings.setCustomName(name, for: sessionID)
        objectWillChange.send()
    }

    func setCustomURL(_ url: String, for sessionID: String) {
        settings.setCustomURL(url, for: sessionID)
        objectWillChange.send()
    }

    func openCustomURL(for sessionID: String) {
        let rawValue = customURL(for: sessionID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else {
            return
        }

        let value: String
        if rawValue.hasPrefix("http://") || rawValue.hasPrefix("https://") {
            value = rawValue
        } else {
            value = "http://\(rawValue)"
        }

        guard let url = URL(string: value) else {
            setActionErrorMessage("Invalid URL: \(rawValue)")
            return
        }

        NSWorkspace.shared.open(url)
    }

    func openGitHub(for session: Session) {
        guard let raw = session.githubUrl,
              let url = URL(string: raw) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func toggleBellMode() {
        guard notificationState.installState == .installed else {
            return
        }

        notificationState.isLoading = true

        do {
            let nextValue = !notificationState.bellModeEnabled
            try notificationService.setBellMode(enabled: nextValue)
            notificationState.bellModeEnabled = nextValue
            showConfirmation(nextValue ? "Bell mode enabled." : "Voice mode enabled.")
        } catch {
            settingsError = error.localizedDescription
        }

        notificationState.isLoading = false
    }

    func installNotifications() {
        notificationState.isLoading = true

        do {
            try notificationService.installNotificationSystem()
            notificationState.installState = .installed
            notificationState.bellModeEnabled = (try? notificationService.checkBellMode()) ?? false
            showConfirmation("Notifications installed.")
        } catch {
            settingsError = error.localizedDescription
        }

        notificationState.isLoading = false
    }

    func uninstallNotifications() {
        notificationState.isLoading = true

        do {
            try notificationService.uninstallNotificationSystem()
            notificationState.installState = .notInstalled
            notificationState.bellModeEnabled = false
            showConfirmation("Notifications uninstalled.")
        } catch {
            settingsError = error.localizedDescription
        }

        notificationState.isLoading = false
    }

    func updateDisplayMode(_ mode: DisplayMode) {
        displayMode = mode
        settings.displayMode = mode
    }

    func updateTheme(_ value: ThemePreference) {
        theme = value
        settings.theme = value
    }

    func updateBackgroundImage(_ value: String) {
        backgroundImage = value
        settings.backgroundImage = value
    }

    func updateOverlayOpacity(_ value: Int) {
        let bounded = min(max(value, 0), 100)
        overlayOpacity = bounded
        settings.overlayOpacity = bounded
    }

    func updateOverlayColor(_ value: String) {
        let normalized = normalizedHexColor(value) ?? SettingsStore.defaultOverlayColor
        overlayColor = normalized
        settings.overlayColor = normalized
    }

    func updateCardClickAction(_ value: CardClickAction) {
        cardClickAction = value
        settings.cardClickAction = value
    }

    func updateDefaultEditor(_ value: DefaultEditor) {
        defaultEditor = value
        settings.defaultEditor = value
    }

    func updateCustomEditorCommand(_ value: String) {
        customEditorCommand = value
        settings.customEditorCommand = value
    }

    func updateUseSlowerCompatibleProjectSwitching(_ enabled: Bool) {
        useSlowerCompatibleProjectSwitching = enabled
        settings.useSlowerCompatibleProjectSwitching = enabled
        miniViewerController.setUseSlowerCompatibleProjectSwitching(enabled)
    }

    func updateDefaultTerminal(_ value: DefaultTerminal) {
        defaultTerminal = value
        settings.defaultTerminal = value
    }

    func updateCustomTerminalCommand(_ value: String) {
        customTerminalCommand = value
        settings.customTerminalCommand = value
    }

    func saveGlobalHotkey(_ shortcut: String) {
        settingsError = nil
        let normalized = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.isEmpty {
            clearGlobalHotkey()
            return
        }

        let success = hotkeyManager.registerAppToggleHotkey(normalized, fallback: normalized)
        if success {
            globalHotkey = normalized
            settings.globalHotkey = normalized
            showConfirmation("Global hotkey saved.")
        } else {
            settingsError = "Unable to register global hotkey."
        }
    }

    func clearGlobalHotkey() {
        hotkeyManager.unregisterAppToggleHotkey()
        globalHotkey = ""
        settings.globalHotkey = ""
        showConfirmation("Global hotkey cleared.")
    }

    func saveMiniViewerHotkey(_ shortcut: String) {
        settingsError = nil
        let normalized = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.isEmpty {
            clearMiniViewerHotkey()
            return
        }

        let success = hotkeyManager.registerMiniViewerHotkey(normalized, fallback: normalized)
        if success {
            miniViewerHotkey = normalized
            settings.miniViewerHotkey = normalized
            showConfirmation("Mini viewer hotkey saved.")
        } else {
            settingsError = "Unable to register mini viewer hotkey."
        }
    }

    func clearMiniViewerHotkey() {
        hotkeyManager.unregisterMiniViewerHotkey()
        miniViewerHotkey = ""
        settings.miniViewerHotkey = ""
        showConfirmation("Mini viewer hotkey cleared.")
    }

    func updateMiniViewerSide(_ value: MiniViewerSide) {
        miniViewerSide = value
        settings.miniViewerSide = value
        miniViewerController.setSide(value)
    }

    func updateMiniViewerShowOnStart(_ enabled: Bool) {
        miniViewerShowOnStart = enabled
        settings.miniViewerShowOnStart = enabled
    }

    func updateMainAppUIElementSize(_ value: UIElementSize) {
        mainAppUIElementSize = value
        settings.mainAppUIElementSize = value
    }

    func updateMiniViewerUIElementSize(_ value: UIElementSize) {
        miniViewerUIElementSize = value
        settings.miniViewerUIElementSize = value
        miniViewerController.setUIElementSize(value)
    }

    func showSettings() {
        settingsPresented = true
        settingsError = nil
    }

    func hideSettings() {
        settingsPresented = false
    }

    func toggleMainWindowVisibility() {
        guard let window = resolvedMainWindow() else {
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let shouldHide = window.isVisible && window.isKeyWindow && NSApplication.shared.isActive
        if shouldHide {
            window.orderOut(nil)
            return
        }

        showAndFocusMainWindow()
    }

    func showAndFocusMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        resolvedMainWindow()?.makeKeyAndOrderFront(nil)
    }

    func toggleMiniViewer() {
        do {
            try miniViewerController.toggle()
        } catch {
            setActionError(error)
        }
    }

    func showMiniViewer() {
        do {
            try miniViewerController.show()
        } catch {
            setActionError(error)
        }
    }

    private func prewarmMiniViewerForFastToggle() {
        do {
            try miniViewerController.prepareForFastToggle()
        } catch {
            setActionError(error)
        }
    }

    private func configureMenuBarCallbacks() {
        menuBarService.setup(
            onShowWindow: { [weak self] in
                DispatchQueue.main.async {
                    self?.showAndFocusMainWindow()
                }
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )

        menuBarService.updateTitle(total: totalCount, waiting: waitingCount)
    }

    private func configureHotkeys() {
        hotkeyManager.setCallbacks(
            onAppToggle: { [weak self] in
                DispatchQueue.main.async {
                    self?.toggleMainWindowVisibility()
                }
            },
            onMiniViewerToggle: { [weak self] in
                DispatchQueue.main.async {
                    self?.toggleMiniViewer()
                }
            }
        )

        if !globalHotkey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = hotkeyManager.registerAppToggleHotkey(globalHotkey)
        }

        if !miniViewerHotkey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = hotkeyManager.registerMiniViewerHotkey(miniViewerHotkey)
        }
    }

    private func applyMiniViewerSettings() {
        miniViewerController.setSide(miniViewerSide)
        miniViewerController.setUIElementSize(miniViewerUIElementSize)
        miniViewerController.setUseSlowerCompatibleProjectSwitching(useSlowerCompatibleProjectSwitching)
    }

    private func refreshNotificationState() {
        notificationState.isLoading = true

        let installed: Bool
        do {
            installed = try notificationService.checkNotificationSystemInstalled()
        } catch {
            notificationState.installState = .notInstalled
            notificationState.bellModeEnabled = false
            notificationState.isLoading = false
            settingsError = error.localizedDescription
            return
        }

        notificationState.installState = installed ? .installed : .notInstalled

        if installed {
            notificationState.bellModeEnabled = (try? notificationService.checkBellMode()) ?? false
        } else {
            notificationState.bellModeEnabled = false
        }

        notificationState.isLoading = false
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh(fromTimer: true)
            }
        }
    }

    private func apply(response: SessionsResponse) {
        let background: [Session]
        let visibleSessions: [Session]

        if response.backgroundSessions.isEmpty {
            background = response.sessions.filter(\.isBackground)
            visibleSessions = response.sessions.filter { !$0.isBackground }
        } else {
            background = response.backgroundSessions
            visibleSessions = response.sessions
        }

        let stableForeground = mergeWithStableOrder(
            existing: lastOrderedForegroundSessions,
            incoming: visibleSessions
        )

        sessions = stableForeground
        backgroundSessions = background
        totalCount = response.totalCount
        waitingCount = response.waitingCount
        agentCounts = makeAgentCounts(from: stableForeground)
        lastOrderedForegroundSessions = stableForeground
        updateGitDiffStats(for: stableForeground)

        errorMessage = nil
        menuBarService.updateTitle(total: totalCount, waiting: waitingCount)
    }

    private func killSessions(_ sessionsToKill: [Session]) {
        var firstError: Error?

        for session in sessionsToKill {
            do {
                try coreActionsService.killSession(pid: session.pid)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError {
            setActionError(firstError)
        }

        refresh()
    }

    private func openInEditor(path: String, projectName: String) {
        do {
            try coreActionsService.openInEditor(
                path: path,
                useSlowerCompatibleProjectSwitching: useSlowerCompatibleProjectSwitching,
                projectName: projectName
            )
        } catch {
            setActionError(error)
        }
    }

    private func openInTerminal(path: String) {
        do {
            try coreActionsService.openInTerminal(path: path, terminal: defaultTerminal)
        } catch {
            setActionError(error)
        }
    }

    private func resolvedMainWindow() -> NSWindow? {
        if let mainWindow {
            return mainWindow
        }

        if let keyWindow = NSApplication.shared.windows.first(where: { $0.canBecomeKey }) {
            return keyWindow
        }

        return NSApplication.shared.windows.first
    }

    private func setActionError(_ error: Error) {
        setActionErrorMessage(error.localizedDescription)
    }

    private func setActionErrorMessage(_ message: String) {
        if settingsPresented {
            settingsError = message
        } else {
            errorMessage = message
        }
    }

    private func showConfirmation(_ message: String) {
        settingsConfirmation = message

        confirmationResetTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.settingsConfirmation = nil
        }

        confirmationResetTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: task)
    }

    private func updateGitDiffStats(for foregroundSessions: [Session]) {
        let projectPaths = Array(Set(foregroundSessions.map(\.projectPath))).sorted()
        let now = Date()
        let cacheSnapshot = gitDiffCache
        let gitDiffStatsService = gitDiffStatsService

        gitDiffStatsGeneration += 1
        let generation = gitDiffStatsGeneration

        gitDiffStatsQueue.async { [weak self] in
            var nextCache: [String: CachedDiffStats] = [:]
            var nextStats: [String: GitDiffStats] = [:]

            for path in projectPaths {
                if let cached = cacheSnapshot[path],
                   now.timeIntervalSince(cached.fetchedAt) < CachedDiffStats.ttl {
                    nextCache[path] = cached
                    nextStats[path] = cached.stats
                    continue
                }

                let stats = gitDiffStatsService.diffStats(for: path)
                let cached = CachedDiffStats(stats: stats, fetchedAt: now)
                nextCache[path] = cached
                nextStats[path] = stats
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                guard self.gitDiffStatsGeneration == generation else {
                    return
                }
                self.gitDiffCache = nextCache
                self.gitDiffStatsByProjectPath = nextStats
            }
        }
    }

    private func makeAgentCounts(from sessions: [Session]) -> [AgentType: Int] {
        var counts: [AgentType: Int] = [
            .claude: 0,
            .codex: 0,
            .opencode: 0
        ]

        for session in sessions {
            counts[session.agentType, default: 0] += 1
        }

        return counts
    }

    private func orderingPriority(for status: SessionStatus) -> Int {
        switch status {
        case .thinking, .processing, .waiting:
            return 0
        case .idle:
            return 1
        case .stale:
            return 2
        }
    }

    private func mergeWithStableOrder(existing: [Session], incoming: [Session]) -> [Session] {
        guard !existing.isEmpty else {
            return incoming
        }

        let existingOrder = Dictionary(uniqueKeysWithValues: existing.enumerated().map { ($1.renderID, $0) })
        let existingPriority = Dictionary(uniqueKeysWithValues: existing.map { ($0.renderID, orderingPriority(for: $0.status)) })

        let hasNewSession = incoming.contains { existingOrder[$0.renderID] == nil }
        let priorityChanged = incoming.contains { session in
            guard let previousPriority = existingPriority[session.renderID] else {
                return false
            }
            return previousPriority != orderingPriority(for: session.status)
        }

        if hasNewSession || priorityChanged {
            return incoming
        }

        var incomingByID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.renderID, $0) })
        var merged: [Session] = []
        merged.reserveCapacity(incoming.count)

        for oldSession in existing {
            if let updated = incomingByID.removeValue(forKey: oldSession.renderID) {
                merged.append(updated)
            }
        }

        for remaining in incomingByID.values {
            merged.append(remaining)
        }

        return merged
    }

    private func normalizedHexColor(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 7,
              trimmed.hasPrefix("#") else {
            return nil
        }

        let hex = String(trimmed.dropFirst())
        let valid = hex.unicodeScalars.allSatisfy { scalar in
            CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains(scalar)
        }

        return valid ? trimmed.uppercased() : nil
    }
}

private struct CachedDiffStats {
    static let ttl: TimeInterval = 12

    let stats: GitDiffStats
    let fetchedAt: Date
}

extension SessionDetectionService: @unchecked Sendable {}
extension GitDiffStatsService: @unchecked Sendable {}
