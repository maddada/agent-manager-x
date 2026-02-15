import Foundation

/// Typed `UserDefaults` access for app-wide settings and per-entity customizations.
final class SettingsStore {
    static let shared = SettingsStore()

    static let defaultGlobalHotkey = "Command+Control+Shift+Space"
    static let defaultMiniViewerHotkey = "Command+Control+Shift+M"
    static let defaultMiniViewerSide: MiniViewerSide = .left
    static let defaultMiniViewerShowOnStart = true
    static let defaultMainAppUIElementSize: UIElementSize = .medium
    static let defaultMiniViewerUIElementSize: UIElementSize = .small
    static let defaultEditorValue: DefaultEditor = .code
    static let defaultTerminalValue: DefaultTerminal = .terminal
    static let defaultCardClickAction: CardClickAction = .editor
    static let defaultDisplayMode: DisplayMode = .masonry
    static let defaultUseSlowerCompatibleProjectSwitching = false
    static let defaultTheme: ThemePreference = .dark
    static let defaultBackgroundImage = "https://images.pexels.com/photos/28428592/pexels-photo-28428592.jpeg"
    static let defaultOverlayOpacity = 88
    static let defaultOverlayColor = "#000000"
    static let defaultNotificationSound: NotificationSound = .arcade

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var globalHotkey: String {
        get { defaults.string(forKey: SettingsKeys.globalHotkey) ?? Self.defaultGlobalHotkey }
        set { defaults.set(newValue, forKey: SettingsKeys.globalHotkey) }
    }

    var miniViewerHotkey: String {
        get { defaults.string(forKey: SettingsKeys.miniViewerHotkey) ?? Self.defaultMiniViewerHotkey }
        set { defaults.set(newValue, forKey: SettingsKeys.miniViewerHotkey) }
    }

    var miniViewerSide: MiniViewerSide {
        get { enumValue(forKey: SettingsKeys.miniViewerSide, default: Self.defaultMiniViewerSide) }
        set { defaults.set(newValue.rawValue, forKey: SettingsKeys.miniViewerSide) }
    }

    var miniViewerShowOnStart: Bool {
        get {
            guard defaults.object(forKey: SettingsKeys.miniViewerShowOnStart) != nil else {
                return Self.defaultMiniViewerShowOnStart
            }
            return defaults.bool(forKey: SettingsKeys.miniViewerShowOnStart)
        }
        set { defaults.set(newValue, forKey: SettingsKeys.miniViewerShowOnStart) }
    }

    var mainAppUIElementSize: UIElementSize {
        get { enumValue(forKey: SettingsKeys.mainAppUIElementSize, default: Self.defaultMainAppUIElementSize) }
        set { defaults.set(newValue.rawValue, forKey: SettingsKeys.mainAppUIElementSize) }
    }

    var miniViewerUIElementSize: UIElementSize {
        get { enumValue(forKey: SettingsKeys.miniViewerUIElementSize, default: Self.defaultMiniViewerUIElementSize) }
        set { defaults.set(newValue.rawValue, forKey: SettingsKeys.miniViewerUIElementSize) }
    }

    var defaultEditor: DefaultEditor {
        get { enumValue(forKey: SettingsKeys.defaultEditor, default: Self.defaultEditorValue) }
        set { defaults.set(newValue.rawValue, forKey: SettingsKeys.defaultEditor) }
    }

    var customEditorCommand: String {
        get { defaults.string(forKey: SettingsKeys.customEditorCommand) ?? "" }
        set { defaults.set(newValue, forKey: SettingsKeys.customEditorCommand) }
    }

    var defaultTerminal: DefaultTerminal {
        get { enumValue(forKey: SettingsKeys.defaultTerminal, default: Self.defaultTerminalValue) }
        set { defaults.set(newValue.rawValue, forKey: SettingsKeys.defaultTerminal) }
    }

    var customTerminalCommand: String {
        get { defaults.string(forKey: SettingsKeys.customTerminalCommand) ?? "" }
        set { defaults.set(newValue, forKey: SettingsKeys.customTerminalCommand) }
    }

    var cardClickAction: CardClickAction {
        get { enumValue(forKey: SettingsKeys.cardClickAction, default: Self.defaultCardClickAction) }
        set { defaults.set(newValue.rawValue, forKey: SettingsKeys.cardClickAction) }
    }

    var displayMode: DisplayMode {
        get { enumValue(forKey: SettingsKeys.displayMode, default: Self.defaultDisplayMode) }
        set { defaults.set(newValue.rawValue, forKey: SettingsKeys.displayMode) }
    }

    var useSlowerCompatibleProjectSwitching: Bool {
        get {
            if defaults.object(forKey: SettingsKeys.useSlowerCompatibleProjectSwitching) != nil {
                return defaults.bool(forKey: SettingsKeys.useSlowerCompatibleProjectSwitching)
            }

            // Backward compatibility for older settings where `true` meant app-based opening.
            if defaults.object(forKey: SettingsKeys.legacyExperimentalVSCodeSessionOpening) != nil {
                return !defaults.bool(forKey: SettingsKeys.legacyExperimentalVSCodeSessionOpening)
            }

            return Self.defaultUseSlowerCompatibleProjectSwitching
        }
        set { defaults.set(newValue, forKey: SettingsKeys.useSlowerCompatibleProjectSwitching) }
    }

