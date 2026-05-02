import SwiftUI
import AppKit
import Combine
import CoreGraphics

private enum ViewerSide: String, Codable {
    case left
    case right
}

private enum ViewerScreenTarget: Equatable {
    case primary
    case builtIn
    case display(String)

    init(storageValue: String) {
        if storageValue == "primary" {
            self = .primary
            return
        }

        if storageValue == "builtin" {
            self = .builtIn
            return
        }

        if storageValue.hasPrefix("display:") {
            let identifier = String(storageValue.dropFirst("display:".count))
            if !identifier.isEmpty {
                self = .display(identifier)
                return
            }
        }

        self = .primary
    }
}

private enum UIElementSize: String, Codable {
    case small
    case medium
    case large

    var fontScale: CGFloat {
        switch self {
        case .small:
            return 1.0
        case .medium:
            return 1.30
        case .large:
            return 1.65
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
        }
    }

    var rightExpandedLeftShift: CGFloat {
        switch self {
        case .small:
            return 0 // 45
        case .medium:
            return 0 // 90
        case .large:
            return 0 // 150
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

private enum SessionDetailsSource: String, Codable {
    case processBased
    case vsmuxSessions
}

private enum MuxSessionSource: String, Codable {
    case vsmux
    case zmux

    var displayName: String {
        switch self {
        case .vsmux:
            return "vsmux"
        case .zmux:
            return "zmux"
        }
    }
}

private enum AgentType: String, Codable, Hashable {
    case claude
    case codex
    case gemini
    case opencode
    case t3
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
    let detailsSource: SessionDetailsSource
    let sessionID: String
    let vsmuxThreadID: String?
    let vsmuxWorkspaceID: String?
    let muxSource: MuxSessionSource?
}

private struct MiniViewerProject: Codable, Identifiable {
    let projectName: String
    let projectPath: String
    let projectIconDataUrl: String?
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
    let showOnActiveMonitor: Bool
    let pinnedScreenTarget: String
    let uiElementSize: UIElementSize
    let expandDelayMilliseconds: Int
    let makeWholeCardHoverable: Bool
    let collapseDelayMilliseconds: Int
    let isVisible: Bool
    let projects: [MiniViewerProject]
}

private struct MiniViewerVisibilityCommand: Codable {
    let command: String
    let isVisible: Bool
}

private struct MiniViewerAction: Encodable {
    let action: String
    let detailsSource: SessionDetailsSource
    let pid: UInt32
    let projectPath: String
    let projectName: String
    let sessionID: String
    let vsmuxWorkspaceID: String?
    let muxSource: MuxSessionSource?
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

private final class ProjectIconProvider {
    private var images: [String: NSImage] = [:]

    func image(for dataURL: String?) -> NSImage? {
        guard let dataURL else {
            return nil
        }

        if let cachedImage = images[dataURL] {
            return cachedImage
        }

        guard let commaIndex = dataURL.firstIndex(of: ",") else {
            return nil
        }

        let encodedData = String(dataURL[dataURL.index(after: commaIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let imageData = Data(base64Encoded: encodedData),
            let image = NSImage(data: imageData)
        else {
            return nil
        }

        images[dataURL] = image
        return image
    }
}

private final class ViewerModel: ObservableObject {
    private let detailFadeAnimation = Animation.easeInOut(duration: 0.16)
    private let geometryAnimation = Animation.easeInOut(duration: 0.14)
    private let detailFadeDuration: TimeInterval = 0.16
    private let geometryCollapseSafetyDelay: TimeInterval = 0.06

    @Published var side: ViewerSide = .right
    @Published var showOnActiveMonitor = false
    @Published var pinnedScreenTarget = "primary"
    @Published var uiElementSize: UIElementSize = .small
    @Published var expandDelayMilliseconds = 300
    @Published var makeWholeCardHoverable = false
    @Published var collapseDelayMilliseconds = 300
    @Published var isVisible = true
    @Published var projects: [MiniViewerProject] = []
    @Published var isExpanded = false
    @Published var showDetails = false
    private var isPointerInside = false
    private var expandTask: DispatchWorkItem?
    private var collapseTask: DispatchWorkItem?

    var sessions: [MiniViewerSession] {
        projects.flatMap(\.sessions)
    }

    var hasVisibleSessions: Bool {
        projects.contains { !$0.sessions.isEmpty }
    }

    func apply(payload: MiniViewerPayload) {
        side = payload.side
        showOnActiveMonitor = payload.showOnActiveMonitor
        pinnedScreenTarget = payload.pinnedScreenTarget
        uiElementSize = payload.uiElementSize
        expandDelayMilliseconds = max(0, payload.expandDelayMilliseconds)
        makeWholeCardHoverable = payload.makeWholeCardHoverable
        collapseDelayMilliseconds = max(0, payload.collapseDelayMilliseconds)
        isVisible = payload.isVisible
        projects = payload.projects
    }

    func setHovering(_ hovering: Bool) {
        if hovering == isPointerInside {
            return
        }

        isPointerInside = hovering
        expandTask?.cancel()
        collapseTask?.cancel()

        if hovering {
            let task = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.isPointerInside else { return }
                withAnimation(self.geometryAnimation) {
                    self.isExpanded = true
                }
                withAnimation(self.detailFadeAnimation) {
                    self.showDetails = true
                }
            }
            expandTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + expandDelay, execute: task)
            return
        }

        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.isPointerInside else { return }
            withAnimation(self.detailFadeAnimation) {
                self.showDetails = false
            }

            let collapseGeometryTask = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard !self.isPointerInside else { return }
                withAnimation(self.geometryAnimation) {
                    self.isExpanded = false
                }
            }
            self.collapseTask = collapseGeometryTask
            DispatchQueue.main.asyncAfter(
                deadline: .now() + self.detailFadeDuration + self.geometryCollapseSafetyDelay,
                execute: collapseGeometryTask
            )
        }
        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: task)
    }

    private var expandDelay: TimeInterval {
        TimeInterval(expandDelayMilliseconds) / 1000
    }

    private var collapseDelay: TimeInterval {
        TimeInterval(collapseDelayMilliseconds) / 1000
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

private struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: () -> Void

    final class RightClickPassthroughView: NSView {
        var onRightClick: () -> Void

        init(onRightClick: @escaping () -> Void) {
            self.onRightClick = onRightClick
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

            guard event.type == .rightMouseDown || event.type == .rightMouseUp else {
                return nil
            }

            return self
        }

        override func rightMouseDown(with event: NSEvent) {
            onRightClick()
        }
    }

    func makeNSView(context: Context) -> NSView {
        RightClickPassthroughView(onRightClick: onRightClick)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let passthroughView = nsView as? RightClickPassthroughView else {
            return
        }
        passthroughView.onRightClick = onRightClick
    }
}

private struct MiniViewerFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

private struct MiniViewerChromeScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

private struct SessionIconFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct MiniViewerContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
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

    func miniViewerPointerCursor() -> some View {
        modifier(MiniViewerPointerCursorModifier())
    }
}

private struct MiniViewerPointerCursorModifier: ViewModifier {
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

private struct SessionRowView: View {
    @Environment(\.miniViewerChromeScale) private var chromeScale
    private let activeOrange = Color(red: 252.0 / 255.0, green: 178.0 / 255.0, blue: 83.0 / 255.0)

    let session: MiniViewerSession
    let isExpanded: Bool
    let showDetails: Bool
    let showProjectName: Bool
    let keepFloatingIconVisibleWhenExpanded: Bool
    let swapAgentIconWithStatusIcon: Bool
    let agentImage: NSImage?
    let onActivate: () -> Void
    let onMiddleClick: () -> Void
    let onRightClick: () -> Void

    private var rowHeight: CGFloat {
        56 * chromeScale
    }

    private var trailingAgentIconSize: CGFloat {
        16.8 * chromeScale
    }

    private var statusIndicatorSize: CGFloat {
        20 * chromeScale
    }

    private var leadingIconSlotSize: CGFloat {
        34 * chromeScale
    }

    private var trailingIconSlotWidth: CGFloat {
        swapAgentIconWithStatusIcon ? statusIndicatorSize : trailingAgentIconSize
    }

    private var trailingIconOffsetX: CGFloat {
        -9
    }

    private var shouldSwapExpandedIcons: Bool {
        swapAgentIconWithStatusIcon && isExpanded
    }

    private var statusIndicatorOpacity: Double {
        if isExpanded {
            if keepFloatingIconVisibleWhenExpanded {
                return 1.0
            }
            return showDetails ? 1.0 : 0.0
        }

        return 0.2
    }

    private var isVSmuxSession: Bool {
        session.detailsSource == .vsmuxSessions
    }

    private var isNewSession: Bool {
        fullMessage == nil && (session.status == .waiting || session.status == .idle)
    }

    private var statusLabel: String {
        if isNewSession { return "New session" }
        switch session.status {
        case .waiting:
            return "Done"
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
        if isNewSession { return .gray }
        switch session.status {
        case .waiting:
            return .green.opacity(0.85)
        case .processing:
            return activeOrange
        case .thinking:
            return activeOrange
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

    private var statLine: String? {
        if isVSmuxSession {
            return nil
        }

        let memoryMB = Double(session.memoryBytes) / (1024.0 * 1024.0)
        let memoryText = memoryMB >= 1024 ? String(format: "%.1fG", memoryMB / 1024.0) : "\(Int(memoryMB.rounded()))M"
        return "\(Int(session.cpuUsage.rounded()))%  \(memoryText)"
    }

    private var messageLine: String {
        guard let fullMessage else {
            return "No messages sent yet"
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
        if trimmed.isEmpty || isNonDisplayableMessage(trimmed) {
            return nil
        }

        return trimmed
    }

    private func isNonDisplayableMessage(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered == "(no content)" ||
            lowered == "no content" ||
            lowered.hasPrefix("<local-command-caveat>") ||
            lowered.hasPrefix("<local-command-stdout") ||
            lowered.hasPrefix("<local-command-stderr") ||
            lowered.hasPrefix("<local-command-exit-code") ||
            lowered.hasPrefix("<command-name>") ||
            lowered.hasPrefix("<command-message>") ||
            lowered.hasPrefix("<command-args>")
    }

    private var loadingStatusIndicator: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .miniViewerFont(size: 14, weight: .bold)
            .foregroundStyle(activeOrange)
            .symbolEffect(.rotate, options: .speed(1.3), isActive: true)
    }

    @ViewBuilder
    private var largeStatusIndicator: some View {
        if isNewSession {
            Image(systemName: "plus")
                .miniViewerFont(size: 14, weight: .bold)
                .foregroundStyle(.secondary)
        } else if session.status == .waiting {
            Image(systemName: "circle.fill")
                .miniViewerFont(size: 14, weight: .bold)
                .foregroundStyle(.green)
        } else if session.status == .processing {
            loadingStatusIndicator
        } else if session.status == .thinking {
            loadingStatusIndicator
        } else {
            Image(systemName: "pause.fill")
                .miniViewerFont(size: 14, weight: .bold)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var agentIcon: some View {
        if let agentImage {
            if session.agentType == .codex {
                Image(nsImage: agentImage)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: trailingAgentIconSize, height: trailingAgentIconSize)
                    .foregroundStyle(.primary)
            } else {
                Image(nsImage: agentImage)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: trailingAgentIconSize, height: trailingAgentIconSize)
            }
        } else {
            Image(systemName: "cpu.fill")
                .miniViewerFont(size: 11, weight: .bold)
                .foregroundStyle(baseTint)
        }
    }

    private var statusIndicator: some View {
        largeStatusIndicator
            .frame(width: statusIndicatorSize, height: statusIndicatorSize)
    }

    var body: some View {
        Button(action: onActivate) {
            HStack(alignment: .center, spacing: 10 * chromeScale) {
                ZStack {
                    if shouldSwapExpandedIcons {
                        agentIcon
                    } else {
                        statusIndicator
                    }
                }
                .frame(width: leadingIconSlotSize, height: leadingIconSlotSize)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: SessionIconFramePreferenceKey.self,
                            value: [session.id: proxy.frame(in: .named("MiniViewerRoot"))]
                        )
                    }
                )
                .opacity(statusIndicatorOpacity)

                if showDetails {
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

                            if isVSmuxSession {
                                Text(lastActivityText)
                                    .miniViewerFont(size: 10, weight: .medium)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        HStack(spacing: 0) {
                            Text(messageLine)
                                .miniViewerFont(size: 10)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }

                        if !isVSmuxSession || session.activeSubagentCount > 0 {
                            HStack(spacing: 7 * chromeScale) {
                                if !isVSmuxSession {
                                    Text(lastActivityText)
                                }
                                if let statLine {
                                    Text(statLine)
                                }
                                if session.activeSubagentCount > 0 {
                                    Text("+\(session.activeSubagentCount) sub")
                                }
                            }
                            .miniViewerFont(size: 9, design: .monospaced)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    Group {
                        if shouldSwapExpandedIcons {
                            statusIndicator
                        } else {
                            agentIcon
                        }
                    }
                    .frame(width: trailingIconSlotWidth, height: rowHeight, alignment: .center)
                    .offset(x: trailingIconOffsetX)
                }
            }
            .contentShape(Rectangle())
        }
        .padding(.horizontal, (showDetails ? 8 : 7) * chromeScale)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 12 * chromeScale)
                .fill(.thinMaterial.opacity(0.8))
                .opacity(showDetails ? 1 : 0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12 * chromeScale)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .opacity(showDetails ? 1 : 0)
        )
        .overlay(MiddleClickCatcher(onMiddleClick: onMiddleClick))
        .overlay(RightClickCatcher(onRightClick: onRightClick))
        .buttonStyle(.plain)
        .focusable(false)
        .miniViewerPointerCursor()
        .animation(.easeInOut(duration: 0.16), value: showDetails)
        .animation(.easeInOut(duration: 0.14), value: isExpanded)
    }
}

private struct ProjectHeaderView: View {
    @Environment(\.miniViewerChromeScale) private var chromeScale

    let project: MiniViewerProject
    let isExpanded: Bool
    let showDetails: Bool
    let projectIcon: NSImage?
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

    private var fallbackFolderColor: Color {
        let hash = project.projectPath.utf8.reduce(UInt64(5381)) { partial, byte in
            ((partial << 5) &+ partial) &+ UInt64(byte)
        }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.28, brightness: 0.97)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
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
            .opacity(showDetails ? 1 : 0)

            Group {
                if let projectIcon {
                    Image(nsImage: projectIcon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Image(systemName: "folder.fill")
                        .miniViewerFont(size: 14, weight: .semibold)
                        .foregroundStyle(fallbackFolderColor)
                }
            }
            .frame(width: 20 * chromeScale, height: 20 * chromeScale)
            .offset(x: 7 * chromeScale, y: -5 * chromeScale)
            .opacity(isExpanded ? 0 : 0.5)
            .zIndex(1)
        }
        .padding(.horizontal, 8 * chromeScale)
        .zIndex(1)
    }
}

private struct MiniViewerRootView: View {
    @ObservedObject var model: ViewerModel
    let iconProvider: AgentIconProvider
    let projectIconProvider: ProjectIconProvider
    let onActivate: (MiniViewerSession) -> Void
    let onMiddleClick: (MiniViewerSession) -> Void
    let onRightClick: (MiniViewerSession) -> Void
    let onIconFramesChanged: ([String: CGRect]) -> Void
    let onContentHeightChanged: (CGFloat) -> Void

    private var chromeScale: CGFloat {
        model.uiElementSize.chromeScale
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8 * chromeScale) {
                ForEach(model.projects) { project in
                    VStack(alignment: .leading, spacing: 6 * chromeScale) {
                        ProjectHeaderView(
                            project: project,
                            isExpanded: model.isExpanded,
                            showDetails: model.showDetails,
                            projectIcon: projectIconProvider.image(for: project.projectIconDataUrl)
                        )
                        .animation(.easeInOut(duration: 0.16), value: model.showDetails)

                        ForEach(project.sessions) { session in
                            SessionRowView(
                                session: session,
                                isExpanded: model.isExpanded,
                                showDetails: model.showDetails,
                                showProjectName: false,
                                keepFloatingIconVisibleWhenExpanded: model.side == .left,
                                swapAgentIconWithStatusIcon: model.side == .right,
                                agentImage: iconProvider.image(for: session.agentType),
                                onActivate: { onActivate(session) },
                                onMiddleClick: { onMiddleClick(session) },
                                onRightClick: { onRightClick(session) }
                            )
                        }
                    }
                    .padding(.bottom, 2 * chromeScale)
                }
            }
            .padding(8 * chromeScale)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: MiniViewerContentHeightPreferenceKey.self,
                        value: proxy.size.height
                    )
                }
            )
        }
        .coordinateSpace(name: "MiniViewerRoot")
        .onPreferenceChange(SessionIconFramePreferenceKey.self) { frames in
            onIconFramesChanged(frames)
        }
        .onPreferenceChange(MiniViewerContentHeightPreferenceKey.self) { height in
            onContentHeightChanged(height)
        }
        .environment(\.miniViewerFontScale, model.uiElementSize.fontScale)
        .environment(\.miniViewerChromeScale, model.uiElementSize.chromeScale)
    }
}

