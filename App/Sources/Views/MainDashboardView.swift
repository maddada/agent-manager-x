import AppKit
import SwiftUI

struct MainDashboardView: View {
    @EnvironmentObject private var store: AppStore

    private var groupedProjects: [ProjectGroup] {
        ProjectGroup.grouped(from: store.sessions)
    }

    var body: some View {
        ZStack {
            BackgroundLayer(
                imageURLString: store.backgroundImage,
                overlayColor: Color(hex: store.overlayColor) ?? .black,
                overlayOpacity: Double(store.overlayOpacity) / 100.0
            )

            VStack(spacing: 0) {
                AppHeaderView()
                Divider()
                MainContentView(groups: groupedProjects)
            }
        }
        .sheet(isPresented: $store.settingsPresented) {
            SettingsSheetView()
                .environmentObject(store)
        }
        .background(
            WindowAccessor { window in
                store.attachMainWindow(window)
            }
        )
    }
}

private struct BackgroundLayer: View {
    let imageURLString: String
    let overlayColor: Color
    let overlayOpacity: Double

    var body: some View {
        ZStack {
            if let url = URL(string: imageURLString), !imageURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                            .ignoresSafeArea()
                    default:
                        Color(nsColor: .windowBackgroundColor)
                            .ignoresSafeArea()
                    }
                }
            } else {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
            }

            overlayColor
                .opacity(overlayOpacity)
                .ignoresSafeArea()
        }
    }
}

