import AppKit
import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    private static let mainWindowFrameAutosaveName = NSWindow.FrameAutosaveName("agent-manager-x-main-window")

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
    @Published var historyPresented = false
    @Published var settingsError: String?
    @Published var settingsConfirmation: String?

    @Published var displayMode: DisplayMode
    @Published var sessionDetailsRetrievalMode: SessionDetailsRetrievalMode
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
    @Published var miniViewerShowOnActiveMonitor: Bool
    @Published var miniViewerPinnedScreenTarget: MiniViewerScreenTarget
    @Published var miniViewerShowOnStart: Bool
    @Published var miniViewerShowRecentSessionsOnly: Bool
    @Published var miniViewerKeepOneSessionPerProjectWhenFilteringRecent: Bool
    @Published var miniViewerRecentActivityWindowMinutes: Int
    @Published var miniViewerMaxSessions: Int
    @Published var mainAppUIElementSize: UIElementSize
    @Published var miniViewerUIElementSize: UIElementSize
    @Published var notificationSound: NotificationSound
    @Published var showSessionFilePath: Bool

    @Published private(set) var notificationState = NotificationState()
    @Published private(set) var gitDiffStatsByProjectPath: [String: GitDiffStats] = [:]
    @Published private(set) var miniViewerScreenOptions: [MiniViewerScreenOption] = []
    @Published private(set) var miniViewerPinnedScreenWarning: String?

    private let settings: SettingsStore
    private let sessionDetectionService: SessionDetectionService
    private let coreActionsService: CoreActionsService
    private let gitDiffStatsService: GitDiffStatsService
    private let menuBarService: MenuBarService
    private let hotkeyManager: GlobalHotkeyManager
    private let miniViewerController: MiniViewerController
    private let notificationService: NotificationService
    private let vsmuxSessionBroker: VSmuxSessionBroker

    private var pollTimer: Timer?
    private var started = false
    private var lastOrderedForegroundSessions: [Session] = []
    private var gitDiffCache: [String: CachedDiffStats] = [:]
    private weak var mainWindow: NSWindow?
    private var configuredMainWindowID: ObjectIdentifier?
    private var confirmationResetTask: DispatchWorkItem?
    private var screenParametersObserver: NSObjectProtocol?
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
        notificationService: NotificationService = NotificationService(),
        vsmuxSessionBroker: VSmuxSessionBroker = VSmuxSessionBroker()
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
        self.vsmuxSessionBroker = vsmuxSessionBroker

        displayMode = settings.displayMode
        sessionDetailsRetrievalMode = settings.sessionDetailsRetrievalMode
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
        miniViewerShowOnActiveMonitor = settings.miniViewerShowOnActiveMonitor
        miniViewerPinnedScreenTarget = settings.miniViewerPinnedScreenTarget
        miniViewerShowOnStart = settings.miniViewerShowOnStart
        miniViewerShowRecentSessionsOnly = settings.miniViewerShowRecentSessionsOnly
        miniViewerKeepOneSessionPerProjectWhenFilteringRecent = settings.miniViewerKeepOneSessionPerProjectWhenFilteringRecent
        miniViewerRecentActivityWindowMinutes = settings.miniViewerRecentActivityWindowMinutes
        miniViewerMaxSessions = settings.miniViewerMaxSessions
        mainAppUIElementSize = settings.mainAppUIElementSize
        miniViewerUIElementSize = settings.miniViewerUIElementSize
        notificationSound = settings.notificationSound
        showSessionFilePath = settings.showSessionFilePath
        self.miniViewerController.setOpenMainWindowHandler { [weak self] in
            self?.showAndFocusMainWindow()
        }
        self.miniViewerController.setVSmuxSessionOpenHandler { [weak self] workspaceId, sessionId, projectPath, projectName in
            Task { @MainActor [weak self] in
                self?.openVSmuxSession(
                    workspaceId: workspaceId,
                    sessionId: sessionId,
                    projectPath: projectPath,
                    projectName: projectName
                )
            }
        }
        self.miniViewerController.setVSmuxSessionCloseHandler { [weak self] workspaceId, sessionId in
            Task { @MainActor [weak self] in
                self?.vsmuxSessionBroker.requestClose(workspaceId: workspaceId, sessionId: sessionId)
            }
        }
        self.vsmuxSessionBroker.onWorkspacesChanged = { [weak self] snapshots in
            Task { @MainActor [weak self] in
                self?.applyVSmuxWorkspaces(snapshots)
            }
        }

        refreshMiniViewerScreenState()
    }

    func start() {
        guard !started else {
            return
        }

        started = true
        startObservingScreenParameters()
        configureMenuBarCallbacks()
        configureHotkeys()
        applyMiniViewerSettings()
        refreshNotificationState()
        startActiveSessionSource()
        refresh(showInitialLoading: true)

        if miniViewerShowOnStart {
            showMiniViewer()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        hotkeyManager.unregisterAppToggleHotkey()
        hotkeyManager.unregisterMiniViewerHotkey()
        hotkeyManager.setCallbacks(onAppToggle: nil, onMiniViewerToggle: nil)
        stopObservingScreenParameters()
        menuBarService.teardown()
        miniViewerController.shutdown()
        vsmuxSessionBroker.stop()
        started = false
    }

    func attachMainWindow(_ window: NSWindow?) {
        guard let window else {
            mainWindow = nil
            configuredMainWindowID = nil
            return
        }

        mainWindow = window

        let windowID = ObjectIdentifier(window)
        guard configuredMainWindowID != windowID else {
            return
        }

        configuredMainWindowID = windowID
        configureMainWindow(window)
    }

    func refresh(showInitialLoading: Bool = false, fromTimer: Bool = false) {
        if sessionDetailsRetrievalMode == .vsmuxSessions {
            if showInitialLoading {
                isLoading = true
            }
            applyVSmuxWorkspaces(vsmuxSessionBroker.currentWorkspaces())
            return
        }

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
                guard self.sessionDetailsRetrievalMode == .processBased else {
                    self.isRefreshInFlight = false
                    self.hasPendingRefresh = false
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
        guard session.detailsSource == .processBased else {
            return
        }
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
        if session.detailsSource == .vsmuxSessions,
           let workspaceId = session.vsmuxWorkspaceID {
            vsmuxSessionBroker.requestClose(workspaceId: workspaceId, sessionId: session.id)
            return
        }

        do {
            try coreActionsService.killSession(pid: session.pid)
        } catch {
            setActionError(error)
        }
        refresh()
    }

    func focusSession(_ session: Session) {
        if session.detailsSource == .vsmuxSessions,
           let workspaceId = session.vsmuxWorkspaceID {
            openVSmuxSession(
                workspaceId: workspaceId,
                sessionId: session.id,
                projectPath: session.projectPath,
                projectName: session.projectName
            )
            return
        }

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
        if session.detailsSource == .vsmuxSessions,
           let workspaceId = session.vsmuxWorkspaceID {
            openVSmuxSession(
                workspaceId: workspaceId,
                sessionId: session.id,
                projectPath: session.projectPath,
                projectName: session.projectName
            )
            return
        }

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
            let soundPath = selectedNotificationSoundPath()
            try notificationService.setBellMode(enabled: nextValue, bellSoundPath: soundPath)
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

    func updateSessionDetailsRetrievalMode(_ mode: SessionDetailsRetrievalMode) {
        guard sessionDetailsRetrievalMode != mode else {
            return
        }

        sessionDetailsRetrievalMode = mode
        settings.sessionDetailsRetrievalMode = mode
        isLoading = true
        startActiveSessionSource()
        refresh(showInitialLoading: true)
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

    func updateNotificationSound(_ value: NotificationSound) {
        notificationSound = value
        settings.notificationSound = value

        guard notificationState.installState == .installed,
              notificationState.bellModeEnabled else {
            return
        }

        do {
            try notificationService.setBellMode(
                enabled: true,
                bellSoundPath: selectedNotificationSoundPath()
            )
            showConfirmation("Notification sound updated.")
        } catch {
            settingsError = error.localizedDescription
        }
    }

    func previewNotificationSound() {
        guard let soundPath = selectedNotificationSoundPath() else {
            settingsError = "Selected notification sound is unavailable."
            return
        }

        do {
            try notificationService.playNotificationSoundPreview(soundPath: soundPath)
        } catch {
            settingsError = error.localizedDescription
        }
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

    func updateMiniViewerShowOnActiveMonitor(_ enabled: Bool) {
        miniViewerShowOnActiveMonitor = enabled
        settings.miniViewerShowOnActiveMonitor = enabled
        miniViewerController.setScreenSelection(
            showOnActiveMonitor: enabled,
            pinnedScreenTarget: miniViewerPinnedScreenTarget
        )
        refreshMiniViewerScreenState()
        revealMiniViewerAfterScreenSelectionChangeIfNeeded()
    }

    func updateMiniViewerPinnedScreenTarget(_ value: MiniViewerScreenTarget) {
        miniViewerPinnedScreenTarget = value
        settings.miniViewerPinnedScreenTarget = value
        settings.miniViewerPinnedScreenNameSnapshot = snapshotLabel(for: value)
        miniViewerController.setScreenSelection(
            showOnActiveMonitor: miniViewerShowOnActiveMonitor,
            pinnedScreenTarget: value
        )
        refreshMiniViewerScreenState()
        revealMiniViewerAfterScreenSelectionChangeIfNeeded()
    }

    func updateMiniViewerShowOnStart(_ enabled: Bool) {
        miniViewerShowOnStart = enabled
        settings.miniViewerShowOnStart = enabled
    }

    func updateMiniViewerShowRecentSessionsOnly(_ enabled: Bool) {
        miniViewerShowRecentSessionsOnly = enabled
        settings.miniViewerShowRecentSessionsOnly = enabled
        miniViewerController.setRecentActivityFilter(
            enabled: enabled,
            minutes: miniViewerRecentActivityWindowMinutes,
            keepOneSessionPerProject: miniViewerKeepOneSessionPerProjectWhenFilteringRecent
        )
    }

    func updateMiniViewerKeepOneSessionPerProjectWhenFilteringRecent(_ enabled: Bool) {
        miniViewerKeepOneSessionPerProjectWhenFilteringRecent = enabled
        settings.miniViewerKeepOneSessionPerProjectWhenFilteringRecent = enabled
        miniViewerController.setRecentActivityFilter(
            enabled: miniViewerShowRecentSessionsOnly,
            minutes: miniViewerRecentActivityWindowMinutes,
            keepOneSessionPerProject: enabled
        )
    }

    func updateMiniViewerRecentActivityWindowMinutes(_ value: Int) {
        let clampedValue = max(1, value)
        miniViewerRecentActivityWindowMinutes = clampedValue
        settings.miniViewerRecentActivityWindowMinutes = clampedValue
        miniViewerController.setRecentActivityFilter(
            enabled: miniViewerShowRecentSessionsOnly,
            minutes: clampedValue,
            keepOneSessionPerProject: miniViewerKeepOneSessionPerProjectWhenFilteringRecent
        )
    }

    func updateMiniViewerMaxSessions(_ value: Int) {
        let clampedValue = max(1, value)
        miniViewerMaxSessions = clampedValue
        settings.miniViewerMaxSessions = clampedValue
        miniViewerController.setMaxSessions(clampedValue)
    }

    func updateShowSessionFilePath(_ enabled: Bool) {
        showSessionFilePath = enabled
        settings.showSessionFilePath = enabled
    }

    func updateMainAppUIElementSize(_ value: UIElementSize) {
        mainAppUIElementSize = value
        settings.mainAppUIElementSize = value
    }

    func increaseMainAppUIElementSizeFromShortcut() {
        guard isMainWindowContextActiveForShortcuts() else {
            return
        }
        stepMainAppUIElementSize(by: 1)
    }

    func decreaseMainAppUIElementSizeFromShortcut() {
        guard isMainWindowContextActiveForShortcuts() else {
            return
        }
        stepMainAppUIElementSize(by: -1)
    }

    func resetMainAppUIElementSizeToMediumFromShortcut() {
        guard isMainWindowContextActiveForShortcuts() else {
            return
        }

        updateMainAppUIElementSize(.medium)
    }

    func openProjectFromShortcutNumber(_ number: Int) {
        guard isMainWindowContextActiveForShortcuts(),
              (1...9).contains(number) else {
            return
        }

        let groups = ProjectGroup.grouped(from: sessions)
        let index = number - 1
        guard groups.indices.contains(index) else {
            return
        }

        let group = groups[index]
        openProject(path: group.projectPath, projectName: group.projectName)
    }

    func updateMiniViewerUIElementSize(_ value: UIElementSize) {
        let clampedValue = value.clampedForMiniViewer
        miniViewerUIElementSize = clampedValue
        settings.miniViewerUIElementSize = clampedValue
        miniViewerController.setUIElementSize(clampedValue)
    }

    func showSettings() {
        settingsPresented = true
        settingsError = nil
    }

    func hideSettings() {
        settingsPresented = false
    }

    func showHistory() {
        historyPresented = true
    }

    func hideHistory() {
        historyPresented = false
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
        updateGitDiffStats(for: sessions)
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
        miniViewerController.setScreenSelection(
            showOnActiveMonitor: miniViewerShowOnActiveMonitor,
            pinnedScreenTarget: miniViewerPinnedScreenTarget
        )
        miniViewerController.setUIElementSize(miniViewerUIElementSize)
        miniViewerController.setRecentActivityFilter(
            enabled: miniViewerShowRecentSessionsOnly,
            minutes: miniViewerRecentActivityWindowMinutes,
            keepOneSessionPerProject: miniViewerKeepOneSessionPerProjectWhenFilteringRecent
        )
        miniViewerController.setMaxSessions(miniViewerMaxSessions)
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

    private func selectedNotificationSoundPath() -> String? {
        let filename = notificationSound.filename
        let baseName = (filename as NSString).deletingPathExtension
        let fileExtension = (filename as NSString).pathExtension
        let systemPath = "/System/Library/Sounds/\(filename)"

        if let soundsSubdirectoryURL = Bundle.main.url(
            forResource: baseName,
            withExtension: fileExtension,
            subdirectory: "sounds"
        ) {
            return soundsSubdirectoryURL.path
        }

        if let rootURL = Bundle.main.url(
            forResource: baseName,
            withExtension: fileExtension
        ) {
            return rootURL.path
        }

        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }

        let nestedPath = resourceURL.appendingPathComponent("sounds/\(filename)").path
        if FileManager.default.fileExists(atPath: nestedPath) {
            return nestedPath
        }

        let rootPath = resourceURL.appendingPathComponent(filename).path
        if FileManager.default.fileExists(atPath: rootPath) {
            return rootPath
        }

        if FileManager.default.fileExists(atPath: systemPath) {
            return systemPath
        }

        return nil
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh(fromTimer: true)
            }
        }
    }

    private func apply(response: SessionsResponse) {
        miniViewerController.updateSessionsResponse(response)

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

    private func startActiveSessionSource() {
        pollTimer?.invalidate()
        pollTimer = nil

        if sessionDetailsRetrievalMode == .processBased {
            vsmuxSessionBroker.stop()
            startPolling()
            return
        }

        vsmuxSessionBroker.start()
    }

    private func applyVSmuxWorkspaces(_ workspaces: [VSmuxWorkspaceSnapshot]) {
        guard sessionDetailsRetrievalMode == .vsmuxSessions else {
            return
        }

        let response = makeVSmuxSessionsResponse(from: workspaces)
        apply(response: response)
        isLoading = false
        errorMessage = nil
    }

    private func makeVSmuxSessionsResponse(from workspaces: [VSmuxWorkspaceSnapshot]) -> SessionsResponse {
        let sessions = workspaces
            .flatMap { workspace in
                workspace.sessions.map { session in
                    Session(
                        id: session.sessionId,
                        agentType: mapVSmuxAgentType(session.agent),
                        projectName: workspace.workspaceName,
                        projectPath: workspace.workspacePath,
                        gitBranch: nil,
                        githubUrl: nil,
                        status: mapVSmuxStatus(session.status),
                        lastMessage: session.displayName,
                        lastMessageRole: nil,
                        lastActivityAt: session.lastActiveAt,
                        pid: 0,
                        cpuUsage: 0,
                        memoryBytes: 0,
                        activeSubagentCount: 0,
                        isBackground: false,
                        detailsSource: .vsmuxSessions,
                        vsmuxWorkspaceID: workspace.workspaceId,
                        vsmuxThreadID: session.threadId,
                        sessionFilePath: nil
                    )
                }
            }
            .sorted(by: compareVSmuxSessions)

        return SessionsResponse(
            sessions: sessions,
            backgroundSessions: [],
            totalCount: sessions.count,
            waitingCount: sessions.filter { $0.status == .waiting }.count
        )
    }

    private func compareVSmuxSessions(lhs: Session, rhs: Session) -> Bool {
        let lhsPriority = orderingPriority(for: lhs.status)
        let rhsPriority = orderingPriority(for: rhs.status)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        let lhsDate = SessionParsingSupport.parseISODate(lhs.lastActivityAt) ?? .distantPast
        let rhsDate = SessionParsingSupport.parseISODate(rhs.lastActivityAt) ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        if lhs.projectPath != rhs.projectPath {
            return lhs.projectPath < rhs.projectPath
        }

        return lhs.id < rhs.id
    }

    private func mapVSmuxAgentType(_ rawAgent: String) -> AgentType {
        switch rawAgent.lowercased() {
        case "claude":
            return .claude
        case "codex":
            return .codex
        case "gemini":
            return .gemini
        case "t3":
            return .t3
        default:
            return .opencode
        }
    }

    private func mapVSmuxStatus(_ rawStatus: String) -> SessionStatus {
        switch rawStatus.lowercased() {
        case "working":
            return .processing
        case "attention":
            return .waiting
        default:
            return .idle
        }
    }

    private func killSessions(_ sessionsToKill: [Session]) {
        var firstError: Error?

        for session in sessionsToKill {
            guard session.detailsSource == .processBased else {
                continue
            }
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

    private func openVSmuxSession(
        workspaceId: String,
        sessionId: String,
        projectPath: String,
        projectName: String
    ) {
        do {
            try coreActionsService.openInEditor(
                path: projectPath,
                useSlowerCompatibleProjectSwitching: useSlowerCompatibleProjectSwitching,
                projectName: projectName
            )
            vsmuxSessionBroker.requestFocus(workspaceId: workspaceId, sessionId: sessionId)
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

    private func configureMainWindow(_ window: NSWindow) {
        _ = window.setFrameAutosaveName(Self.mainWindowFrameAutosaveName)
    }

    private func isMainWindowContextActiveForShortcuts() -> Bool {
        guard NSApplication.shared.isActive,
              let mainWindow else {
            return false
        }

        if mainWindow.isKeyWindow {
            return true
        }

        guard let keyWindow = NSApplication.shared.keyWindow else {
            return false
        }

        return keyWindow.sheetParent == mainWindow
    }

    private func stepMainAppUIElementSize(by offset: Int) {
        let sizes = UIElementSize.allCases
        guard let currentIndex = sizes.firstIndex(of: mainAppUIElementSize) else {
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), sizes.count - 1)
        guard nextIndex != currentIndex else {
            return
        }

        updateMainAppUIElementSize(sizes[nextIndex])
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
        let shouldRefresh = settingsPresented ||
            historyPresented ||
            (resolvedMainWindow()?.isVisible ?? false)

        guard shouldRefresh else {
            return
        }

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

    private func startObservingScreenParameters() {
        guard screenParametersObserver == nil else {
            refreshMiniViewerScreenState()
            return
        }

        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshMiniViewerScreenState()
            }
        }

        refreshMiniViewerScreenState()
    }

    private func stopObservingScreenParameters() {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
        screenParametersObserver = nil
    }

    private func refreshMiniViewerScreenState() {
        let catalog = MiniViewerScreenCatalog(
            pinnedTarget: miniViewerPinnedScreenTarget,
            pinnedLabelSnapshot: settings.miniViewerPinnedScreenNameSnapshot
        )
        miniViewerScreenOptions = catalog.options
        miniViewerPinnedScreenWarning = miniViewerShowOnActiveMonitor ? nil : catalog.warningMessage
    }

    private func snapshotLabel(for target: MiniViewerScreenTarget) -> String {
        switch target {
        case .primary:
            return ""
        case .builtIn:
            return "Built-in screen"
        case .display:
            return miniViewerScreenOptions.first(where: { $0.target == target })?.label ?? settings.miniViewerPinnedScreenNameSnapshot
        }
    }

    private func revealMiniViewerAfterScreenSelectionChangeIfNeeded() {
        guard miniViewerHasVisibleSessions() else {
            return
        }

        showMiniViewer()
    }

    private func miniViewerHasVisibleSessions() -> Bool {
        var visibleSessions = sessions

        if miniViewerShowRecentSessionsOnly {
            let cutoff = Date().addingTimeInterval(TimeInterval(-miniViewerRecentActivityWindowMinutes * 60))
            let recentSessions = visibleSessions.filter { session in
                guard let lastActivityDate = SessionParsingSupport.parseISODate(session.lastActivityAt) else {
                    return false
                }
                return lastActivityDate >= cutoff
            }

            if miniViewerKeepOneSessionPerProjectWhenFilteringRecent {
                return !visibleSessions.isEmpty
            }

            visibleSessions = recentSessions
        }

        return !visibleSessions.prefix(miniViewerMaxSessions).isEmpty
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

struct MiniViewerScreenOption: Identifiable, Hashable {
    let target: MiniViewerScreenTarget
    let label: String

    var id: String {
        target.storageValue
    }
}

private struct MiniViewerScreenCatalog {
    let options: [MiniViewerScreenOption]
    let warningMessage: String?

    init(pinnedTarget: MiniViewerScreenTarget, pinnedLabelSnapshot: String) {
        let detectedDisplays = NSScreen.screens.compactMap(MiniViewerDetectedDisplay.init(screen:))
        let detectedDisplaysByTarget = Dictionary(uniqueKeysWithValues: detectedDisplays.map { ($0.target, $0) })

        var builtOptions: [MiniViewerScreenOption] = [
            MiniViewerScreenOption(target: .primary, label: "Primary screen")
        ]

        let builtInDisplay = detectedDisplays.first(where: \.isBuiltIn)
        if let builtInDisplay {
            builtOptions.append(MiniViewerScreenOption(target: .builtIn, label: builtInDisplay.builtInLabel))
        } else if pinnedTarget == .builtIn {
            builtOptions.append(MiniViewerScreenOption(target: .builtIn, label: "Built-in screen"))
        }

        let externalOptions = detectedDisplays
            .filter { !$0.isBuiltIn }
            .map { MiniViewerScreenOption(target: $0.target, label: $0.optionLabel) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        builtOptions.append(contentsOf: externalOptions)

        if case let .display(identifier) = pinnedTarget,
           detectedDisplaysByTarget[pinnedTarget] == nil {
            let fallbackLabel = pinnedLabelSnapshot.isEmpty
                ? "External display [\(MiniViewerDetectedDisplay.shortIdentifier(for: identifier))]"
                : pinnedLabelSnapshot
            builtOptions.append(MiniViewerScreenOption(target: .display(identifier), label: fallbackLabel))
        }

        options = builtOptions

        switch pinnedTarget {
        case .primary:
            warningMessage = nil
        case .builtIn:
            if builtInDisplay != nil {
                warningMessage = nil
            } else {
                warningMessage = "Built-in screen is unavailable. Mini viewer is temporarily using Primary screen until it returns."
            }
        case .display:
            if detectedDisplaysByTarget[pinnedTarget] == nil {
                let label = builtOptions.first(where: { $0.target == pinnedTarget })?.label ?? "Selected screen"
                warningMessage = "\(label) is unavailable. Mini viewer is temporarily using Primary screen until it returns."
            } else {
                warningMessage = nil
            }
        }
    }
}

private struct MiniViewerDetectedDisplay {
    let target: MiniViewerScreenTarget
    let optionLabel: String
    let builtInLabel: String
    let isBuiltIn: Bool

    init?(screen: NSScreen) {
        guard let displayID = screen.agentManagerXDisplayID else {
            return nil
        }

        let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
        self.isBuiltIn = isBuiltIn

        if isBuiltIn {
            target = .display(Self.stableIdentifier(for: displayID))
            builtInLabel = "Built-in screen"
            optionLabel = builtInLabel
            return
        }

        let identifier = Self.stableIdentifier(for: displayID)
        let name = Self.friendlyExternalName(for: screen)
        target = .display(identifier)
        builtInLabel = "Built-in screen"
        optionLabel = "\(name) [\(Self.shortIdentifier(for: identifier))]"
    }

    private static func friendlyExternalName(for screen: NSScreen) -> String {
        let trimmedName = screen.localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "External display" : trimmedName
    }

    private static func stableIdentifier(for displayID: CGDirectDisplayID) -> String {
        if let unmanaged = CGDisplayCreateUUIDFromDisplayID(displayID) {
            let uuid = unmanaged.takeRetainedValue()
            return (CFUUIDCreateString(nil, uuid) as String).uppercased()
        }

        return "display-\(displayID)"
    }

    static func shortIdentifier(for identifier: String) -> String {
        let normalized = identifier
            .replacingOccurrences(of: "display:", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        return String(normalized.prefix(8))
    }
}

private extension NSScreen {
    var agentManagerXDisplayID: CGDirectDisplayID? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}

private struct CachedDiffStats {
    static let ttl: TimeInterval = 12

    let stats: GitDiffStats
    let fetchedAt: Date
}

extension SessionDetectionService: @unchecked Sendable {}
extension GitDiffStatsService: @unchecked Sendable {}