final class MiniViewerAppDelegate: NSObject, NSApplicationDelegate {
    private let model = ViewerModel()
    private let iconProvider = AgentIconProvider()
    private let projectIconProvider = ProjectIconProvider()
    private var window: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var iconFrames: [String: CGRect] = [:]
    private var measuredContentHeight: CGFloat = 0
    private var screenParametersObserver: NSObjectProtocol?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

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
        startScreenParametersObserver()
        startInputReader()
        startHoverMonitor()
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopHoverMonitor()
        stopScreenParametersObserver()
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
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false

        panel.contentView = NSHostingView(
            rootView: MiniViewerRootView(
                model: model,
                iconProvider: iconProvider,
                projectIconProvider: projectIconProvider,
                onActivate: { [weak self] session in
                    self?.activateSession(session)
                },
                onMiddleClick: { [weak self] session in
                    self?.endSession(session)
                },
                onRightClick: { [weak self] session in
                    self?.openMainWindow(for: session)
                },
                onIconFramesChanged: { [weak self] frames in
                    self?.iconFrames = frames
                    self?.updateWindowFrame(animated: false)
                    self?.updateHoverStateFromPointer()
                },
                onContentHeightChanged: { [weak self] height in
                    self?.updateMeasuredContentHeight(height)
                }
            )
        )

