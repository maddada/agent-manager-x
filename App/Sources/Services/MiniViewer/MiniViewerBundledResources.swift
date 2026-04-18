import Foundation

enum MiniViewerBundledResources {
    static let source = #"""
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
    let agentImage: NSImage?
    let onActivate: () -> Void
    let onMiddleClick: () -> Void
    let onRightClick: () -> Void
    @State private var isLoadingSpinActive = false

    private var rowHeight: CGFloat {
        56 * chromeScale
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

    private var statLine: String {
        if isVSmuxSession {
            let threadText: String?
            if let threadID = session.vsmuxThreadID,
               !threadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                threadText = "thread \(String(threadID.prefix(8)))"
            } else {
                threadText = nil
            }

            if let threadText {
                return "VSmux session • \(threadText)"
            }

            return "VSmux session"
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
            Image(systemName: "arrow.triangle.2.circlepath")
                .miniViewerFont(size: 14, weight: .bold)
                .foregroundStyle(activeOrange)
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
        } else if session.status == .thinking {
            Image(systemName: "arrow.triangle.2.circlepath")
                .miniViewerFont(size: 14, weight: .bold)
                .foregroundStyle(activeOrange)
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
        } else {
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
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: SessionIconFramePreferenceKey.self,
                                    value: [session.id: proxy.frame(in: .named("MiniViewerRoot"))]
                                )
                            }
                        )

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
                    .opacity(showDetails ? 1 : 0)
                }
                .frame(width: 34 * chromeScale, height: 34 * chromeScale)
                .opacity(statusIndicatorOpacity)

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

                    HStack(spacing: 7 * chromeScale) {
                        if !isVSmuxSession {
                            Text(lastActivityText)
                        }
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
    let onRightClick: (MiniViewerSession) -> Void
    let onIconFramesChanged: ([String: CGRect]) -> Void

    private var chromeScale: CGFloat {
        model.uiElementSize.chromeScale
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8 * chromeScale) {
                ForEach(model.projects) { project in
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
                                keepFloatingIconVisibleWhenExpanded: model.side == .left,
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
        }
        .coordinateSpace(name: "MiniViewerRoot")
        .onPreferenceChange(SessionIconFramePreferenceKey.self) { frames in
            onIconFramesChanged(frames)
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
    private var iconFrames: [String: CGRect] = [:]
    private var screenParametersObserver: NSObjectProtocol?

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
        let height = desiredHeight(for: model.projects)
        let baseX = model.side == .left ? screenFrame.minX : screenFrame.maxX - width
        let x: CGFloat
        if model.isExpanded, model.side == .right {
            x = baseX - model.uiElementSize.rightExpandedLeftShift
        } else {
            x = baseX
        }
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
        let hoveringExpandedCard = model.makeWholeCardHoverable && model.isExpanded && panel.frame.contains(pointer)
        model.setHovering(hoveringIcon || hoveringExpandedCard)
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
            vsmuxWorkspaceID: session.vsmuxWorkspaceID
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
"""#

    static let icons: [String: String] = [
        "claude.svg": #"""
<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'><path fill='#d97757' d='m3.127 10.604 3.135-1.76.053-.153-.053-.085H6.11l-.525-.032-1.791-.048-1.554-.065-1.505-.08-.38-.081L0 7.832l.036-.234.32-.214.455.04 1.009.069 1.513.105 1.097.064 1.626.17h.259l.036-.105-.089-.065-.068-.064-1.566-1.062-1.695-1.121-.887-.646-.48-.327-.243-.306-.104-.67.435-.48.585.04.15.04.593.456 1.267.981 1.654 1.218.242.202.097-.068.012-.049-.109-.181-.9-1.626-.96-1.655-.428-.686-.113-.411a2 2 0 0 1-.068-.484l.496-.674L4.446 0l.662.089.279.242.411.94.666 1.48 1.033 2.014.302.597.162.553.06.17h.105v-.097l.085-1.134.157-1.392.154-1.792.052-.504.25-.605.497-.327.387.186.319.456-.045.294-.19 1.23-.37 1.93-.243 1.29h.142l.161-.16.654-.868 1.097-1.372.484-.545.565-.601.363-.287h.686l.505.751-.226.775-.707.895-.585.759-.839 1.13-.524.904.048.072.125-.012 1.897-.403 1.024-.186 1.223-.21.553.258.06.263-.218.536-1.307.323-1.533.307-2.284.54-.028.02.032.04 1.029.098.44.024h1.077l2.005.15.525.346.315.424-.053.323-.807.411-3.631-.863-.872-.218h-.12v.073l.726.71 1.331 1.202 1.667 1.55.084.383-.214.302-.226-.032-1.464-1.101-.565-.497-1.28-1.077h-.084v.113l.295.432 1.557 2.34.08.718-.112.234-.404.141-.444-.08-.911-1.28-.94-1.44-.759-1.291-.093.053-.448 4.821-.21.246-.484.186-.403-.307-.214-.496.214-.98.258-1.28.21-1.016.19-1.263.112-.42-.008-.028-.092.012-.953 1.307-1.448 1.957-1.146 1.227-.274.109-.477-.247.045-.44.266-.39 1.586-2.018.956-1.25.617-.723-.004-.105h-.036l-4.212 2.736-.75.096-.324-.302.04-.496.154-.162 1.267-.871z'/></svg>
"""#,
        "codex.svg": #"""
<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 256 260'><path fill='#000000' d='M239.184 106.203a64.716 64.716 0 0 0-5.576-53.103C219.452 28.459 191 15.784 163.213 21.74A65.586 65.586 0 0 0 52.096 45.22a64.716 64.716 0 0 0-43.23 31.36c-14.31 24.602-11.061 55.634 8.033 76.74a64.665 64.665 0 0 0 5.525 53.102c14.174 24.65 42.644 37.324 70.446 31.36a64.72 64.72 0 0 0 48.754 21.744c28.481.025 53.714-18.361 62.414-45.481a64.767 64.767 0 0 0 43.229-31.36c14.137-24.558 10.875-55.423-8.083-76.483Zm-97.56 136.338a48.397 48.397 0 0 1-31.105-11.255l1.535-.87 51.67-29.825a8.595 8.595 0 0 0 4.247-7.367v-72.85l21.845 12.636c.218.111.37.32.409.563v60.367c-.056 26.818-21.783 48.545-48.601 48.601Zm-104.466-44.61a48.345 48.345 0 0 1-5.781-32.589l1.534.921 51.722 29.826a8.339 8.339 0 0 0 8.441 0l63.181-36.425v25.221a.87.87 0 0 1-.358.665l-52.335 30.184c-23.257 13.398-52.97 5.431-66.404-17.803ZM23.549 85.38a48.499 48.499 0 0 1 25.58-21.333v61.39a8.288 8.288 0 0 0 4.195 7.316l62.874 36.272-21.845 12.636a.819.819 0 0 1-.767 0L41.353 151.53c-23.211-13.454-31.171-43.144-17.804-66.405v.256Zm179.466 41.695-63.08-36.63L161.73 77.86a.819.819 0 0 1 .768 0l52.233 30.184a48.6 48.6 0 0 1-7.316 87.635v-61.391a8.544 8.544 0 0 0-4.4-7.213Zm21.742-32.69-1.535-.922-51.619-30.081a8.39 8.39 0 0 0-8.492 0L99.98 99.808V74.587a.716.716 0 0 1 .307-.665l52.233-30.133a48.652 48.652 0 0 1 72.236 50.391v.205ZM88.061 139.097l-21.845-12.585a.87.87 0 0 1-.41-.614V65.685a48.652 48.652 0 0 1 79.757-37.346l-1.535.87-51.67 29.825a8.595 8.595 0 0 0-4.246 7.367l-.051 72.697Zm11.868-25.58 28.138-16.217 28.188 16.218v32.434l-28.086 16.218-28.188-16.218-.052-32.434Z'/></svg>
"""#,
        "opencode.svg": #"""
<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 36'><path fill='#5B8EEB' d='M18 24H6V12H18V24Z' opacity='0.5'/><path fill='#5B8EEB' d='M18 6H6V24H18V6ZM24 30H0V0H24V30Z'/></svg>
"""#
    ]
}