    var theme: ThemePreference {
        get {
            // Accept legacy web theme values and collapse them into dark/light for native.
            if let rawValue = defaults.string(forKey: SettingsKeys.theme) {
                if rawValue == "github-light" || rawValue == "solarized-light" || rawValue == "catppuccin-latte" {
                    return .light
                }
                if rawValue == "dark" || rawValue == "light" {
                    return ThemePreference(rawValue: rawValue) ?? Self.defaultTheme
                }
            }
            return Self.defaultTheme
        }
        set { defaults.set(newValue.rawValue, forKey: SettingsKeys.theme) }
    }

    var backgroundImage: String {
        get { defaults.string(forKey: SettingsKeys.backgroundImage) ?? Self.defaultBackgroundImage }
        set { defaults.set(newValue, forKey: SettingsKeys.backgroundImage) }
    }

    var overlayOpacity: Int {
        get {
            guard defaults.object(forKey: SettingsKeys.overlayOpacity) != nil else {
                return Self.defaultOverlayOpacity
            }
            let value = defaults.integer(forKey: SettingsKeys.overlayOpacity)
            return min(max(value, 0), 100)
        }
        set { defaults.set(min(max(newValue, 0), 100), forKey: SettingsKeys.overlayOpacity) }
    }

    var overlayColor: String {
        get { defaults.string(forKey: SettingsKeys.overlayColor) ?? Self.defaultOverlayColor }
        set { defaults.set(newValue, forKey: SettingsKeys.overlayColor) }
    }

    var notificationSound: NotificationSound {
        get { enumValue(forKey: SettingsKeys.notificationSound, default: Self.defaultNotificationSound) }
        set { defaults.set(newValue.rawValue, forKey: SettingsKeys.notificationSound) }
    }

    func projectCommand(for projectPath: String, action: ProjectCommandAction) -> String {
        readProjectCommandsStore()[projectPath]?[action.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func setProjectCommand(_ command: String, for projectPath: String, action: ProjectCommandAction) {
        var store = readProjectCommandsStore()
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.isEmpty {
            store[projectPath]?[action.rawValue] = nil
            if store[projectPath]?.isEmpty == true {
                store[projectPath] = nil
            }
        } else {
            var projectCommands = store[projectPath] ?? [:]
            projectCommands[action.rawValue] = normalized
            store[projectPath] = projectCommands
        }

        defaults.set(store, forKey: SettingsKeys.projectCommands)
    }

    var customNamesBySessionID: [String: String] {
        get { stringDictionary(forKey: SettingsKeys.customNames) }
        set { defaults.set(newValue, forKey: SettingsKeys.customNames) }
    }

    func customName(for sessionID: String) -> String? {
        customNamesBySessionID[sessionID]
    }

    func setCustomName(_ name: String, for sessionID: String) {
        var map = customNamesBySessionID
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            map[sessionID] = nil
        } else {
            map[sessionID] = normalized
        }
        customNamesBySessionID = map
    }

    var customURLsBySessionID: [String: String] {
        get { stringDictionary(forKey: SettingsKeys.customURLs) }
        set { defaults.set(newValue, forKey: SettingsKeys.customURLs) }
    }

    func customURL(for sessionID: String) -> String? {
        customURLsBySessionID[sessionID]
    }

    func setCustomURL(_ url: String, for sessionID: String) {
        var map = customURLsBySessionID
        let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            map[sessionID] = nil
        } else {
            map[sessionID] = normalized
        }
        customURLsBySessionID = map
    }

    private func enumValue<T: RawRepresentable>(forKey key: String, default defaultValue: T) -> T where T.RawValue == String {
        guard let rawValue = defaults.string(forKey: key),
              let value = T(rawValue: rawValue) else {
            return defaultValue
        }
        return value
    }

    private func stringDictionary(forKey key: String) -> [String: String] {
        guard let raw = defaults.dictionary(forKey: key) else {
            return [:]
        }

        var result: [String: String] = [:]
        for (mapKey, value) in raw {
            if let stringValue = value as? String {
                result[mapKey] = stringValue
            }
        }
        return result
    }

    private func readProjectCommandsStore() -> [String: [String: String]] {
        guard let rawStore = defaults.dictionary(forKey: SettingsKeys.projectCommands) else {
            return [:]
        }

        var typedStore: [String: [String: String]] = [:]
        for (projectPath, value) in rawStore {
            guard let commands = value as? [String: Any] else {
                continue
            }

            var typedCommands: [String: String] = [:]
            for (commandKey, commandValue) in commands {
                if let stringValue = commandValue as? String {
                    typedCommands[commandKey] = stringValue
                }
            }

            if !typedCommands.isEmpty {
                typedStore[projectPath] = typedCommands
            }
        }

        return typedStore
    }
}
