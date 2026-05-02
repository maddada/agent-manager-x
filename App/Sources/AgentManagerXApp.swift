import AppKit
import Combine
import Sparkle
import SwiftUI

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let updaterController: SPUStandardUpdaterController
    @ObservedObject var updaterState: UpdaterState

    var updater: SPUUpdater {
        updaterController.updater
    }

    override init() {
        let state = UpdaterState()
        updaterState = state

        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: state, userDriverDelegate: nil)
        updaterController = controller
        state.updater = controller.updater

        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard
            let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let icon = NSImage(contentsOf: url)
        else {
            return
        }

        NSApplication.shared.applicationIconImage = icon

        if updater.automaticallyChecksForUpdates {
            updater.checkForUpdatesInBackground()
        }
    }
}

private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater) {
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: \.canCheckForUpdates, on: self)
    }
}

private struct CheckForUpdatesCommand: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

@main
struct AgentManagerXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(appDelegate.updaterState)
                .frame(minWidth: 900, minHeight: 620)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updater: appDelegate.updater)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    store.showSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandMenu("Display") {
                Button("Increase Main Window UI Size") {
                    store.increaseMainAppUIElementSizeFromShortcut()
                }
                .keyboardShortcut("=", modifiers: [.command])

                Button("Decrease Main Window UI Size") {
                    store.decreaseMainAppUIElementSizeFromShortcut()
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button("Reset Main Window UI Size (Medium)") {
                    store.resetMainAppUIElementSizeToMediumFromShortcut()
                }
                .keyboardShortcut("0", modifiers: [.command])
            }

            CommandMenu("Projects") {
                ForEach(1...9, id: \.self) { number in
                    Button("Open Project \(number)") {
                        store.openProjectFromShortcutNumber(number)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: [.command])
                }
            }
        }
    }
}