private struct AppHeaderView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showBackgroundPanel = false

    private let agentTypeOrder: [AgentType] = [.claude, .codex, .opencode]

    var body: some View {
        HStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Text("Agent Manager X")
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(minWidth: 0, alignment: .leading)

                    if store.totalCount > 0 {
                        StatBadge(label: "\(store.totalCount) active", tint: .blue)
                            .layoutPriority(1)
                    }

                    if store.waitingCount > 0 {
                        StatBadge(label: "\(store.waitingCount) waiting", tint: .yellow)
                            .layoutPriority(1)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    if store.totalCount > 0 {
                        StatBadge(label: "\(store.totalCount) active", tint: .blue)
                    }

                    if store.waitingCount > 0 {
                        StatBadge(label: "\(store.waitingCount) waiting", tint: .yellow)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)

            HStack(spacing: 8) {
                if !store.backgroundSessions.isEmpty {
                    Button {
                        showBackgroundPanel.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Text("BG")
                            StatBadge(label: "\(store.backgroundSessions.count)", tint: .gray)
                        }
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .pointerCursor()
                    .help("Background sessions")
                    .popover(isPresented: $showBackgroundPanel, arrowEdge: .bottom) {
                        BackgroundSessionsPanel()
                            .environmentObject(store)
                            .frame(width: 320)
                            .padding(12)
                    }
                }

                if store.idleCount() > 0 {
                    Button {
                        store.killIdleSessions()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Idle")
                            StatBadge(label: "\(store.idleCount())", tint: .gray)
                        }
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .pointerCursor()
                    .help("Kill idle sessions")
                }

                if store.staleCount() > 0 {
                    Button {
                        store.killStaleSessions()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Stale")
                            StatBadge(label: "\(store.staleCount())", tint: .gray)
                        }
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .pointerCursor()
                    .help("Kill stale sessions")
                }

                ForEach(agentTypeOrder, id: \.rawValue) { type in
                    let count = store.agentCounts[type, default: 0]
                    if count > 0 {
                        Button {
                            store.killSessions(by: type)
                        } label: {
                            HStack(spacing: 6) {
                                Text(type.rawValue.capitalized)
                                StatBadge(label: "\(count)", tint: .gray)
                            }
                        }
                        .buttonStyle(.borderless)
                        .focusable(false)
                        .pointerCursor()
                        .help("Kill all \(type.rawValue) sessions")
                    }
                }

                if store.notificationState.installState == .installed {
                    Button {
                        store.toggleBellMode()
                    } label: {
                        Image(systemName: store.notificationState.bellModeEnabled ? "bell.fill" : "waveform")
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .disabled(store.notificationState.isLoading)
                    .pointerCursor()
                    .help(store.notificationState.bellModeEnabled ? "Bell mode" : "Voice mode")
                }

                Button {
                    let nextMode: DisplayMode = store.displayMode == .list ? .masonry : .list
                    store.updateDisplayMode(nextMode)
                } label: {
                    Image(systemName: store.displayMode == .list ? "square.grid.2x2" : "list.bullet")
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .pointerCursor()
                .help(store.displayMode == .list ? "Switch to grid" : "Switch to list")

                Button {
                    store.showSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .pointerCursor()
                .help("Settings")

                Button {
                    store.refresh(showInitialLoading: true)
                } label: {
                    if store.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .pointerCursor()
                .help("Refresh")
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

private struct BackgroundSessionsPanel: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Background Sessions")
                .font(.headline)

            Text("Background agent helpers detected without a user-facing terminal session.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(store.backgroundSessions, id: \.renderID) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.agentType.rawValue.capitalized)
                                    .font(.subheadline.weight(.medium))
                                Text("pid \(session.pid)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                store.killBackgroundSession(session)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .pointerCursor()
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                    }
                }
                .mainAppScrollbarStyle(for: store.mainAppUIElementSize)
            }
            .frame(maxHeight: 220)

            Button("Close All", role: .destructive) {
                store.killAllBackgroundSessions()
            }
            .buttonStyle(.bordered)
            .focusable(false)
            .pointerCursor()
        }
    }
}

private struct MainContentView: View {
    @EnvironmentObject private var store: AppStore
    let groups: [ProjectGroup]

    private let gridColumns = [GridItem(.adaptive(minimum: 360), spacing: 14, alignment: .top)]

    var body: some View {
        Group {
            if store.isLoading && store.sessions.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading sessions…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = store.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No active sessions")
                        .font(.headline)
                    Text("Start an agent session to see it here.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.displayMode == .list {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(groups) { group in
                            ProjectGroupCardView(group: group, compactSessions: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .mainAppScrollbarStyle(for: store.mainAppUIElementSize)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: gridColumns, spacing: 14) {
                        ForEach(groups) { group in
                            ProjectGroupCardView(group: group, compactSessions: false)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .mainAppScrollbarStyle(for: store.mainAppUIElementSize)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

private struct ProjectGroupCardView: View {
    @EnvironmentObject private var store: AppStore

    let group: ProjectGroup
    let compactSessions: Bool

    @State private var commandEditorAction: ProjectCommandAction = .run
    @State private var commandDraft = ""
    @State private var commandEditorVisible = false
    @State private var runAfterSave = false
    @State private var activePopoverSessionID: String?

    private var groupBranch: String? {
        group.sessions
            .compactMap(\.gitBranch)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private var diffStats: GitDiffStats? {
        store.gitDiffStatsByProjectPath[group.projectPath]
    }

    private var hasDiffStats: Bool {
        guard let diffStats else {
            return false
        }
        return diffStats.additions > 0 || diffStats.deletions > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProjectGroupHeaderView(
                group: group,
                branch: groupBranch,
                diffStats: diffStats,
                hasDiffStats: hasDiffStats,
                actionsOnNewRow: !compactSessions,
                onKillAll: {
                    store.killProjectSessions(group)
                },
                onOpenProject: {
                    store.openProject(path: group.projectPath, projectName: group.projectName)
                },
                onOpenInTerminal: {
                    store.openProjectInTerminal(path: group.projectPath)
                },
                onRunAction: { action in
                    runProjectAction(action)
                },
                onEditAction: { action in
                    openCommandEditor(for: action, runAfterSave: false)
                }
            )

            Divider()
                .padding(.horizontal, 12)

            VStack(spacing: compactSessions ? 8 : 10) {
                ForEach(group.sessions, id: \.renderID) { session in
                    SessionCardView(
                        session: session,
                        compact: compactSessions,
                        onMessagePopoverVisibilityChanged: { presented in
                            if presented {
                                activePopoverSessionID = session.renderID
                            } else if activePopoverSessionID == session.renderID {
                                activePopoverSessionID = nil
                            }
                        }
                    )
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .zIndex(activePopoverSessionID == nil ? 0 : 10_000)
        .sheet(isPresented: $commandEditorVisible) {
            ProjectCommandDialog(
                action: commandEditorAction,
                command: $commandDraft,
                runAfterSave: runAfterSave,
                projectName: group.projectName,
                onCancel: {
                    commandEditorVisible = false
                },
                onSave: {
                    let trimmed = commandDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.setProjectCommand(trimmed, for: group.projectPath, action: commandEditorAction)
                    commandEditorVisible = false
                    if runAfterSave, !trimmed.isEmpty {
                        store.runProjectCommand(projectPath: group.projectPath, command: trimmed)
                    }
                }
            )
        }
    }

    private func runProjectAction(_ action: ProjectCommandAction) {
        let command = store.projectCommand(for: group.projectPath, action: action)
        if command.isEmpty {
            openCommandEditor(for: action, runAfterSave: true)
            return
        }

        store.runProjectCommand(projectPath: group.projectPath, command: command)
    }

    private func openCommandEditor(for action: ProjectCommandAction, runAfterSave: Bool) {
        commandEditorAction = action
        commandDraft = store.projectCommand(for: group.projectPath, action: action)
        self.runAfterSave = runAfterSave
        commandEditorVisible = true
    }
}

private struct ProjectGroupHeaderView: View {
    @EnvironmentObject private var store: AppStore

    let group: ProjectGroup
    let branch: String?
    let diffStats: GitDiffStats?
    let hasDiffStats: Bool
    let actionsOnNewRow: Bool
    let onKillAll: () -> Void
    let onOpenProject: () -> Void
    let onOpenInTerminal: () -> Void
    let onRunAction: (ProjectCommandAction) -> Void
    let onEditAction: (ProjectCommandAction) -> Void
    @State private var isHoveringHeader = false

    var body: some View {
        VStack(alignment: .leading, spacing: actionsOnNewRow ? 8 : 0) {
            HStack(alignment: .top, spacing: 10) {
                Button(role: .destructive, action: onKillAll) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.red))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .hoverPointerCursor()
                .help("Kill all sessions in project")
                .opacity(isHoveringHeader ? 1 : 0)
                .allowsHitTesting(isHoveringHeader)
                .layoutPriority(2)

                Button(action: onOpenProject) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.projectName)
                            .font(store.mainAppUIElementSize.projectHeaderTitleFont)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(minWidth: 0, alignment: .leading)

                        Text(truncatePath(group.projectPath))
                            .font(store.mainAppUIElementSize.projectHeaderMetaFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(minWidth: 0, alignment: .leading)

                        HStack(spacing: 8) {
                            if let branch {
                                Label(branch, systemImage: "arrow.triangle.branch")
                                    .font(store.mainAppUIElementSize.projectHeaderMetaFont)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .layoutPriority(0)
                            }

                            if hasDiffStats, let diffStats {
                                HStack(spacing: 6) {
                                    Text("+\(diffStats.additions)")
                                        .foregroundStyle(.green)
                                    Text("-\(diffStats.deletions)")
                                        .foregroundStyle(.red)
                                }
                                .font(store.mainAppUIElementSize.projectHeaderMetaMonospacedFont)
                                .layoutPriority(1)
                            }

                            Text("\(group.sessions.count) session\(group.sessions.count == 1 ? "" : "s")")
                                .font(store.mainAppUIElementSize.projectHeaderMetaFont)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .layoutPriority(1)
                        }
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .hoverPointerCursor()
                .help("Open project")
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)

                if !actionsOnNewRow {
                    projectActionButtons
                        .layoutPriority(2)
                }
            }

            if actionsOnNewRow {
                HStack {
                    projectActionButtons
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .onHover { hovering in
            isHoveringHeader = hovering
        }
        .onMiddleClick(perform: onKillAll)
    }

    private var projectActionButtons: some View {
        HStack(spacing: 6) {
            Button("Terminal", action: onOpenInTerminal)
                .buttonStyle(.bordered)
                .focusable(false)
                .hoverPointerCursor()
                .controlSize(.small)

            ForEach(ProjectCommandAction.allCases, id: \.rawValue) { action in
                ProjectQuickActionButton(
                    title: action.label,
                    action: action,
                    onRun: onRunAction,
                    onEdit: onEditAction
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ProjectQuickActionButton: View {
    let title: String
    let action: ProjectCommandAction
    let onRun: (ProjectCommandAction) -> Void
    let onEdit: (ProjectCommandAction) -> Void

    var body: some View {
        Button(title) {
            onRun(action)
        }
        .buttonStyle(.bordered)
        .focusable(false)
        .hoverPointerCursor()
        .controlSize(.small)
        .contextMenu {
            Button("Edit Command") {
                onEdit(action)
            }
        }
    }
}

private struct SessionCardView: View {
    @EnvironmentObject private var store: AppStore

    let session: Session
    let compact: Bool
    let onMessagePopoverVisibilityChanged: (Bool) -> Void

    @State private var renameDialogVisible = false
    @State private var urlDialogVisible = false
    @State private var renameDraft = ""
    @State private var urlDraft = ""
    @State private var isHoveringCard = false
    @State private var isMessagePreviewHovered = false
    @State private var isMessagePopoverHovered = false
    @State private var isMessagePopoverPresented = false
    @State private var showMessagePopoverTask: DispatchWorkItem?
    @State private var hideMessagePopoverTask: DispatchWorkItem?

    private var customName: String {
        store.customName(for: session.id)
    }

    private var customURL: String {
        store.customURL(for: session.id)
    }

    private var statusStyle: SessionStatusStyle {
        SessionStatusStyle.from(status: session.status)
    }

    private var previewText: String {
        let fallback = session.status == .idle || session.status == .stale ? "No recent messages" : statusStyle.label
        guard let message = session.lastMessage,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }

        return message
    }

    private var fullMessage: String? {
        guard let message = session.lastMessage else {
            return nil
        }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var messagePopoverSize: CGSize {
        compact ? CGSize(width: 430, height: 210) : CGSize(width: 520, height: 240)
    }

    private func scheduleMessagePopoverShow() {
        hideMessagePopoverTask?.cancel()
        showMessagePopoverTask?.cancel()
        guard fullMessage != nil else {
            return
        }

        let task = DispatchWorkItem {
            if isMessagePreviewHovered {
                isMessagePopoverPresented = true
            }
        }
        showMessagePopoverTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: task)
    }

    private func scheduleMessagePopoverHide() {
        showMessagePopoverTask?.cancel()
        hideMessagePopoverTask?.cancel()
        let task = DispatchWorkItem {
            if !isMessagePreviewHovered && !isMessagePopoverHovered {
                isMessagePopoverPresented = false
            }
        }
        hideMessagePopoverTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: task)
    }

    private var metricsLine: String {
        let timeAgo = formatTimeAgo(session.lastActivityAt)
        var parts = [
            "PID \(session.pid)",
            "\(session.cpuUsage.formatted(.number.precision(.fractionLength(0))))%",
            formatMemory(session.memoryBytes),
            timeAgo
        ]

        if session.activeSubagentCount > 0 {
            parts.append("+\(session.activeSubagentCount)")
        }

        return parts.joined(separator: " • ")
    }

    private var cardTopPadding: CGFloat {
        compact ? 8 : 9
    }

    private var messageTopPadding: CGFloat {
        compact ? 8 : 10
    }

    private var metricsTopPadding: CGFloat {
        compact ? 6 : 8
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    Text(statusStyle.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(statusStyle.badgeBackground))
                        .foregroundStyle(statusStyle.accent)
                        .layoutPriority(2)

                    if !customName.isEmpty {
                        Text(customName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(minWidth: 0, alignment: .leading)
                    }

                    Spacer(minLength: 8)

                    AgentMarkerView(agentType: session.agentType, color: statusStyle.accent)
                        .layoutPriority(2)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                Text(previewText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(compact ? 1 : 3)
                    .truncationMode(.tail)
                    .padding(.top, messageTopPadding)
                    .onHover { hovering in
                        isMessagePreviewHovered = hovering
                        if hovering {
                            scheduleMessagePopoverShow()
                        } else {
                            scheduleMessagePopoverHide()
                        }
                    }

                Text(metricsLine)
                    .font(store.mainAppUIElementSize.sessionMetricsFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, metricsTopPadding)
            }
            .padding(.top, cardTopPadding)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(statusStyle.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(statusStyle.cardBorder, lineWidth: 1)
            )

            Button(role: .destructive) {
                store.killSession(session)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.red))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .offset(x: -8, y: -8)
            .opacity(isHoveringCard ? 1 : 0)
            .allowsHitTesting(isHoveringCard)
            .help("Kill session")

            if !customURL.isEmpty {
                Button {
                    store.openCustomURL(for: session.id)
                } label: {
                    Image(systemName: "link")
                        .font(.caption)
                        .padding(6)
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .offset(x: compact ? 6 : 10, y: compact ? 72 : 96)
                .help(customURL)
            }

        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHoveringCard = hovering
        }
        .onChange(of: isHoveringCard) { _, hovering in
            if !hovering {
                scheduleMessagePopoverHide()
            }
        }
        .onTapGesture {
            store.openSession(session)
        }
        .onMiddleClick(perform: {
            store.killSession(session)
        })
        .overlay(alignment: .top) {
            if isMessagePopoverPresented, let fullMessage {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(fullMessage)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .mainAppScrollbarStyle(for: store.mainAppUIElementSize)
                .frame(width: messagePopoverSize.width, height: messagePopoverSize.height)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.24), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 4)
                .offset(y: compact ? 62 : 92)
                .zIndex(3000)
                .onTapGesture {
                    showMessagePopoverTask?.cancel()
                    hideMessagePopoverTask?.cancel()
                    isMessagePopoverPresented = false
                    isMessagePopoverHovered = false
                    isMessagePreviewHovered = false
                }
                .onHover { hovering in
                    isMessagePopoverHovered = hovering
                    if hovering {
                        hideMessagePopoverTask?.cancel()
                    } else {
                        scheduleMessagePopoverHide()
                    }
                }
            }
        }
        .zIndex(isMessagePopoverPresented ? 20_000 : 0)
        .onDisappear {
            showMessagePopoverTask?.cancel()
            hideMessagePopoverTask?.cancel()
            isMessagePopoverPresented = false
            isMessagePreviewHovered = false
            isMessagePopoverHovered = false
            onMessagePopoverVisibilityChanged(false)
        }
        .onChange(of: isMessagePopoverPresented) { _, presented in
            onMessagePopoverVisibilityChanged(presented)
        }
        .pointerCursor()
        .contextMenu {
            Button("Open in Editor") {
                store.openSessionInEditor(session)
            }

            Button("Open in Terminal") {
                store.openSessionInTerminal(session)
            }

            Button("Focus Session") {
                store.focusSession(session)
            }

            Divider()

            Button(customName.isEmpty ? "Rename" : "Rename (Custom)") {
                renameDraft = customName.isEmpty ? session.projectName : customName
                renameDialogVisible = true
            }

            Button(customURL.isEmpty ? "Set URL" : "Edit URL") {
                urlDraft = customURL
                urlDialogVisible = true
            }

            if !customURL.isEmpty {
                Button("Open URL") {
                    store.openCustomURL(for: session.id)
                }
            }

            if session.githubUrl != nil {
                Button("Open GitHub") {
                    store.openGitHub(for: session)
                }
            }

            Divider()

            Button("Kill Session", role: .destructive) {
                store.killSession(session)
            }
        }
        .sheet(isPresented: $renameDialogVisible) {
            RenameDialog(
                title: "Rename Session",
                originalName: session.projectName,
                value: $renameDraft,
                hasCustomValue: !customName.isEmpty,
                onCancel: {
                    renameDialogVisible = false
                },
                onReset: {
                    store.setCustomName("", for: session.id)
                    renameDialogVisible = false
                },
                onSave: {
                    store.setCustomName(renameDraft, for: session.id)
                    renameDialogVisible = false
                }
            )
        }
        .sheet(isPresented: $urlDialogVisible) {
            URLDialog(
                title: "Session URL",
                value: $urlDraft,
                hasCustomValue: !customURL.isEmpty,
                onCancel: {
                    urlDialogVisible = false
                },
                onClear: {
                    store.setCustomURL("", for: session.id)
                    urlDialogVisible = false
                },
                onSave: {
                    store.setCustomURL(urlDraft, for: session.id)
                    urlDialogVisible = false
                }
            )
        }
    }
}

private struct AgentMarkerView: View {
    let agentType: AgentType
    let color: Color

    private var label: String {
        switch agentType {
        case .claude: return "CL"
        case .codex: return "CX"
        case .opencode: return "OC"
        }
    }

    private var fallbackLabelView: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.22)))
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func iconImageView(_ image: NSImage) -> some View {
        if agentType == .codex {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(.primary)
        } else {
            Image(nsImage: image)
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 16, height: 16)
        }
    }

    var body: some View {
        if let image = AgentIconProvider.image(for: agentType) {
            iconImageView(image)
            .padding(4)
            .background(Circle().fill(Color.primary.opacity(0.10)))
            .overlay(
                Circle()
                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
            )
        } else {
            fallbackLabelView
        }
    }
}

extension View {
    func pointerCursor() -> some View {
        modifier(PointerCursorModifier())
    }

    func onMiddleClick(perform action: @escaping () -> Void) -> some View {
        overlay(MiddleClickListener(onMiddleClick: action))
    }

    func hoverPointerCursor() -> some View {
        modifier(HoverPointerCursorModifier())
    }
}

private struct PointerCursorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(
                PointerCursorRegion()
                    .allowsHitTesting(false)
            )
    }
}

private struct PointerCursorRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> PointerCursorNSView {
        PointerCursorNSView()
    }

    func updateNSView(_ nsView: PointerCursorNSView, context: Context) {
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

private final class PointerCursorNSView: NSView {
    override var isOpaque: Bool {
        false
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }
}

private struct HoverPointerCursorModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
                isHovering = hovering
            }
            .onDisappear {
                if isHovering {
                    NSCursor.arrow.set()
                    isHovering = false
                }
            }
    }
}

private struct MiddleClickListener: NSViewRepresentable {
    let onMiddleClick: () -> Void

    func makeNSView(context: Context) -> MiddleClickNSView {
        let view = MiddleClickNSView()
        view.onMiddleClick = onMiddleClick
        return view
    }

    func updateNSView(_ nsView: MiddleClickNSView, context: Context) {
        nsView.onMiddleClick = onMiddleClick
    }

    static func dismantleNSView(_ nsView: MiddleClickNSView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

private final class MiddleClickNSView: NSView {
    var onMiddleClick: (() -> Void)?
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMonitoring()
        } else {
            startMonitoringIfNeeded()
        }
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoringIfNeeded() {
        guard monitor == nil else {
            return
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseUp]) { [weak self] event in
            guard let self, event.buttonNumber == 2 else {
                return event
            }

            guard self.window === event.window else {
                return event
            }

            let point = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(point) else {
                return event
            }

            self.onMiddleClick?()
            return nil
        }
    }

    func stopMonitoring() {
        guard let monitor else {
            return
        }

        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}

private enum AgentIconProvider {
    private static let fileNames: [AgentType: String] = [
        .claude: "claude",
        .codex: "codex",
        .opencode: "opencode"
    ]

    private static var cache: [AgentType: NSImage] = [:]

    static func image(for agentType: AgentType) -> NSImage? {
        if let cached = cache[agentType] {
            return cached
        }

        guard let fileName = fileNames[agentType],
              let iconURL = iconURL(for: fileName),
              let icon = NSImage(contentsOf: iconURL)
        else {
            return nil
        }

        cache[agentType] = icon
        return icon
    }

    private static func iconURL(for fileName: String) -> URL? {
        if let bundled = Bundle.main.url(
            forResource: fileName,
            withExtension: "svg",
            subdirectory: "native-mini-viewer/icons"
        ) {
            return bundled
        }

        if let bundledAtRoot = Bundle.main.url(forResource: fileName, withExtension: "svg") {
            return bundledAtRoot
        }

        // Development fallback for local runs where resources are not yet copied into the app bundle.
        let sourceURL = URL(fileURLWithPath: #filePath)
        let repoRoot = sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let devPath = repoRoot
            .appendingPathComponent("App", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("native-mini-viewer", isDirectory: true)
            .appendingPathComponent("icons", isDirectory: true)
            .appendingPathComponent("\(fileName).svg")

        if FileManager.default.fileExists(atPath: devPath.path) {
            return devPath
        }

        return nil
    }
}

private struct SessionStatusStyle {
    let label: String
    let accent: Color
    let badgeBackground: Color
    let cardBackground: Color
    let cardBorder: Color

    static func from(status: SessionStatus) -> SessionStatusStyle {
        switch status {
        case .thinking:
            return SessionStatusStyle(
                label: "Responding",
                accent: .blue,
                badgeBackground: .blue.opacity(0.2),
                cardBackground: .blue.opacity(0.12),
                cardBorder: .blue.opacity(0.25)
            )
        case .processing:
            return SessionStatusStyle(
                label: "Processing",
                accent: .blue,
                badgeBackground: .blue.opacity(0.2),
                cardBackground: .blue.opacity(0.12),
                cardBorder: .blue.opacity(0.25)
            )
        case .waiting:
            return SessionStatusStyle(
                label: "Waiting",
                accent: .yellow,
                badgeBackground: .yellow.opacity(0.22),
                cardBackground: .yellow.opacity(0.10),
                cardBorder: .yellow.opacity(0.24)
            )
        case .idle:
            return SessionStatusStyle(
                label: "Idle",
                accent: .gray,
                badgeBackground: .gray.opacity(0.25),
                cardBackground: .gray.opacity(0.08),
                cardBorder: .gray.opacity(0.18)
            )
        case .stale:
            return SessionStatusStyle(
                label: "Stale",
                accent: .secondary,
                badgeBackground: .secondary.opacity(0.2),
                cardBackground: .secondary.opacity(0.06),
                cardBorder: .secondary.opacity(0.15)
            )
        }
    }
}

private struct RenameDialog: View {
    let title: String
    let originalName: String
    @Binding var value: String
    let hasCustomValue: Bool
    let onCancel: () -> Void
    let onReset: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            TextField("Name", text: $value)
                .textFieldStyle(.roundedBorder)

            Text("Original: \(originalName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", action: onCancel)
                    .focusable(false)
                    .pointerCursor()
                if hasCustomValue {
                    Button("Reset", role: .destructive, action: onReset)
                        .focusable(false)
                        .pointerCursor()
                }
                Spacer()
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .focusable(false)
                    .pointerCursor()
            }
        }
        .padding(18)
        .frame(minWidth: 340)
    }
}

private struct URLDialog: View {
    let title: String
    @Binding var value: String
    let hasCustomValue: Bool
    let onCancel: () -> Void
    let onClear: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            TextField("https://...", text: $value)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel", action: onCancel)
                    .focusable(false)
                    .pointerCursor()
                if hasCustomValue {
                    Button("Clear", role: .destructive, action: onClear)
                        .focusable(false)
                        .pointerCursor()
                }
                Spacer()
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .focusable(false)
                    .pointerCursor()
            }
        }
        .padding(18)
        .frame(minWidth: 340)
    }
}

private struct ProjectCommandDialog: View {
    let action: ProjectCommandAction
    @Binding var command: String
    let runAfterSave: Bool
    let projectName: String
    let onCancel: () -> Void
    let onSave: () -> Void

    private var title: String {
        action.dialogTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            TextField(action.placeholder, text: $command)
                .textFieldStyle(.roundedBorder)

            Text(
                runAfterSave
                    ? "Set and run this command for \(projectName)."
                    : "Edit this command for \(projectName)."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", action: onCancel)
                    .focusable(false)
                    .pointerCursor()
                Spacer()
                Button(runAfterSave ? "Save and Run" : "Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .focusable(false)
                    .pointerCursor()
            }
        }
        .padding(18)
        .frame(minWidth: 360)
    }
}

private struct StatBadge: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.2)))
            .foregroundStyle(tint)
    }
}

