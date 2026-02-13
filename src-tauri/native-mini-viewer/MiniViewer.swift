import SwiftUI
import AppKit
import Combine

private enum ViewerSide: String, Codable {
    case left
    case right
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
    let projects: [MiniViewerProject]
}

private struct MiniViewerAction: Encodable {
    let action: String
    let pid: UInt32
    let projectPath: String
    let projectName: String
}

private final class AgentIconProvider {
    private var images: [AgentType: NSImage] = [:]

    init() {
        guard let iconDir = ProcessInfo.processInfo.environment["MINI_VIEWER_ICON_DIR"] else {
            return
        }

        let mappings: [(AgentType, String, String)] = [
            (.claude, "claude.svg", "claude.png"),
            (.codex, "codex.svg", "codex.png"),
            (.opencode, "opencode.svg", "opencode.png"),
        ]

        for (type, preferred, fallback) in mappings {
            let preferredPath = URL(fileURLWithPath: iconDir).appendingPathComponent(preferred).path
            if let image = NSImage(contentsOfFile: preferredPath) {
                images[type] = image
                continue
            }

            let fallbackPath = URL(fileURLWithPath: iconDir).appendingPathComponent(fallback).path
            if let image = NSImage(contentsOfFile: fallbackPath) {
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
    @Published var projects: [MiniViewerProject] = []
    @Published var isExpanded = false
    @Published var showDetails = false
    private var isPointerInside = false
    private var collapseTask: DispatchWorkItem?

    var sessions: [MiniViewerSession] {
        projects.flatMap(\.sessions)
    }

    func apply(payload: MiniViewerPayload) {
        side = payload.side
        projects = payload.projects
    }

    func setHovering(_ hovering: Bool) {
        if hovering == isPointerInside {
            return
        }

        isPointerInside = hovering
        collapseTask?.cancel()

        if hovering {
            showDetails = true
            withAnimation(.easeInOut(duration: 0.14)) {
                isExpanded = true
            }
            return
        }

        // Hide row details instantly on unhover to avoid lingering text during collapse.
        showDetails = false

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

    final class Coordinator: NSObject {
        var onMiddleClick: () -> Void

        init(onMiddleClick: @escaping () -> Void) {
            self.onMiddleClick = onMiddleClick
        }

        @objc func handleMiddleClick() {
            onMiddleClick()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onMiddleClick: onMiddleClick)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        let recognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMiddleClick)
        )
        recognizer.numberOfClicksRequired = 1
        recognizer.buttonMask = 0x4 // Middle mouse button
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onMiddleClick = onMiddleClick
    }
}

private struct SessionRowView: View {
    let session: MiniViewerSession
    let isExpanded: Bool
    let showDetails: Bool
    let showProjectName: Bool
    let agentImage: NSImage?
    let onActivate: () -> Void
    let onMiddleClick: () -> Void
    @State private var isLoadingSpinActive = false
    @State private var isMessageHovered = false
    @State private var isMessagePopoverHovered = false
    @State private var isMessagePopoverPresented = false
    @State private var hideMessagePopoverTask: DispatchWorkItem?

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

    private func scheduleMessagePopoverHide() {
        hideMessagePopoverTask?.cancel()
        let task = DispatchWorkItem {
            if !isMessageHovered && !isMessagePopoverHovered {
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
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.yellow)
        case .processing, .thinking:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14, weight: .bold))
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
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        Button(action: onActivate) {
            HStack(alignment: .center, spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    largeStatusIndicator
                        .frame(width: 20, height: 20)

                    if showDetails {
                        Group {
                            if let agentImage {
                                Image(nsImage: agentImage)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFit()
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "cpu.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(baseTint)
                            }
                        }
                        .offset(x: 6, y: 6)
                    }
                }
                .frame(width: 34, height: 34)
                .opacity(isExpanded ? 1.0 : 0.2)

                if showDetails {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if showProjectName {
                                Text(session.projectName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                            }

                            Text(statusLabel)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(baseTint.opacity(0.18), in: Capsule())
                        }

                        Text(messageLine)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .onHover { hovering in
                                guard fullMessage != nil else { return }
                                isMessageHovered = hovering
                                if hovering {
                                    showMessagePopover()
                                } else {
                                    scheduleMessagePopoverHide()
                                }
                            }
                            .popover(
                                isPresented: $isMessagePopoverPresented,
                                attachmentAnchor: .rect(.bounds),
                                arrowEdge: .top
                            ) {
                                ScrollView(.vertical, showsIndicators: true) {
                                    Text(fullMessage ?? "")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(14)
                                }
                                .frame(width: 420, height: 220)
                                .background(.ultraThinMaterial)
                                .onHover { hovering in
                                    isMessagePopoverHovered = hovering
                                    if hovering {
                                        hideMessagePopoverTask?.cancel()
                                    } else {
                                        scheduleMessagePopoverHide()
                                    }
                                }
                            }

                        HStack(spacing: 7) {
                            Text(lastActivityText)
                            Text(statLine)
                            if session.activeSubagentCount > 0 {
                                Text("+\(session.activeSubagentCount) sub")
                            }
                        }
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .background(isExpanded ? AnyView(
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial.opacity(0.8))
        ) : AnyView(EmptyView()))
        .overlay(isExpanded ? AnyView(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        ) : AnyView(EmptyView()))
        .overlay(MiddleClickCatcher(onMiddleClick: onMiddleClick))
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.16), value: isExpanded)
        .onChange(of: showDetails) { _, detailsVisible in
            if !detailsVisible {
                hideMessagePopoverTask?.cancel()
                isMessagePopoverPresented = false
                isMessageHovered = false
                isMessagePopoverHovered = false
            }
        }
    }
}

