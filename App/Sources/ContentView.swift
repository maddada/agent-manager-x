import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    private var preferredScheme: ColorScheme {
        store.theme == .dark ? .dark : .light
    }

    private var mainAppScale: CGFloat {
        store.mainAppUIElementSize.mainAppScale
    }

    var body: some View {
        GeometryReader { proxy in
            MainDashboardView()
                .frame(
                    width: proxy.size.width / mainAppScale,
                    height: proxy.size.height / mainAppScale,
                    alignment: .topLeading
                )
                .scaleEffect(mainAppScale, anchor: .topLeading)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .preferredColorScheme(preferredScheme)
        .task {
            store.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            store.stop()
        }
    }
}

private extension UIElementSize {
    var mainAppScale: CGFloat {
        switch self {
        case .small:
            return 1.0
        case .medium:
            return 1.12
        case .large:
            return 1.24
        case .extraLarge:
            return 1.36
        }
    }
}
