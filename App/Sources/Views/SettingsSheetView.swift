import SwiftUI

struct SettingsSheetView: View {
    @EnvironmentObject private var store: AppStore

    @State private var globalHotkeyDraft = ""
    @State private var miniViewerHotkeyDraft = ""
    @State private var overlayColorDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done") {
                    store.hideSettings()
                }
                .keyboardShortcut(.cancelAction)
                .focusable(false)
                .pointerCursor()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    themeSection
                    appearanceSection
                    clickActionSection
                    editorSection
                    terminalSection
                    hotkeysSection
                    miniViewerSection
                    notificationsSection
                    messageSection
                }
                .padding(16)
                .mainAppScrollbarStyle(for: store.mainAppUIElementSize)
            }
            .frame(minWidth: 500, minHeight: 580)
        }
        .onAppear {
            syncDraftValues()
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Theme")

            Picker("Theme", selection: Binding(
                get: { store.theme },
                set: { store.updateTheme($0) }
            )) {
                Text("Dark").tag(ThemePreference.dark)
                Text("Light").tag(ThemePreference.light)
            }
            .pickerStyle(.segmented)
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Background")

            TextField(
                "Background image URL",
                text: Binding(
                    get: { store.backgroundImage },
                    set: { store.updateBackgroundImage($0) }
                )
            )
            .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Overlay color")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("#000000", text: $overlayColorDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Button("Apply") {
                        store.updateOverlayColor(overlayColorDraft)
                        overlayColorDraft = store.overlayColor
                    }
                    .buttonStyle(.bordered)
                    .focusable(false)
                    .pointerCursor()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Overlay opacity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(store.overlayOpacity)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(value: Binding(
                    get: { Double(store.overlayOpacity) },
                    set: { store.updateOverlayOpacity(Int($0)) }
                ), in: 0...100, step: 1)
            }

            Picker("Main App UI Element Size", selection: Binding(
                get: { store.mainAppUIElementSize },
                set: { store.updateMainAppUIElementSize($0) }
            )) {
                ForEach(UIElementSize.allCases, id: \.rawValue) { size in
                    Text(size.displayName).tag(size)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var clickActionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Card Click")

            Picker("Card Click", selection: Binding(
                get: { store.cardClickAction },
                set: { store.updateCardClickAction($0) }
            )) {
                Text("Editor").tag(CardClickAction.editor)
                Text("Terminal").tag(CardClickAction.terminal)
            }
            .pickerStyle(.segmented)
        }
    }

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Editor")

            Picker("Default Editor", selection: Binding(
                get: { store.defaultEditor },
                set: { store.updateDefaultEditor($0) }
            )) {
                ForEach(DefaultEditor.allCases, id: \.rawValue) { editor in
                    Text(editorLabel(editor)).tag(editor)
                }
            }

            if store.defaultEditor == .custom {
                TextField("Custom editor command", text: Binding(
                    get: { store.customEditorCommand },
                    set: { store.updateCustomEditorCommand($0) }
                ))
                .textFieldStyle(.roundedBorder)
            }

            if store.defaultEditor == .code || store.defaultEditor == .cursor {
                Toggle("Use slower but more compatible method to switch to project", isOn: Binding(
                    get: { store.useSlowerCompatibleProjectSwitching },
                    set: { store.updateUseSlowerCompatibleProjectSwitching($0) }
                ))
            }
        }
    }

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Terminal")

            Picker("Default Terminal", selection: Binding(
                get: { store.defaultTerminal },
                set: { store.updateDefaultTerminal($0) }
            )) {
                ForEach(DefaultTerminal.allCases, id: \.rawValue) { terminal in
                    Text(terminalLabel(terminal)).tag(terminal)
                }
            }

            if store.defaultTerminal == .custom {
                TextField("Custom terminal command", text: Binding(
                    get: { store.customTerminalCommand },
                    set: { store.updateCustomTerminalCommand($0) }
                ))
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var hotkeysSection: some View {
        HotkeyRecorderRow(
            title: "Global Hotkey",
            helperText: "Toggle the main window from anywhere.",
            placeholder: "Click to set hotkey",
            shortcut: $globalHotkeyDraft,
            onSave: { store.saveGlobalHotkey($0) },
            onClear: { store.clearGlobalHotkey() }
        )
    }

    private var miniViewerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HotkeyRecorderRow(
                title: "Mini Viewer Hotkey",
                helperText: "Toggle the native mini viewer.",
                placeholder: "Click to set mini viewer hotkey",
                shortcut: $miniViewerHotkeyDraft,
                onSave: { store.saveMiniViewerHotkey($0) },
                onClear: { store.clearMiniViewerHotkey() }
            )

            Picker("Mini Viewer Side", selection: Binding(
                get: { store.miniViewerSide },
                set: { store.updateMiniViewerSide($0) }
            )) {
                Text("Left").tag(MiniViewerSide.left)
                Text("Right").tag(MiniViewerSide.right)
            }
            .pickerStyle(.segmented)

            Picker("Mini Viewer UI Element Size", selection: Binding(
                get: { store.miniViewerUIElementSize },
                set: { store.updateMiniViewerUIElementSize($0) }
            )) {
                ForEach(UIElementSize.allCases, id: \.rawValue) { size in
                    Text(size.displayName).tag(size)
                }
            }
            .pickerStyle(.menu)

            Toggle("Show mini viewer on start", isOn: Binding(
                get: { store.miniViewerShowOnStart },
                set: { store.updateMiniViewerShowOnStart($0) }
            ))
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Notifications")

            Text("Install voice notifications for task completion.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if store.notificationState.installState == .installed {
                    Button("Uninstall", role: .destructive) {
                        store.uninstallNotifications()
                    }
                    .buttonStyle(.bordered)
                    .focusable(false)
                    .pointerCursor()
                } else {
                    Button("Install") {
                        store.installNotifications()
                    }
                    .buttonStyle(.borderedProminent)
                    .focusable(false)
                    .pointerCursor()
                }

                if store.notificationState.installState == .installed {
                    Button(store.notificationState.bellModeEnabled ? "Bell Mode: On" : "Bell Mode: Off") {
                        store.toggleBellMode()
                    }
                    .buttonStyle(.bordered)
                    .focusable(false)
                    .pointerCursor()
                }
            }
            .disabled(store.notificationState.isLoading)
        }
    }

    @ViewBuilder
    private var messageSection: some View {
        if let error = store.settingsError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.12)))
        }

        if let confirmation = store.settingsConfirmation {
            Text(confirmation)
                .font(.caption)
                .foregroundStyle(.green)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.12)))
        }
    }

    private func syncDraftValues() {
        globalHotkeyDraft = store.globalHotkey
        miniViewerHotkeyDraft = store.miniViewerHotkey
        overlayColorDraft = store.overlayColor
    }

    private func editorLabel(_ editor: DefaultEditor) -> String {
        switch editor {
        case .code:
            return "VS Code"
        case .neovim:
            return "Neovim"
        default:
            return editor.rawValue.capitalized
        }
    }

    private func terminalLabel(_ terminal: DefaultTerminal) -> String {
        switch terminal {
        case .iterm:
            return "iTerm"
        default:
            return terminal.rawValue.capitalized
        }
    }
}

private struct SectionTitle: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(.subheadline.weight(.semibold))
    }
}