private struct ProjectHeaderView: View {
    let project: MiniViewerProject
    private let reservedHeaderHeight: CGFloat = 54

    private var displayPath: String {
        let homePath = NSHomeDirectory()
        if project.projectPath.hasPrefix(homePath) {
            return "~" + project.projectPath.dropFirst(homePath.count)
        }
        return project.projectPath
    }

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
        VStack(alignment: .leading, spacing: 3) {
            Text(project.projectName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            Text(displayPath)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 7) {
                if let branchName {
                    HStack(spacing: 3) {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.system(size: 9, weight: .medium))
                        Text(branchName)
                    }
                }

                if hasDiffStats {
                    HStack(spacing: 4) {
                        Text("+\(project.diffAdditions)")
                            .foregroundStyle(Color.green.opacity(0.9))
                        Text("-\(project.diffDeletions)")
                            .foregroundStyle(Color.red.opacity(0.9))
                    }
                }

                Text("\(project.sessions.count) \(project.sessions.count == 1 ? "session" : "sessions")")
            }
            .font(.system(size: 9, weight: .regular, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .frame(height: reservedHeaderHeight, alignment: .topLeading)
    }
}

private struct MiniViewerRootView: View {
    @ObservedObject var model: ViewerModel
    let iconProvider: AgentIconProvider
    let onActivate: (MiniViewerSession) -> Void
    let onMiddleClick: (MiniViewerSession) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                if model.projects.isEmpty {
                    Text("No active sessions")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                } else {
                    ForEach(model.projects) { project in
                        VStack(alignment: .leading, spacing: 6) {
                            ProjectHeaderView(project: project)

                            ForEach(project.sessions) { session in
                                SessionRowView(
                                    session: session,
                                    isExpanded: model.isExpanded,
                                    showDetails: model.showDetails,
                                    showProjectName: false,
                                    agentImage: iconProvider.image(for: session.agentType),
                                    onActivate: { onActivate(session) },
                                    onMiddleClick: { onMiddleClick(session) }
                                )
                            }
                        }
                        .padding(.bottom, 2)
                    }
                }
            }
            .padding(8)
        }
    }
}

final class MiniViewerAppDelegate: NSObject, NSApplicationDelegate {
    private let model = ViewerModel()
    private let iconProvider = AgentIconProvider()
    private var window: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var hoverTimer: Timer?
    private var hasPerformedInitialReveal = false

    private let collapsedWidth: CGFloat = 64
    private let expandedWidth: CGFloat = 360
    private let minHeight: CGFloat = 80
    private let rowHeight: CGFloat = 56
    private let projectHeaderHeight: CGFloat = 54
    private let projectStackSpacing: CGFloat = 6
    private let projectBottomPadding: CGFloat = 2
    private let rootPaddingTopBottom: CGFloat = 16
    private let rootProjectSpacing: CGFloat = 8

    func applicationDidFinishLaunching(_ notification: Notification) {
        createWindow()
        bindModel()
        startInputReader()
        startHoverMonitor()
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: false)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func createWindow() {
        let initialRect = NSRect(x: 0, y: 0, width: collapsedWidth, height: 220)
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
        panel.orderFrontRegardless()
        scheduleInitialRevealIfNeeded()
    }

    private func bindModel() {
        Publishers.CombineLatest3(model.$side, model.$isExpanded, model.$projects)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
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

            // Each project VStack uses spacing=6 between header and each session row.
            let interItemSpacing = CGFloat(sessionCount) * projectStackSpacing

            return partial + projectHeaderHeight + rowsHeight + interItemSpacing + projectBottomPadding
        }

        let betweenProjects = CGFloat(max(projects.count - 1, 0)) * rootProjectSpacing
        let total = rootPaddingTopBottom + betweenProjects + projectContentHeights
        return max(total, minHeight)
    }

    private func updateWindowFrame(animated: Bool) {
        guard let panel = window else { return }
        guard let screenFrame = NSScreen.main?.visibleFrame else { return }

        let width = model.isExpanded ? expandedWidth : collapsedWidth
        let height = desiredHeight(for: model.projects)
        let x = model.side == .left ? screenFrame.minX : screenFrame.maxX - width
        let y = screenFrame.midY - (height / 2.0)
        let frame = NSRect(x: x, y: y, width: width, height: height)

        // Avoid NSPanel frame animation jitter near screen edges while hovering quickly.
        panel.setFrame(frame, display: true, animate: false)
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

    private func scheduleInitialRevealIfNeeded() {
        guard !hasPerformedInitialReveal else { return }
        hasPerformedInitialReveal = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let panel = self?.window else { return }
            panel.alphaValue = 1.0
        }
    }
}

let app = NSApplication.shared
let delegate = MiniViewerAppDelegate()
app.delegate = delegate
app.run()
