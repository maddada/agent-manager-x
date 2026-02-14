import AppKit
import SwiftUI

struct HotkeyRecorderRow: View {
    let title: String
    let helperText: String
    let placeholder: String

    @Binding var shortcut: String

    let onSave: (String) -> Void
    let onClear: () -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                Button {
                    toggleRecording()
                } label: {
                    Text(isRecording ? "Press keys…" : (shortcut.isEmpty ? placeholder : shortcut))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .focusable(false)
                .pointerCursor()

                Button("Clear") {
                    stopRecording()
                    shortcut = ""
                    onClear()
                }
                .buttonStyle(.bordered)
                .focusable(false)
                .pointerCursor()

                Button("Save") {
                    stopRecording()
                    onSave(shortcut)
                }
                .buttonStyle(.borderedProminent)
                .focusable(false)
                .pointerCursor()
            }

            Text(helperText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard isRecording else {
                return event
            }

            if let value = shortcutString(from: event) {
                shortcut = value
                stopRecording()
                return nil
            }

            return nil
        }
    }

    private func stopRecording() {
        isRecording = false

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func shortcutString(from event: NSEvent) -> String? {
        var parts: [String] = []

        if event.modifierFlags.contains(.command) {
            parts.append("Command")
        }
        if event.modifierFlags.contains(.control) {
            parts.append("Control")
        }
        if event.modifierFlags.contains(.option) {
            parts.append("Option")
        }
        if event.modifierFlags.contains(.shift) {
            parts.append("Shift")
        }

        guard let key = normalizedKey(from: event) else {
            return nil
        }

        parts.append(key)
        return parts.joined(separator: "+")
    }

    private func normalizedKey(from event: NSEvent) -> String? {
        let specialByKeyCode: [UInt16: String] = [
            49: "Space",
            36: "Enter",
            48: "Tab",
            53: "Escape",
            51: "Delete",
            117: "ForwardDelete",
            123: "Left",
            124: "Right",
            125: "Down",
            126: "Up"
        ]

        if let special = specialByKeyCode[event.keyCode] {
            return special
        }

        let functionKeysByCode: [UInt16: String] = [
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]

        if let function = functionKeysByCode[event.keyCode] {
            return function
        }

        guard let characters = event.charactersIgnoringModifiers,
              let first = characters.first else {
            return nil
        }

        if first.isLetter || first.isNumber {
            return String(first).uppercased()
        }

        let symbol = String(first)
        let allowed = ["-", "=", "[", "]", "\\", ";", "'", ",", ".", "/", "`"]
        if allowed.contains(symbol) {
            return symbol
        }

        return nil
    }
}
