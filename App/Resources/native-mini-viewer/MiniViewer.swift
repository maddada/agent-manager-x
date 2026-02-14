import SwiftUI
import AppKit
import Combine

private enum ViewerSide: String, Codable {
    case left
    case right
}

private enum UIElementSize: String, Codable {
    case small
    case medium
    case large
    case extraLarge

    var fontScale: CGFloat {
        switch self {
        case .small:
            return 1.0
        case .medium:
            return 1.30
        case .large:
            return 1.65
        case .extraLarge:
            return 2.0
        }
    }

    var chromeScale: CGFloat {
        switch self {
        case .small:
            return 1.0
        case .medium:
            return 1.18
        case .large:
            return 1.38
        case .extraLarge:
            return 1.62
        }
    }
}

private enum SessionStatus: String, Codable {
    case waiting
    case processing
    case thinking
    case idle
    case stale
}

private enum AgentType: String, Codable, Hashable {
    case claude
    case codex
    case opencode
}

private struct MiniViewerSession: Codable, Identifiable {
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
}

private struct MiniViewerProject: Codable, Identifiable {
    let projectName: String
    let projectPath: String
    let gitBranch: String?
    let diffAdditions: UInt64
    let diffDeletions: UInt64
    let sessions: [MiniViewerSession]

    var id: String {
        projectPath
    }
}

private struct MiniViewerPayload: Codable {
    let side: ViewerSide
    let uiElementSize: UIElementSize
    let isVisible: Bool
    let projects: [MiniViewerProject]
}

private struct MiniViewerVisibilityCommand: Codable {
    let command: String
    let isVisible: Bool
}

private struct MiniViewerAction: Encodable {
    let action: String
    let pid: UInt32
    let projectPath: String
    let projectName: String
}

private struct BottomRoundedRectangle: Shape {
    var radius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let clampedRadius = min(radius, min(rect.width, rect.height) / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + clampedRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + clampedRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - clampedRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + clampedRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

private final class AgentIconProvider {
    private var images: [AgentType: NSImage] = [:]

    init() {
        guard let iconDir = ProcessInfo.processInfo.environment["MINI_VIEWER_ICON_DIR"] else {
            return
        }

        let mappings: [(AgentType, String)] = [
            (.claude, "claude.svg"),
            (.codex, "codex.svg"),
            (.opencode, "opencode.svg"),
        ]

        for (type, fileName) in mappings {
            let path = URL(fileURLWithPath: iconDir).appendingPathComponent(fileName).path
            if let image = NSImage(contentsOfFile: path) {
                images[type] = image
            }
        }
    }

    func image(for type: AgentType) -> NSImage? {
        images[type]
    }
}

private final class ViewerModel: ObservableObject {
    @Published var side: ViewerSide = .right
    @Published var uiElementSize: UIElementSize = .small
    @Published var isVisible = true
    @Published var projects: [MiniViewerProject] = []
    @Published var isExpanded = false
    @Published var showDetails = false
    private var isPointerInside = false
    private var collapseTask: DispatchWorkItem?

    var sessions: [MiniViewerSession] {
        projects.flatMap(\.sessions)
    }

    var hasVisibleSessions: Bool {
        projects.contains { !$0.sessions.isEmpty }
    }

    func apply(payload: MiniViewerPayload) {
        side = payload.side
        uiElementSize = payload.uiElementSize
        isVisible = payload.isVisible
        projects = payload.projects
    }

    func setHovering(_ hovering: Bool) {
        if hovering == isPointerInside {
            return
        }

        isPointerInside = hovering
        collapseTask?.cancel()

        if hovering {
            withAnimation(.easeInOut(duration: 0.16)) {
                showDetails = true
            }
            withAnimation(.easeInOut(duration: 0.14)) {
                isExpanded = true
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.12)) {
            showDetails = false
        }

        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.isPointerInside else { return }
            withAnimation(.easeInOut(duration: 0.14)) {
                self.isExpanded = false
            }
        }
        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: task)
    }
}

private struct MiddleClickCatcher: NSViewRepresentable {
    let onMiddleClick: () -> Void

    final class MiddleClickPassthroughView: NSView {
        var onMiddleClick: () -> Void

        init(onMiddleClick: @escaping () -> Void) {
            self.onMiddleClick = onMiddleClick
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            return nil
        }

