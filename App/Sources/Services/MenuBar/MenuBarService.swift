import AppKit
import Foundation

@MainActor
final class MenuBarService: NSObject {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var onShowWindow: (() -> Void)?
    private var onQuit: (() -> Void)?

    func setup(onShowWindow: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onShowWindow = onShowWindow
        self.onQuit = onQuit

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()

        let showItem = NSMenuItem(title: "Show Window", action: #selector(handleShowWindow), keyEquivalent: "")
        showItem.target = self

        let quitItem = NSMenuItem(title: "Quit", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self

        menu.addItem(showItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        if let button = item.button {
            button.image = loadTrayImage()
            button.image?.isTemplate = true
            button.imagePosition = .imageLeft
            button.target = self
            button.action = #selector(handleStatusItemClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        statusItem = item
        statusMenu = menu
    }

    func teardown() {
        guard let statusItem else {
            return
        }

        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
        statusMenu = nil
        onShowWindow = nil
        onQuit = nil
    }

    func updateTitle(total: Int, waiting: Int) {
        guard let button = statusItem?.button else {
            return
        }

        if waiting > 0 {
            button.title = "\(total) (\(waiting) idle)"
        } else if total > 0 {
            button.title = "\(total)"
        } else {
            button.title = ""
        }
    }

    @objc
    private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else {
            onShowWindow?()
            return
        }

        if event.type == .rightMouseUp {
            if let statusItem, let menu = statusMenu {
                statusItem.menu = menu
                statusItem.button?.performClick(nil)
                statusItem.menu = nil
            }
            return
        }

        onShowWindow?()
    }

    @objc
    private func handleShowWindow() {
        onShowWindow?()
    }

    @objc
    private func handleQuit() {
        if let onQuit {
            onQuit()
        } else {
            NSApplication.shared.terminate(nil)
        }
    }

    private func loadTrayImage() -> NSImage? {
        if let bundled = Bundle.main.url(forResource: "tray-icon", withExtension: "png", subdirectory: "tray"),
           let image = NSImage(contentsOf: bundled) {
            return image
        }

        if let direct = Bundle.main.url(forResource: "tray-icon", withExtension: "png"),
           let image = NSImage(contentsOf: direct) {
            return image
        }

        let sourceURL = URL(fileURLWithPath: #filePath)
        let repoRoot = sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let devAsset = repoRoot
            .appendingPathComponent("App", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("tray", isDirectory: true)
            .appendingPathComponent("tray-icon.png")

        return NSImage(contentsOf: devAsset)
    }
}
