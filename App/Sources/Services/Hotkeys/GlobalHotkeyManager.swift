import AppKit
import Carbon
import Foundation

struct ParsedHotkey {
    let keyCode: UInt32
    let modifiers: UInt32
}

enum HotkeyTarget {
    case appToggle
    case miniViewerToggle

    var identifier: UInt32 {
        switch self {
        case .appToggle:
            return 1
        case .miniViewerToggle:
            return 2
        }
    }
}

enum HotkeyShortcutParser {
    static func parse(_ shortcut: String) -> ParsedHotkey? {
        let rawTokens = shortcut
            .split(separator: "+", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rawTokens.isEmpty else {
            return nil
        }

        var modifiers: UInt32 = 0
        var keyCode: UInt32?

        for token in rawTokens {
            let normalized = token.lowercased()
            if let modifier = modifierForToken(normalized) {
                modifiers |= modifier
                continue
            }

            if keyCode == nil,
               let candidateKeyCode = keyCodeForToken(normalized) {
                keyCode = candidateKeyCode
            }
        }

        guard let keyCode else {
            return nil
        }

        return ParsedHotkey(keyCode: keyCode, modifiers: modifiers)
    }

    private static func modifierForToken(_ token: String) -> UInt32? {
        switch token {
        case "command", "cmd", "⌘":
            return UInt32(cmdKey)
        case "control", "ctrl", "ctl", "^", "⌃":
            return UInt32(controlKey)
        case "shift", "⇧":
            return UInt32(shiftKey)
        case "option", "opt", "alt", "⌥":
            return UInt32(optionKey)
        case "function", "fn", "globe":
            // Carbon hotkeys do not expose a stable fn/globe modifier for global registration.
            return 0
        default:
            return nil
        }
    }

    private static func keyCodeForToken(_ token: String) -> UInt32? {
        if let functionKey = parseFunctionKey(token) {
            return functionKey
        }

        switch token {
        case "space", "spacebar": return UInt32(kVK_Space)
        case "enter", "return", "↩": return UInt32(kVK_Return)
        case "tab", "⇥": return UInt32(kVK_Tab)
        case "escape", "esc", "⎋": return UInt32(kVK_Escape)
        case "delete", "backspace", "⌫": return UInt32(kVK_Delete)
        case "forwarddelete", "del", "⌦": return UInt32(kVK_ForwardDelete)
        case "up", "uparrow", "↑": return UInt32(kVK_UpArrow)
        case "down", "downarrow", "↓": return UInt32(kVK_DownArrow)
        case "left", "leftarrow", "←": return UInt32(kVK_LeftArrow)
        case "right", "rightarrow", "→": return UInt32(kVK_RightArrow)
        case "home": return UInt32(kVK_Home)
        case "end": return UInt32(kVK_End)
        case "pageup", "pgup": return UInt32(kVK_PageUp)
        case "pagedown", "pgdn": return UInt32(kVK_PageDown)
        case "help": return UInt32(kVK_Help)
        default:
            break
        }

        if token.count == 1,
           let scalar = token.unicodeScalars.first {
            return keyCodeForScalar(scalar)
        }

        return nil
    }

    private static func parseFunctionKey(_ token: String) -> UInt32? {
        guard token.hasPrefix("f"),
              let number = Int(token.dropFirst()) else {
            return nil
        }

        switch number {
        case 1: return UInt32(kVK_F1)
        case 2: return UInt32(kVK_F2)
        case 3: return UInt32(kVK_F3)
        case 4: return UInt32(kVK_F4)
        case 5: return UInt32(kVK_F5)
        case 6: return UInt32(kVK_F6)
        case 7: return UInt32(kVK_F7)
        case 8: return UInt32(kVK_F8)
        case 9: return UInt32(kVK_F9)
        case 10: return UInt32(kVK_F10)
        case 11: return UInt32(kVK_F11)
        case 12: return UInt32(kVK_F12)
        case 13: return UInt32(kVK_F13)
        case 14: return UInt32(kVK_F14)
        case 15: return UInt32(kVK_F15)
        case 16: return UInt32(kVK_F16)
        case 17: return UInt32(kVK_F17)
        case 18: return UInt32(kVK_F18)
        case 19: return UInt32(kVK_F19)
        case 20: return UInt32(kVK_F20)
        default:
            return nil
        }
    }

    private static func keyCodeForScalar(_ scalar: UnicodeScalar) -> UInt32? {
        switch scalar {
        case "a": return UInt32(kVK_ANSI_A)
        case "b": return UInt32(kVK_ANSI_B)
        case "c": return UInt32(kVK_ANSI_C)
        case "d": return UInt32(kVK_ANSI_D)
        case "e": return UInt32(kVK_ANSI_E)
        case "f": return UInt32(kVK_ANSI_F)
        case "g": return UInt32(kVK_ANSI_G)
        case "h": return UInt32(kVK_ANSI_H)
        case "i": return UInt32(kVK_ANSI_I)
        case "j": return UInt32(kVK_ANSI_J)
        case "k": return UInt32(kVK_ANSI_K)
        case "l": return UInt32(kVK_ANSI_L)
        case "m": return UInt32(kVK_ANSI_M)
        case "n": return UInt32(kVK_ANSI_N)
        case "o": return UInt32(kVK_ANSI_O)
        case "p": return UInt32(kVK_ANSI_P)
        case "q": return UInt32(kVK_ANSI_Q)
        case "r": return UInt32(kVK_ANSI_R)
        case "s": return UInt32(kVK_ANSI_S)
        case "t": return UInt32(kVK_ANSI_T)
        case "u": return UInt32(kVK_ANSI_U)
        case "v": return UInt32(kVK_ANSI_V)
        case "w": return UInt32(kVK_ANSI_W)
        case "x": return UInt32(kVK_ANSI_X)
        case "y": return UInt32(kVK_ANSI_Y)
        case "z": return UInt32(kVK_ANSI_Z)
        case "0": return UInt32(kVK_ANSI_0)
        case "1": return UInt32(kVK_ANSI_1)
        case "2": return UInt32(kVK_ANSI_2)
        case "3": return UInt32(kVK_ANSI_3)
        case "4": return UInt32(kVK_ANSI_4)
        case "5": return UInt32(kVK_ANSI_5)
        case "6": return UInt32(kVK_ANSI_6)
        case "7": return UInt32(kVK_ANSI_7)
        case "8": return UInt32(kVK_ANSI_8)
        case "9": return UInt32(kVK_ANSI_9)
        case "-": return UInt32(kVK_ANSI_Minus)
        case "=": return UInt32(kVK_ANSI_Equal)
        case "[": return UInt32(kVK_ANSI_LeftBracket)
        case "]": return UInt32(kVK_ANSI_RightBracket)
        case "\\": return UInt32(kVK_ANSI_Backslash)
        case ";": return UInt32(kVK_ANSI_Semicolon)
        case "'": return UInt32(kVK_ANSI_Quote)
        case ",": return UInt32(kVK_ANSI_Comma)
        case ".": return UInt32(kVK_ANSI_Period)
        case "/": return UInt32(kVK_ANSI_Slash)
        case "`": return UInt32(kVK_ANSI_Grave)
        default:
            return nil
        }
    }
}

final class GlobalHotkeyManager {
    private static let hotKeySignature: OSType = 0x414D5858 // "AMXX"

