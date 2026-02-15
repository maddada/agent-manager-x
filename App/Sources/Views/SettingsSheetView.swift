import SwiftUI

struct SettingsSheetView: View {
    @EnvironmentObject private var store: AppStore

    @State private var globalHotkeyDraft = ""
    @State private var miniViewerHotkeyDraft = ""
    @State private var overlayColorDraft = ""

    private var settingsScale: CGFloat {
        store.mainAppUIElementSize.mainAppScale
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Settings")
                        .font(.title2.weight(.bold))
                    Spacer()
                    Button("Done") {
                        store.hideSettings()
                    }
                    .keyboardShortcut(.cancelAction)
                    .focusable(false)
                    .pointerCursor()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        settingsSection("Appearance") {
                            themeRow
                            backgroundRows
                            uiSizeRow
                        }

                        settingsDivider

                        settingsSection("Behavior") {
                            clickActionRow
                            editorRows
                            terminalRows
                        }

                        settingsDivider

                        settingsSection("Hotkeys") {
                            globalHotkeyRow
                            shortcutsReferenceRows
                        }

                        settingsDivider

                        settingsSection("Mini Viewer") {
                            miniViewerHotkeyRow
                            miniViewerOptionsRows
                        }

                        settingsDivider

                        settingsSection("Notifications") {
                            notificationRows
                        }

                        messageSection
                    }
                    .mainAppScrollbarStyle(for: store.mainAppUIElementSize)
                }
            }
            .frame(
                width: proxy.size.width / settingsScale,
                height: proxy.size.height / settingsScale,
                alignment: .topLeading
            )
            .scaleEffect(settingsScale, anchor: .topLeading)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(minWidth: 500, minHeight: 580)
        .onAppear {
            syncDraftValues()
        }
    }

    // MARK: - Section Builder

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            content()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var settingsDivider: some View {
        Divider()
            .padding(.horizontal, 20)
    }

    // MARK: - Appearance

    private var themeRow: some View {
        SettingsRow("Theme") {
            Picker("Theme", selection: Binding(
                get: { store.theme },
                set: { store.updateTheme($0) }
            )) {
                Text("Dark").tag(ThemePreference.dark)
                Text("Light").tag(ThemePreference.light)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
    }

    private var backgroundRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow("Background Image") {
                TextField(
                    "URL",
                    text: Binding(
                        get: { store.backgroundImage },
                        set: { store.updateBackgroundImage($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
            }

            SettingsRow("Overlay Color") {
                HStack(spacing: 8) {
                    TextField("#000000", text: $overlayColorDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 120)

                    Button("Apply") {
                        store.updateOverlayColor(overlayColorDraft)
                        overlayColorDraft = store.overlayColor
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .focusable(false)
                    .pointerCursor()
                }
            }

            SettingsRow("Overlay Opacity") {
                HStack(spacing: 10) {
                    Slider(value: Binding(
                        get: { Double(store.overlayOpacity) },
                        set: { store.updateOverlayOpacity(Int($0)) }
                    ), in: 0...100, step: 1)

                    Text("\(store.overlayOpacity)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
    }

    private var uiSizeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingsRow("UI Element Size") {
                Picker("", selection: Binding(
                    get: { store.mainAppUIElementSize },
                    set: { store.updateMainAppUIElementSize($0) }
                )) {
                    ForEach(UIElementSize.allCases, id: \.rawValue) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }

            Text("Cmd+= / Cmd+- to adjust, Cmd+0 to reset.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Behavior

    private var clickActionRow: some View {
        SettingsRow("Card Click Action") {
            Picker("", selection: Binding(
                get: { store.cardClickAction },
                set: { store.updateCardClickAction($0) }
            )) {
                Text("Editor").tag(CardClickAction.editor)
                Text("Terminal").tag(CardClickAction.terminal)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
    }

    private var editorRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow("Default Editor") {
                Picker("", selection: Binding(
                    get: { store.defaultEditor },
                    set: { store.updateDefaultEditor($0) }
                )) {
                    ForEach(DefaultEditor.allCases, id: \.rawValue) { editor in
                        Text(editorLabel(editor)).tag(editor)
                    }
                }
                .frame(width: 140)
            }

            if store.defaultEditor == .custom {
                TextField("Custom editor command", text: Binding(
                    get: { store.customEditorCommand },
                    set: { store.updateCustomEditorCommand($0) }
                ))
                .textFieldStyle(.roundedBorder)
            }

            if store.defaultEditor == .code || store.defaultEditor == .cursor {
                Toggle("Use slower but more compatible project switching", isOn: Binding(
                    get: { store.useSlowerCompatibleProjectSwitching },
                    set: { store.updateUseSlowerCompatibleProjectSwitching($0) }
                ))
                .font(.callout)
            }
        }
    }

    private var terminalRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow("Default Terminal") {
                Picker("", selection: Binding(
                    get: { store.defaultTerminal },
                    set: { store.updateDefaultTerminal($0) }
                )) {
                    ForEach(DefaultTerminal.allCases, id: \.rawValue) { terminal in
                        Text(terminalLabel(terminal)).tag(terminal)
                    }
                }
                .frame(width: 140)
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

    // MARK: - Hotkeys

    private var globalHotkeyRow: some View {
        HotkeyRecorderRow(
            title: "Global Hotkey",
            helperText: "Toggle the main window from anywhere.",
            placeholder: "Click to set hotkey",
            shortcut: $globalHotkeyDraft,
            onSave: { store.saveGlobalHotkey($0) },
            onClear: { store.clearGlobalHotkey() }
        )
    }

    // MARK: - Mini Viewer

    private var miniViewerHotkeyRow: some View {
        HotkeyRecorderRow(
            title: "Mini Viewer Hotkey",
            helperText: "Toggle the native mini viewer.",
            placeholder: "Click to set mini viewer hotkey",
            shortcut: $miniViewerHotkeyDraft,
            onSave: { store.saveMiniViewerHotkey($0) },
            onClear: { store.clearMiniViewerHotkey() }
        )
    }

    private var miniViewerOptionsRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow("Side") {
                Picker("", selection: Binding(
                    get: { store.miniViewerSide },
                    set: { store.updateMiniViewerSide($0) }
                )) {
                    Text("Left").tag(MiniViewerSide.left)
                    Text("Right").tag(MiniViewerSide.right)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            SettingsRow("UI Element Size") {
                Picker("", selection: Binding(
                    get: { store.miniViewerUIElementSize },
                    set: { store.updateMiniViewerUIElementSize($0) }
                )) {
                    ForEach(UIElementSize.allCases, id: \.rawValue) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }

            Toggle("Show mini viewer on start", isOn: Binding(
                get: { store.miniViewerShowOnStart },
                set: { store.updateMiniViewerShowOnStart($0) }
            ))
            .font(.callout)
        }
    }

    // MARK: - Notifications

    private var notificationRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow("Sound") {
                HStack(spacing: 8) {
                    Picker("", selection: Binding(
                        get: { store.notificationSound },
                        set: { store.updateNotificationSound($0) }
                    )) {
                        ForEach(NotificationSound.allCases, id: \.rawValue) { sound in
                            Text(sound.displayName).tag(sound)
                        }
                    }
                    .pickerStyle(.menu)

                    Button("Play") {
                        store.previewNotificationSound()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .focusable(false)
                    .pointerCursor()
                }
            }

            Text("Used for Bell Mode. Choose a sound, then click Play to preview.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                if store.notificationState.installState == .installed {
                    Button("Uninstall", role: .destructive) {
                        store.uninstallNotifications()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .focusable(false)
                    .pointerCursor()
                } else {
                    Button("Install Voice Notifications") {
                        store.installNotifications()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .focusable(false)
                    .pointerCursor()
                }

                if store.notificationState.installState == .installed {
                    Button(store.notificationState.bellModeEnabled ? "Bell Mode: On" : "Bell Mode: Off") {
                        store.toggleBellMode()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .focusable(false)
                    .pointerCursor()
                }
            }
            .disabled(store.notificationState.isLoading)
        }
    }

    // MARK: - Keyboard Shortcuts Reference

    private var shortcutsReferenceRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            shortcutRow("Cmd+,", "Open Settings")
            shortcutRow("Cmd+0", "Reset UI Size to Medium")
            shortcutRow("Cmd+= / Cmd+-", "Increase / Decrease UI Size")
            shortcutRow("Cmd+1...9", "Open Project 1...9")
        }
    }

    private func shortcutRow(_ key: String, _ description: String) -> some View {
        HStack(spacing: 0) {
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(description)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Messages

    @ViewBuilder
    private var messageSection: some View {
        if store.settingsError != nil || store.settingsConfirmation != nil {
            VStack(alignment: .leading, spacing: 8) {
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
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Helpers

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

// MARK: - Reusable Row

private struct SettingsRow<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(minWidth: 120, alignment: .leading)

            content
        }
    }
}