        override var isOpaque: Bool {
            false
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = window?.currentEvent else {
                return nil
            }

            guard event.type == .otherMouseDown || event.type == .otherMouseUp else {
                return nil
            }

            return event.buttonNumber == 2 ? self : nil
        }

        override func otherMouseDown(with event: NSEvent) {
            guard event.buttonNumber == 2 else {
                super.otherMouseDown(with: event)
                return
            }

            onMiddleClick()
        }
    }

    func makeNSView(context: Context) -> NSView {
        MiddleClickPassthroughView(onMiddleClick: onMiddleClick)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let passthroughView = nsView as? MiddleClickPassthroughView else {
            return
        }
        passthroughView.onMiddleClick = onMiddleClick
    }
}

private struct MiniViewerFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

private struct MiniViewerChromeScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

private extension EnvironmentValues {
    var miniViewerFontScale: CGFloat {
        get { self[MiniViewerFontScaleKey.self] }
        set { self[MiniViewerFontScaleKey.self] = newValue }
    }

    var miniViewerChromeScale: CGFloat {
        get { self[MiniViewerChromeScaleKey.self] }
        set { self[MiniViewerChromeScaleKey.self] = newValue }
    }
}

private struct MiniViewerScaledFontModifier: ViewModifier {
    @Environment(\.miniViewerFontScale) private var fontScale

    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * fontScale, weight: weight, design: design))
    }
}

private extension View {
    func miniViewerFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(MiniViewerScaledFontModifier(size: size, weight: weight, design: design))
    }
}

private struct SessionRowView: View {
    @Environment(\.miniViewerChromeScale) private var chromeScale

    let session: MiniViewerSession
    let isExpanded: Bool
    let showDetails: Bool
    let showProjectName: Bool
    let showPopoverAbove: Bool
    let agentImage: NSImage?
    let onActivate: () -> Void
    let onMiddleClick: () -> Void
    let onPopoverVisibilityChanged: (Bool) -> Void
    @State private var isLoadingSpinActive = false
    @State private var isRowHovered = false
    @State private var isMessagePopoverHovered = false
    @State private var isMessagePopoverPresented = false
    @State private var showMessagePopoverTask: DispatchWorkItem?
    @State private var hideMessagePopoverTask: DispatchWorkItem?

    private var messagePopoverWidth: CGFloat {
        320 * chromeScale
    }

    private var messagePopoverHeight: CGFloat {
        180 * chromeScale
    }

    private var popoverYOffset: CGFloat {
        if showPopoverAbove {
            return -(messagePopoverHeight + (10 * chromeScale))
        }
        return 44 * chromeScale
    }

    private var rowHeight: CGFloat {
        56 * chromeScale
    }

    private var statusLabel: String {
        switch session.status {
        case .waiting:
            return "Waiting"
        case .processing:
            return "Processing"
        case .thinking:
            return "Thinking"
        case .idle:
            return "Idle"
        case .stale:
            return "Stale"
        }
    }

    private var baseTint: Color {
        switch session.status {
        case .waiting:
            return .blue.opacity(0.6)
        case .processing:
            return .blue
        case .thinking:
            return .indigo
        case .idle:
            return .gray
        case .stale:
            return .gray.opacity(0.7)
        }
    }

    private var lastActivityText: String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackParser = ISO8601DateFormatter()
        fallbackParser.formatOptions = [.withInternetDateTime]