    private var eventHandlerRef: EventHandlerRef?
    private var appToggleHotKeyRef: EventHotKeyRef?
    private var miniViewerHotKeyRef: EventHotKeyRef?

    private var appToggleCallback: (() -> Void)?
    private var miniViewerToggleCallback: (() -> Void)?

    init() {
        installEventHandlerIfNeeded()
    }

    deinit {
        unregisterAppToggleHotkey()
        unregisterMiniViewerHotkey()

        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    func setCallbacks(onAppToggle: (() -> Void)?, onMiniViewerToggle: (() -> Void)?) {
        appToggleCallback = onAppToggle
        miniViewerToggleCallback = onMiniViewerToggle
    }

    @discardableResult
    func registerAppToggleHotkey(
        _ shortcut: String,
        fallback fallbackShortcut: String = SettingsStore.defaultGlobalHotkey
    ) -> Bool {
        registerHotkey(.appToggle, shortcut: shortcut, fallback: fallbackShortcut)
    }

    func unregisterAppToggleHotkey() {
        unregisterHotkey(.appToggle)
    }

    @discardableResult
    func registerMiniViewerHotkey(
        _ shortcut: String,
        fallback fallbackShortcut: String = SettingsStore.defaultMiniViewerHotkey
    ) -> Bool {
        registerHotkey(.miniViewerToggle, shortcut: shortcut, fallback: fallbackShortcut)
    }

    func unregisterMiniViewerHotkey() {
        unregisterHotkey(.miniViewerToggle)
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else {
                return noErr
            }

            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            return manager.handleHotkeyEvent(event)
        }

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        if status != noErr {
            eventHandlerRef = nil
        }
    }

    @discardableResult
    private func registerHotkey(_ target: HotkeyTarget, shortcut: String, fallback: String) -> Bool {
        unregisterHotkey(target)

        guard let parsed = HotkeyShortcutParser.parse(shortcut) ?? HotkeyShortcutParser.parse(fallback) else {
            return false
        }

        var hotkeyRef: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: Self.hotKeySignature, id: target.identifier)

        let status = RegisterEventHotKey(
            parsed.keyCode,
            parsed.modifiers,
            hotkeyID,
            GetEventDispatcherTarget(),
            0,
            &hotkeyRef
        )

        guard status == noErr, let hotkeyRef else {
            return false
        }

        switch target {
        case .appToggle:
            appToggleHotKeyRef = hotkeyRef
        case .miniViewerToggle:
            miniViewerHotKeyRef = hotkeyRef
        }

        return true
    }

    private func unregisterHotkey(_ target: HotkeyTarget) {
        switch target {
        case .appToggle:
            if let ref = appToggleHotKeyRef {
                UnregisterEventHotKey(ref)
                appToggleHotKeyRef = nil
            }
        case .miniViewerToggle:
            if let ref = miniViewerHotKeyRef {
                UnregisterEventHotKey(ref)
                miniViewerHotKeyRef = nil
            }
        }
    }

    private func handleHotkeyEvent(_ event: EventRef) -> OSStatus {
        var hotkeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )

        guard status == noErr else {
            return status
        }

        switch hotkeyID.id {
        case HotkeyTarget.appToggle.identifier:
            appToggleCallback?()
        case HotkeyTarget.miniViewerToggle.identifier:
            miniViewerToggleCallback?()
        default:
            break
        }

        return noErr
    }
}