        window = panel
        panel.alphaValue = 0
        updateWindowFrame(animated: false)
    }

    private func bindModel() {
        Publishers.CombineLatest4(model.$side, model.$isExpanded, model.$projects, model.$uiElementSize)
            .combineLatest(
                Publishers.CombineLatest3(
                    model.$isVisible,
                    model.$showOnActiveMonitor,
                    model.$pinnedScreenTarget
                )
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updateWindowFrame(animated: true)
            }
            .store(in: &cancellables)
    }

    private func startScreenParametersObserver() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateWindowFrame(animated: false)
        }
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

    private func resolvedHeight(for projects: [MiniViewerProject]) -> CGFloat {
        let fallbackHeight = desiredHeight(for: projects)
        guard measuredContentHeight > 0 else {
            return fallbackHeight
        }

        return max(measuredContentHeight, minHeight)
    }

    private func updateMeasuredContentHeight(_ height: CGFloat) {
        let normalizedHeight = max(height.rounded(.toNearestOrAwayFromZero), 0)
        guard abs(normalizedHeight - measuredContentHeight) > 0.5 else {
            return
        }

        measuredContentHeight = normalizedHeight
        updateWindowFrame(animated: false)
    }

    private func updateWindowFrame(animated: Bool) {
        guard let panel = window else { return }
        guard let screen = resolvedScreen() else { return }
        let screenFrame = screen.visibleFrame

        guard model.isVisible && model.hasVisibleSessions else {
            panel.ignoresMouseEvents = true
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }

        panel.ignoresMouseEvents = !model.isExpanded

        let width = model.isExpanded ? expandedWidth : collapsedWidth
        let height = resolvedHeight(for: model.projects)
        let baseX = model.side == .left ? screenFrame.minX : screenFrame.maxX - width
        let x: CGFloat
        if model.isExpanded, model.side == .right {
            x = baseX - model.uiElementSize.rightExpandedLeftShift
        } else {
            x = baseX
        }
        let centeredY = screenFrame.midY - (height / 2.0)
        let fallbackY = height <= screenFrame.height
            ? min(max(centeredY, screenFrame.minY), screenFrame.maxY - height)
            : centeredY
        let y = iconStackCenteredY(screenFrame: screenFrame) ?? fallbackY
        let frame = NSRect(x: x, y: y, width: width, height: height)

        // Avoid NSPanel frame animation jitter near screen edges while hovering quickly.
        panel.setFrame(frame, display: true, animate: false)
        panel.alphaValue = 1.0
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        updateHoverStateFromPointer()
    }

    private func iconStackCenteredY(screenFrame: NSRect) -> CGFloat? {
        guard let panel = window,
              let contentView = panel.contentView,
              !iconFrames.isEmpty else {
            return nil
        }

        let windowRects = iconFrames.values.map { iconFrame in
            contentView.convert(iconFrame, to: nil)
        }
        guard let firstRect = windowRects.first else {
            return nil
        }

        let iconStackRect = windowRects.dropFirst().reduce(firstRect) { partial, rect in
            partial.union(rect)
        }
        guard iconStackRect.height > 0 else {
            return nil
        }

        return screenFrame.midY - iconStackRect.midY
    }

    private func resolvedScreen() -> NSScreen? {
        if model.showOnActiveMonitor {
            return NSScreen.main ?? primaryScreen()
        }

        switch ViewerScreenTarget(storageValue: model.pinnedScreenTarget) {
        case .primary:
            return primaryScreen()
        case .builtIn:
            return builtInScreen() ?? primaryScreen()
        case let .display(identifier):
            return screen(matchingStableIdentifier: identifier) ?? primaryScreen()
        }
    }

    private func primaryScreen() -> NSScreen? {
        let mainDisplayID = CGMainDisplayID()
        return NSScreen.screens.first(where: { $0.agentManagerXDisplayID == mainDisplayID }) ?? NSScreen.screens.first
    }

    private func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let displayID = screen.agentManagerXDisplayID else {
                return false
            }
            return CGDisplayIsBuiltin(displayID) != 0
        }
    }

    private func screen(matchingStableIdentifier identifier: String) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let displayID = screen.agentManagerXDisplayID else {
                return false
            }
            return stableIdentifier(for: displayID) == identifier
        }
    }

    private func stableIdentifier(for displayID: CGDirectDisplayID) -> String {
        if let unmanaged = CGDisplayCreateUUIDFromDisplayID(displayID) {
            let uuid = unmanaged.takeRetainedValue()
            return (CFUUIDCreateString(nil, uuid) as String).uppercased()
        }

        return "display-\(displayID)"
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
        stopHoverMonitor()

        let eventMask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged
        ]

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateHoverStateFromPointer()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.updateHoverStateFromPointer()
            return event
        }

        updateHoverStateFromPointer()
    }

    private func stopHoverMonitor() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }

        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    private func stopScreenParametersObserver() {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }
    }

    private func updateHoverStateFromPointer() {
        guard model.isVisible && model.hasVisibleSessions else {
            model.setHovering(false)
            return
        }

        guard let panel = window else { return }
        guard let contentView = panel.contentView else { return }
        guard let screenFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }

        let pointer = NSEvent.mouseLocation
        let liveIconRects = iconFrames.values.map { iconFrame in
            let windowRect = contentView.convert(iconFrame, to: nil)
            return panel.convertToScreen(windowRect)
        }
        let liveHoverStripRect = hoverStripRect(for: liveIconRects)

        let rightCollapsedAnchorRects: [NSRect]
        let rightCollapsedHoverStripRect: NSRect?
        if model.side == .right && model.isExpanded {
            let collapsedPanelMinX = screenFrame.maxX - collapsedWidth
            let expandedPanelMinX = panel.frame.minX
            let anchorShiftX = collapsedPanelMinX - expandedPanelMinX
            rightCollapsedAnchorRects = liveIconRects.map { rect in
                rect.offsetBy(dx: anchorShiftX, dy: 0)
            }
            rightCollapsedHoverStripRect = liveHoverStripRect?.offsetBy(dx: anchorShiftX, dy: 0)
        } else {
            rightCollapsedAnchorRects = []
            rightCollapsedHoverStripRect = nil
        }

        let hoveringIcon = liveIconRects.contains(where: { $0.contains(pointer) }) ||
            rightCollapsedAnchorRects.contains(where: { $0.contains(pointer) }) ||
            liveHoverStripRect?.contains(pointer) == true ||
            rightCollapsedHoverStripRect?.contains(pointer) == true
        let expandedCardRects = expandedCardRects(for: liveIconRects, panelFrame: panel.frame)
        let hoveringExpandedCard = model.makeWholeCardHoverable &&
            model.isExpanded &&
            expandedCardRects.contains(where: { $0.contains(pointer) })
        model.setHovering(hoveringIcon || hoveringExpandedCard)
    }

    private func expandedCardRects(for iconRects: [NSRect], panelFrame: NSRect) -> [NSRect] {
        guard model.isExpanded else { return [] }

        let cardInset = 8 * chromeScale
        let cardWidth = max(panelFrame.width - (cardInset * 2), 0)

        return iconRects.map { rect in
            NSRect(
                x: panelFrame.minX + cardInset,
                y: rect.midY - (rowHeight / 2),
                width: cardWidth,
                height: rowHeight
            )
        }
    }

    private func hoverStripRect(for iconRects: [NSRect]) -> NSRect? {
        guard !iconRects.isEmpty else { return nil }

        let hoverWidth = 34 * chromeScale
        let hoverHeight = 34 * chromeScale

        let normalizedRects = iconRects.map { rect in
            NSRect(
                x: rect.midX - (hoverWidth / 2),
                y: rect.midY - (hoverHeight / 2),
                width: hoverWidth,
                height: hoverHeight
            )
        }

        let minX = normalizedRects.map(\.minX).min() ?? 0
        let maxX = normalizedRects.map(\.maxX).max() ?? 0
        let minY = normalizedRects.map(\.minY).min() ?? 0
        let maxY = normalizedRects.map(\.maxY).max() ?? 0

        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func activateSession(_ session: MiniViewerSession) {
        sendAction("focusSession", session: session)
    }

    private func endSession(_ session: MiniViewerSession) {
        sendAction("endSession", session: session)
    }

    private func openMainWindow(for session: MiniViewerSession) {
        sendAction("openMainWindow", session: session)
    }

    private func sendAction(_ actionName: String, session: MiniViewerSession) {
        let action = MiniViewerAction(
            action: actionName,
            detailsSource: session.detailsSource,
            pid: session.pid,
            projectPath: session.projectPath,
            projectName: session.projectName,
            sessionID: session.sessionID,
            vsmuxWorkspaceID: session.vsmuxWorkspaceID,
            muxSource: session.muxSource
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
        if let rawShowOnActiveMonitor = environment["MINI_VIEWER_SHOW_ON_ACTIVE_MONITOR"] {
            model.showOnActiveMonitor = rawShowOnActiveMonitor == "1"
        }
        if let rawPinnedScreenTarget = environment["MINI_VIEWER_PINNED_SCREEN_TARGET"],
           !rawPinnedScreenTarget.isEmpty {
            model.pinnedScreenTarget = rawPinnedScreenTarget
        }
        if let rawSize = environment["MINI_VIEWER_UI_ELEMENT_SIZE"],
           let initialSize = UIElementSize(rawValue: rawSize) {
            model.uiElementSize = initialSize
        }
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

let app = NSApplication.shared
let delegate = MiniViewerAppDelegate()
app.delegate = delegate
app.run()