        let date = parser.date(from: session.lastActivityAt) ?? fallbackParser.date(from: session.lastActivityAt)
        guard let date else {
            return "recent"
        }

        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return "now" }
        if diff < 3600 { return "\(diff / 60)m" }
        if diff < 86400 { return "\(diff / 3600)h" }
        return "\(diff / 86400)d"
    }

    private var statLine: String {
        let memoryMB = Double(session.memoryBytes) / (1024.0 * 1024.0)
        let memoryText = memoryMB >= 1024 ? String(format: "%.1fG", memoryMB / 1024.0) : "\(Int(memoryMB.rounded()))M"
        return "PID \(session.pid)  \(Int(session.cpuUsage.rounded()))%  \(memoryText)"
    }

    private var messageLine: String {
        guard let fullMessage else {
            return "No recent message"
        }

        // Normalize multi-line content so stale sessions with newline-prefixed messages
        // still render a visible first line in the collapsed text line.
        return fullMessage
            .components(separatedBy: .newlines)
            .joined(separator: " ")
    }

    private var fullMessage: String? {
        guard let lastMessage = session.lastMessage else {
            return nil
        }

        let trimmed = lastMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }

        return trimmed
    }

    private func showMessagePopover() {
        hideMessagePopoverTask?.cancel()
        guard showDetails, fullMessage != nil else {
            return
        }
        isMessagePopoverPresented = true
    }

    private func scheduleMessagePopoverShow() {
        showMessagePopoverTask?.cancel()
        guard showDetails, fullMessage != nil else {
            return
        }

        let task = DispatchWorkItem {
            if isRowHovered {
                showMessagePopover()
            }
        }
        showMessagePopoverTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: task)
    }

    private func scheduleMessagePopoverHide() {
        hideMessagePopoverTask?.cancel()
        let task = DispatchWorkItem {
            if !isRowHovered && !isMessagePopoverHovered {
                isMessagePopoverPresented = false
            }
        }
        hideMessagePopoverTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: task)
    }

    @ViewBuilder
    private var largeStatusIndicator: some View {
        switch session.status {
        case .waiting:
            Image(systemName: "exclamationmark.triangle.fill")
                .miniViewerFont(size: 14, weight: .bold)
                .foregroundStyle(.yellow)
        case .processing, .thinking:
            Image(systemName: "arrow.triangle.2.circlepath")
                .miniViewerFont(size: 14, weight: .bold)
                .foregroundStyle(.blue)
                .rotationEffect(.degrees(isLoadingSpinActive ? 360 : 0))
                .animation(
                    .linear(duration: 0.8).repeatForever(autoreverses: false),
                    value: isLoadingSpinActive
                )
                .onAppear {
                    isLoadingSpinActive = true
                }
                .onDisappear {
                    isLoadingSpinActive = false
                }
        case .idle, .stale:
            Image(systemName: "pause.fill")
                .miniViewerFont(size: 14, weight: .bold)
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        Button(action: onActivate) {
            HStack(alignment: .center, spacing: 10 * chromeScale) {
                ZStack(alignment: .bottomTrailing) {
                    largeStatusIndicator
                        .frame(width: 20 * chromeScale, height: 20 * chromeScale)

                    if showDetails {
                        Group {
                            if let agentImage {
                                Group {
                                    if session.agentType == .codex {
                                        Image(nsImage: agentImage)
                                            .renderingMode(.template)
                                            .resizable()
                                            .interpolation(.high)
                                            .scaledToFit()
                                            .frame(width: 12 * chromeScale, height: 12 * chromeScale)
                                            .foregroundStyle(.primary)
                                    } else {
                                        Image(nsImage: agentImage)
                                            .renderingMode(.original)
                                            .resizable()
                                            .interpolation(.high)
                                            .scaledToFit()
                                            .frame(width: 12 * chromeScale, height: 12 * chromeScale)
                                    }
                                }
                            } else {
                                Image(systemName: "cpu.fill")
                                    .miniViewerFont(size: 8, weight: .bold)
                                    .foregroundStyle(baseTint)
                            }
                        }
                        .offset(x: 6 * chromeScale, y: 6 * chromeScale)
                    }
                }
                .frame(width: 34 * chromeScale, height: 34 * chromeScale)
                .opacity(isExpanded ? 1.0 : 0.2)

                VStack(alignment: .leading, spacing: 3 * chromeScale) {
                    HStack(spacing: 6 * chromeScale) {
                        if showProjectName {
                            Text(session.projectName)
                                .miniViewerFont(size: 12, weight: .semibold)
                                .lineLimit(1)
                        }

                        Text(statusLabel)
                            .miniViewerFont(size: 10, weight: .medium)
                            .padding(.horizontal, 6 * chromeScale)
                            .padding(.vertical, 2 * chromeScale)
                            .background(baseTint.opacity(0.18), in: Capsule())
                    }

                    HStack(spacing: 0) {
                        Text(messageLine)
                            .miniViewerFont(size: 10)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())

                    HStack(spacing: 7 * chromeScale) {
                        Text(lastActivityText)
                        Text(statLine)
                        if session.activeSubagentCount > 0 {
                            Text("+\(session.activeSubagentCount) sub")
                        }
                    }
                    .miniViewerFont(size: 9, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .opacity(showDetails ? 1 : 0)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 8 * chromeScale)
        .frame(height: rowHeight)
        .background(isExpanded ? AnyView(
            RoundedRectangle(cornerRadius: 12 * chromeScale)
                .fill(.thinMaterial.opacity(0.8))
        ) : AnyView(EmptyView()))
        .overlay(isExpanded ? AnyView(
            RoundedRectangle(cornerRadius: 12 * chromeScale)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        ) : AnyView(EmptyView()))
        .overlay(MiddleClickCatcher(onMiddleClick: onMiddleClick))
        .buttonStyle(.plain)
        .focusable(false)
        .zIndex(isMessagePopoverPresented ? 200 : 0)
        .onHover { hovering in
            isRowHovered = hovering
            if hovering {
                scheduleMessagePopoverShow()
            } else {
                showMessagePopoverTask?.cancel()
                scheduleMessagePopoverHide()
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isExpanded)
        .overlay(alignment: .top) {
            if showDetails, isMessagePopoverPresented, let fullMessage {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(fullMessage)
                        .miniViewerFont(size: 13)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14 * chromeScale)
                }
                .frame(width: messagePopoverWidth, height: messagePopoverHeight)
                .background(
                    RoundedRectangle(cornerRadius: 12 * chromeScale, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .offset(y: popoverYOffset)
                .zIndex(5000)
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
        .onChange(of: showDetails) { _, detailsVisible in
            if !detailsVisible {
                showMessagePopoverTask?.cancel()
                hideMessagePopoverTask?.cancel()
                isMessagePopoverPresented = false
                isRowHovered = false
                isMessagePopoverHovered = false
            }
        }
        .onChange(of: isMessagePopoverPresented) { _, presented in
            onPopoverVisibilityChanged(presented)
        }
        .onDisappear {
            showMessagePopoverTask?.cancel()
            hideMessagePopoverTask?.cancel()
            isMessagePopoverPresented = false
            isRowHovered = false
            isMessagePopoverHovered = false
        }
    }
}

private struct ProjectHeaderView: View {
    @Environment(\.miniViewerChromeScale) private var chromeScale

    let project: MiniViewerProject
    private let headerFill = Color(red: 0.11, green: 0.13, blue: 0.16).opacity(0.85)

    private var branchName: String? {
        guard let gitBranch = project.gitBranch else {
            return nil
        }
        let trimmed = gitBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var hasDiffStats: Bool {
        project.diffAdditions > 0 || project.diffDeletions > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3 * chromeScale) {
            HStack(spacing: 8 * chromeScale) {
                HStack(spacing: 4 * chromeScale) {
                    Text(project.projectName)
                        .miniViewerFont(size: 12, weight: .semibold)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("(\(project.sessions.count))")
                        .miniViewerFont(size: 12, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6 * chromeScale)

                HStack(spacing: 7 * chromeScale) {
                    if let branchName {
                        HStack(spacing: 3 * chromeScale) {
                            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                                .miniViewerFont(size: 9, weight: .medium)
                            Text(branchName)
                        }
                    }

                    if hasDiffStats {
                        HStack(spacing: 4 * chromeScale) {
                            Text("+\(project.diffAdditions)")
                                .foregroundStyle(Color.green.opacity(0.9))
                            Text("-\(project.diffDeletions)")
                                .foregroundStyle(Color.red.opacity(0.9))
                        }
                    }
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .miniViewerFont(size: 9, design: .monospaced)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10 * chromeScale)
        .padding(.top, 6 * chromeScale)
        .padding(.bottom, 5 * chromeScale)
        .background(
            BottomRoundedRectangle(radius: 11 * chromeScale)
                .fill(headerFill)
        )
        .overlay(
            BottomRoundedRectangle(radius: 11 * chromeScale)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
        .padding(.horizontal, 8 * chromeScale)
    }
}

private struct MiniViewerRootView: View {
    @ObservedObject var model: ViewerModel
    let iconProvider: AgentIconProvider
    let onActivate: (MiniViewerSession) -> Void
    let onMiddleClick: (MiniViewerSession) -> Void
    @State private var activePopoverSessionID: String?

    private var chromeScale: CGFloat {
        model.uiElementSize.chromeScale
    }

    private var popoverAboveSessionIDs: Set<String> {
        Set(model.projects.flatMap(\.sessions).suffix(2).map(\.id))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8 * chromeScale) {
                ForEach(model.projects) { project in
                    let projectHasActivePopover = activePopoverSessionID != nil
                        && project.sessions.contains(where: { $0.id == activePopoverSessionID })
                    VStack(alignment: .leading, spacing: 6 * chromeScale) {
                        ProjectHeaderView(project: project)
                            .opacity(model.showDetails ? 1 : 0)
                            .animation(.easeInOut(duration: 0.16), value: model.showDetails)

                        ForEach(project.sessions) { session in
                            SessionRowView(
                                session: session,
                                isExpanded: model.isExpanded,
                                showDetails: model.showDetails,
                                showProjectName: false,
                                showPopoverAbove: popoverAboveSessionIDs.contains(session.id),
                                agentImage: iconProvider.image(for: session.agentType),
                                onActivate: { onActivate(session) },
                                onMiddleClick: { onMiddleClick(session) },
                                onPopoverVisibilityChanged: { presented in
                                    if presented {
                                        activePopoverSessionID = session.id
                                    } else if activePopoverSessionID == session.id {
                                        activePopoverSessionID = nil
                                    }
                                }
                            )
                        }
                    }
                    .padding(.bottom, 2 * chromeScale)
                    .zIndex(projectHasActivePopover ? 1000 : 0)
                }
            }
            .padding(8 * chromeScale)
        }
        .environment(\.miniViewerFontScale, model.uiElementSize.fontScale)
        .environment(\.miniViewerChromeScale, model.uiElementSize.chromeScale)
    }
}

final class MiniViewerAppDelegate: NSObject, NSApplicationDelegate {
    private let model = ViewerModel()
    private let iconProvider = AgentIconProvider()
    private var window: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var hoverTimer: Timer?

    private var chromeScale: CGFloat { model.uiElementSize.chromeScale }
    private var collapsedWidth: CGFloat { 64 * chromeScale }
    private var expandedWidth: CGFloat { 360 * chromeScale }
    private var minHeight: CGFloat { 80 * chromeScale }
    private var rowHeight: CGFloat { 56 * chromeScale }
    private var projectHeaderHeight: CGFloat { 54 * chromeScale }
    private var projectStackSpacing: CGFloat { 6 * chromeScale }
    private var projectBottomPadding: CGFloat { 2 * chromeScale }
    private var rootPaddingTopBottom: CGFloat { 16 * chromeScale }
    private var rootProjectSpacing: CGFloat { 8 * chromeScale }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyInitialConfigurationFromEnvironment()
        createWindow()
        bindModel()
        startInputReader()
        startHoverMonitor()
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: false)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func createWindow() {
        let initialRect = NSRect(x: 0, y: 0, width: collapsedWidth, height: 220 * chromeScale)
        let panel = NSPanel(
            contentRect: initialRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false

        panel.contentView = NSHostingView(
            rootView: MiniViewerRootView(
                model: model,
                iconProvider: iconProvider,
                onActivate: { [weak self] session in
                    self?.activateSession(session)
                },
                onMiddleClick: { [weak self] session in
                    self?.endSession(session)
                }
            )
        )

        window = panel
        panel.alphaValue = 0
        updateWindowFrame(animated: false)
    }

    private func bindModel() {
        Publishers.CombineLatest4(model.$side, model.$isExpanded, model.$projects, model.$uiElementSize)
            .combineLatest(model.$isVisible)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updateWindowFrame(animated: true)
            }
            .store(in: &cancellables)
    }

    private func desiredHeight(for projects: [MiniViewerProject]) -> CGFloat {
        guard !projects.isEmpty else {
            return minHeight
        }

        let projectContentHeights = projects.reduce(CGFloat(0)) { partial, project in
            let sessionCount = max(project.sessions.count, 0)
            let rowsHeight = CGFloat(sessionCount) * rowHeight
            let headerHeight = projectHeaderHeight
            let itemCount = sessionCount + 1
            let interItemSpacing = CGFloat(max(itemCount - 1, 0)) * projectStackSpacing

            return partial + headerHeight + rowsHeight + interItemSpacing + projectBottomPadding
        }

        let betweenProjects = CGFloat(max(projects.count - 1, 0)) * rootProjectSpacing
        let total = rootPaddingTopBottom + betweenProjects + projectContentHeights
        return max(total, minHeight)
    }

    private func updateWindowFrame(animated: Bool) {
        guard let panel = window else { return }
        guard let screenFrame = NSScreen.main?.visibleFrame else { return }

        guard model.isVisible && model.hasVisibleSessions else {
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }

        let width = model.isExpanded ? expandedWidth : collapsedWidth
        let height = desiredHeight(for: model.projects)
        let x = model.side == .left ? screenFrame.minX : screenFrame.maxX - width
        let centeredY = screenFrame.midY - (height / 2.0)
        let y: CGFloat
        if height <= screenFrame.height {
            y = min(max(centeredY, screenFrame.minY), screenFrame.maxY - height)
        } else {
            y = screenFrame.minY
        }
        let frame = NSRect(x: x, y: y, width: width, height: height)

        // Avoid NSPanel frame animation jitter near screen edges while hovering quickly.
        panel.setFrame(frame, display: true, animate: false)
        panel.alphaValue = 1.0
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func startInputReader() {
        var buffer = Data()
        let decoder = JSONDecoder()
        let handle = FileHandle.standardInput

        handle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
                return
            }

            buffer.append(chunk)

            while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
                buffer.removeSubrange(0...newlineRange.lowerBound)

                guard !lineData.isEmpty else {
                    continue
                }

                if let visibility = try? decoder.decode(MiniViewerVisibilityCommand.self, from: lineData),
                   visibility.command == "setVisibility" {
                    DispatchQueue.main.async {
                        self?.model.isVisible = visibility.isVisible
                    }
                    continue
                }

                do {
                    let payload = try decoder.decode(MiniViewerPayload.self, from: lineData)
                    DispatchQueue.main.async {
                        self?.model.apply(payload: payload)
                    }
                } catch {
                    continue
                }
            }
        }
    }

    private func startHoverMonitor() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            self?.updateHoverStateFromPointer()
        }
        if let hoverTimer {
            RunLoop.main.add(hoverTimer, forMode: .common)
        }
    }

    private func updateHoverStateFromPointer() {
        guard let panel = window else { return }
        guard let screenFrame = NSScreen.main?.visibleFrame else { return }

        let pointer = NSEvent.mouseLocation
        let frame = panel.frame
        let withinVerticalRange = pointer.y >= frame.minY - 10 && pointer.y <= frame.maxY + 10
        if !withinVerticalRange {
            model.setHovering(false)
            return
        }

        let edgeTriggerWidth: CGFloat = 10
        let stickyBounds = frame.insetBy(dx: -10, dy: -10)
        let edgeTriggered: Bool = {
            switch model.side {
            case .left:
                return pointer.x <= screenFrame.minX + edgeTriggerWidth
            case .right:
                return pointer.x >= screenFrame.maxX - edgeTriggerWidth
            }
        }()

        if model.isExpanded {
            model.setHovering(stickyBounds.contains(pointer) || edgeTriggered)
        } else {
            model.setHovering(edgeTriggered)
        }
    }

    private func activateSession(_ session: MiniViewerSession) {
        sendAction("focusSession", session: session)
    }

    private func endSession(_ session: MiniViewerSession) {
        sendAction("endSession", session: session)
    }

    private func sendAction(_ actionName: String, session: MiniViewerSession) {
        let action = MiniViewerAction(
            action: actionName,
            pid: session.pid,
            projectPath: session.projectPath,
            projectName: session.projectName
        )

        guard let data = try? JSONEncoder().encode(action) else {
            return
        }

        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }

    private func applyInitialConfigurationFromEnvironment() {
        let environment = ProcessInfo.processInfo.environment
        if let rawSide = environment["MINI_VIEWER_SIDE"],
           let initialSide = ViewerSide(rawValue: rawSide) {
            model.side = initialSide
        }
        if let rawSize = environment["MINI_VIEWER_UI_ELEMENT_SIZE"],
           let initialSize = UIElementSize(rawValue: rawSize) {
            model.uiElementSize = initialSize
        }
    }
}

let app = NSApplication.shared
let delegate = MiniViewerAppDelegate()
app.delegate = delegate
app.run()
