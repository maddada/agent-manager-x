import AppKit
import SwiftUI

private struct MainAppScrollbarConfigurator: NSViewRepresentable {
    let scale: CGFloat

    func makeNSView(context: Context) -> ScrollbarConfiguratorView {
        let view = ScrollbarConfiguratorView()
        view.scale = scale
        return view
    }

    func updateNSView(_ nsView: ScrollbarConfiguratorView, context: Context) {
        nsView.scale = scale
    }
}

private final class ScrollbarConfiguratorView: NSView {
    var scale: CGFloat = 1.0 {
        didSet {
            applyStyle()
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleStyleApplication()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleStyleApplication()
    }

    override func layout() {
        super.layout()
        applyStyle()
    }

    private func scheduleStyleApplication() {
        DispatchQueue.main.async { [weak self] in
            self?.applyStyle()
        }
    }

    private func applyStyle() {
        guard let scrollView = enclosingScrollView else {
            return
        }

        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.scrollerInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 3)

        guard let scroller = scrollView.verticalScroller else {
            return
        }

        scroller.controlSize = .mini
        scroller.knobStyle = .default

        let safeScale = max(scale, 0.1)
        let targetVisibleWidth: CGFloat = 6
        let compensatedWidth = targetVisibleWidth / safeScale

        var frame = scroller.frame
        if abs(frame.width - compensatedWidth) > 0.25 {
            frame.origin.x += frame.width - compensatedWidth
            frame.size.width = compensatedWidth
            scroller.frame = frame
        }
    }
}

extension View {
    func mainAppScrollbarStyle(for size: UIElementSize) -> some View {
        background(
            MainAppScrollbarConfigurator(scale: size.mainAppScale)
                .frame(width: 0, height: 0)
        )
    }
}