private extension UIElementSize {
    var projectHeaderTitleFont: Font {
        switch self {
        case .small:
            return .title3.weight(.semibold)
        case .medium:
            return .title2.weight(.semibold)
        case .large:
            return .title.weight(.semibold)
        case .extraLarge:
            return .largeTitle.weight(.semibold)
        }
    }

    var projectHeaderMetaFont: Font {
        switch self {
        case .small:
            return .footnote
        case .medium:
            return .body
        case .large:
            return .title3
        case .extraLarge:
            return .title2
        }
    }

    var projectHeaderMetaMonospacedFont: Font {
        switch self {
        case .small:
            return .system(.footnote, design: .monospaced)
        case .medium:
            return .system(.body, design: .monospaced)
        case .large:
            return .system(.title3, design: .monospaced)
        case .extraLarge:
            return .system(.title2, design: .monospaced)
        }
    }

    var sessionMetricsFont: Font {
        switch self {
        case .small:
            return .system(.subheadline, design: .monospaced)
        case .medium:
            return .system(.body, design: .monospaced)
        case .large:
            return .system(.title3, design: .monospaced)
        case .extraLarge:
            return .system(.title2, design: .monospaced)
        }
    }
}

private func truncatePath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path.hasPrefix(home) {
        return "~" + path.dropFirst(home.count)
    }
    return path
}

private func formatMemory(_ bytes: Int64) -> String {
    let mb = Double(bytes) / (1024 * 1024)
    if mb >= 1024 {
        return String(format: "%.1fG", mb / 1024)
    }
    return String(format: "%.0fM", mb)
}

private func formatTimeAgo(_ timestamp: String) -> String {
    guard let date = SessionParsingSupport.parseISODate(timestamp) else {
        return "unknown"
    }

    let delta = Int(Date().timeIntervalSince(date))
    if delta < 60 {
        return "just now"
    }

    let minutes = delta / 60
    if minutes < 60 {
        return "\(minutes)m ago"
    }

    let hours = minutes / 60
    if hours < 24 {
        return "\(hours)h ago"
    }

    let days = hours / 24
    return "\(days)d ago"
}

private extension Color {
    init?(hex: String) {
        let raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix("#"), raw.count == 7 else {
            return nil
        }

        let scanner = Scanner(string: String(raw.dropFirst()))
        var value: UInt64 = 0
        guard scanner.scanHexInt64(&value) else {
            return nil
        }

        let red = Double((value & 0xFF0000) >> 16) / 255.0
        let green = Double((value & 0x00FF00) >> 8) / 255.0
        let blue = Double(value & 0x0000FF) / 255.0

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
