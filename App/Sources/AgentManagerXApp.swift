import AppKit
import SwiftUI

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard
            let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let icon = NSImage(contentsOf: url)
        else {
            return
        }

        NSApplication.shared.applicationIconImage = icon
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
                .frame(minWidth: 900, minHeight: 620)
        }
        .commands {
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
