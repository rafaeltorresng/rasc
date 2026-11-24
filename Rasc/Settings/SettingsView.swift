import AppKit
import KeyboardShortcuts
import SwiftUI

struct RefineStatusDescription: Equatable, Sendable {
    let headline: String
    let detail: String

    static func make(from availability: RefinementAvailability) -> Self {
        switch availability {
        case .available:
            RefineStatusDescription(
                headline: "On-device",
                detail: "Refine runs on-device with Apple Intelligence when you invoke it."
            )
        case .unavailable(.appleIntelligenceNotEnabled):
            RefineStatusDescription(
                headline: "Unavailable",
                detail: "Turn on Apple Intelligence in System Settings to use Refine."
            )
        case .unavailable(.deviceNotEligible):
            RefineStatusDescription(
                headline: "Unavailable",
                detail: "Refine requires a Mac that supports Apple Intelligence."
            )
        case .unavailable(.modelNotReady):
            RefineStatusDescription(
                headline: "Preparing",
                detail: "Apple Intelligence is still preparing its on-device model. Try again later."
            )
        case .unavailable(.unsupportedEnvironment):
            RefineStatusDescription(
                headline: "macOS 26 required",
                detail: "Refine needs macOS 26 or later and Apple Intelligence. Capture and Keep work without it."
            )
        case .unavailable(.unknown):
            RefineStatusDescription(
                headline: "Unavailable",
                detail: "Refine is currently unavailable on this Mac."
            )
        }
    }
}

private enum RefineLanguagePickerValue: Hashable {
    case matchNote
    case fixedLocale(String)
}

struct SettingsView: View {
    private let refinementProvider: any RefinementProvider
    private let loginItemController: LoginItemController
    private let languageSettings: RefineLanguageSettingsStore
    private let themeSettings: AppThemeSettingsStore
    private let supportedLocales: any RefineSupportedLocaleDiscovering

    @ObservedObject private var themeStore: ThemeStore
    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(NoteTextSize.preferenceKey) private var noteTextSize: NoteTextSize = .standard
    @State private var customDraft: CustomTheme
    @State private var customEditingScheme: ColorScheme?
    @State private var selectedTheme: AppTheme
    @State private var launchAtLogin = false
    @State private var loginItemState = LoginItemState.disabled
    @State private var launchAtLoginError: String?
    @State private var refineStatus = RefineStatusDescription(
        headline: "Checking…",
        detail: "Checking Refine availability."
    )
    @State private var selectedLanguage: RefineLanguagePickerValue = .matchNote
    @State private var supportedFixedLocales: [RefineFixedLocaleOption] = []
    @State private var languageResolution = RefineLanguagePreferenceResolution(
        stored: .matchNote,
        effectivePolicy: .matchNote,
        isUsingFallback: false,
        unsupportedSavedLocaleIdentifier: nil
    )
    @State private var globalShortcutRevision = 0
    @State private var shortcutRestoreMessage: String?

    init(
        refinementProvider: any RefinementProvider = FoundationModelsRefinementProvider(),
        loginItemController: LoginItemController = LoginItemController(),
        languageSettings: RefineLanguageSettingsStore = RefineLanguageSettingsStore(),
        themeSettings: AppThemeSettingsStore = AppThemeSettingsStore(),
        themeStore: ThemeStore = .shared,
        supportedLocales: any RefineSupportedLocaleDiscovering = RefineSupportedLocales()
    ) {
        self.refinementProvider = refinementProvider
        self.loginItemController = loginItemController
        self.languageSettings = languageSettings
        self.themeSettings = themeSettings
        _selectedTheme = State(initialValue: themeSettings.load())
        self.themeStore = themeStore
        _customDraft = State(initialValue: themeStore.custom)
        self.supportedLocales = supportedLocales
    }

    var body: some View {
        let _ = globalShortcutRevision
        ScrollViewReader { proxy in
            settingsForm
                .onAppear {
                    scrollToKeyboardShortcutsIfNeeded(proxy)
                }
                .onReceive(NotificationCenter.default.publisher(for: SettingsNavigation.revealNotification)) { _ in
                    scrollToKeyboardShortcutsIfNeeded(proxy)
                }
        }
        .onGlobalShortcutChange {
            globalShortcutRevision += 1
            shortcutRestoreMessage = nil
        }
    }

    private var settingsForm: some View {
        Form {
            Section("Appearance") {
                Picker("Mode", selection: Binding(
                    get: { selectedTheme },
                    set: { selectMode($0) }
                )) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Note Text Size") {
                    Picker("Note Text Size", selection: $noteTextSize) {
                        ForEach(NoteTextSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 194)
                }

                HStack(spacing: 16) {
                    ForEach(ThemePreset.allCases) { preset in
                        ThemePresetSwatch(
                            preset: preset,
                            preview: ThemeCatalog.resolve(
                                preset: preset, scheme: colorScheme, custom: themeStore.custom
                            ),
                            isSelected: themeStore.preset == preset
                        ) {
                            themeStore.selectPreset(preset)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Theme Style")

                if themeStore.preset == .custom {
                    customThemeEditor
                }

                if themeStore.isCustomized || selectedTheme != .system {
                    Button("Restore Default Theme") {
                        themeStore.reset()
                        selectMode(.system)
                    }
                    .help("Restore System appearance and Graphite Paper")
                }
            }
            .listRowBackground(settingsSectionBackground)

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, isEnabled in
                        updateLaunchAtLogin(isEnabled)
                    }

                if loginItemState == .requiresApproval {
                    HStack {
                        Text("Launch at Login needs approval in System Settings.")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText(for: colorScheme))
                        Spacer()
                        Button("Open Login Items Settings") {
                            loginItemController.openSystemSettings()
                        }
                    }
                }

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(palette.destructiveText(for: colorScheme))
                }
            }
            .listRowBackground(settingsSectionBackground)

            keyboardShortcutsSection

            Section("Refine") {
                LabeledContent(refineStatus.headline) {
                    Text(refineStatus.detail)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText(for: colorScheme))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                Picker("Language", selection: $selectedLanguage) {
                    Text("Match note language").tag(RefineLanguagePickerValue.matchNote)
                    ForEach(supportedFixedLocales) { option in
                        Text(option.displayName).tag(RefineLanguagePickerValue.fixedLocale(option.localeIdentifier))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedLanguage) { _, value in
                    persistLanguageSelection(value)
                }

                Text(languageHelpText)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText(for: colorScheme))

                if languageResolution.isUsingFallback,
                   let unsupported = languageResolution.unsupportedSavedLocaleIdentifier {
                    Text("Saved language \(unsupported) is unavailable on this Mac. Refine is using Match note language until you choose another option.")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText(for: colorScheme))
                }
            }
            .listRowBackground(settingsSectionBackground)

            Section {
                Text("Your notes are stored locally on this Mac. Refine runs on-device when available.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText(for: colorScheme))

                Link("Source on GitHub", destination: URL(string: "https://github.com/rafaeltorresng/rasc")!)

                Button("Send Feedback…") {
                    BetaFeedback.open()
                }
            }
            .listRowBackground(settingsSectionBackground)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(20)
        .frame(
            minWidth: 460,
            idealWidth: 500,
            maxWidth: 560,
            minHeight: SettingsWindowPresentation.fittedMinimumHeight(
                visibleHeight: NSScreen.main?.visibleFrame.height ?? 680
            )
        )
        .rascWindowSurface()
        .registersSettingsOpenAction()
        .task {
            refreshLaunchAtLoginState()
            refreshLanguageSettings()
            await refreshRefineStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            selectMode(themeSettings.load())
            refreshLaunchAtLoginState()
            refreshLanguageSettings()
        }
    }

    private func selectMode(_ theme: AppTheme) {
        guard theme != selectedTheme else { return }
        selectedTheme = theme
        customEditingScheme = nil
        themeSettings.save(theme)
        AppThemeApplicator.apply(theme)
    }

    private var customThemeEditor: some View {
        let scheme = customEditingScheme ?? colorScheme
        let otherScheme: ColorScheme = scheme == .dark ? .light : .dark
        let preview = customDraft[scheme].palette(for: scheme)
        let issue = customDraft[scheme].issue(for: scheme) ?? customDraft[otherScheme].issue(for: otherScheme)

        return VStack(alignment: .leading, spacing: 10) {
            Picker("Custom Palette Appearance", selection: Binding(
                get: { customEditingScheme ?? colorScheme },
                set: { customEditingScheme = $0 }
            )) {
                Text("Light").tag(ColorScheme.light)
                Text("Dark").tag(ColorScheme.dark)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 120)

            HStack(spacing: 20) {
                ColorPicker("Background", selection: colorBinding(for: scheme, \.background), supportsOpacity: false)
                ColorPicker("Note Text", selection: colorBinding(for: scheme, \.noteText), supportsOpacity: false)
                Spacer(minLength: 0)
            }
            .id(scheme)
            .onChange(of: scheme) {
                if NSColorPanel.sharedColorPanelExists {
                    NSColorPanel.shared.close()
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("An unfinished thought")
                    .font(.system(size: noteTextSize.points(RascSurfaceMetrics.noteFontSize), weight: .medium))
                Text("A little room to think.")
                    .font(.system(size: noteTextSize.points(13)))
            }
            .foregroundStyle(preview.noteText.map { Color(nsColor: $0) } ?? .primary)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(Color(nsColor: preview.canvas), in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: preview.border), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Palette preview")
            .accessibilityValue("An unfinished thought. A little room to think.")

            HStack {
                Text(issue ?? "Preview")
                    .font(.caption)
                    .foregroundStyle(issue == nil
                        ? palette.secondaryText(for: colorScheme)
                        : palette.destructiveText(for: colorScheme))
                Spacer(minLength: 8)
                Button("Reset Palette") {
                    customDraft = .standard
                    themeStore.applyCustomPalette(customDraft)
                }
                .disabled(customDraft == .standard && themeStore.custom == .standard)
                .help("Restore both the Light and Dark palettes")
                Button("Apply") {
                    themeStore.applyCustomPalette(customDraft)
                }
                .buttonStyle(.borderedProminent)
                .disabled(issue != nil || customDraft == themeStore.custom)
                .accessibilityLabel("Apply Custom Palette")
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .transaction { $0.animation = nil }
    }

    private func colorBinding(for scheme: ColorScheme, _ role: WritableKeyPath<CustomThemeColors, ThemeColor>) -> Binding<CGColor> {
        Binding(
            get: { customDraft[scheme][keyPath: role].nsColor.cgColor },
            set: { color in
                guard let nativeColor = NSColor(cgColor: color), let chosenColor = ThemeColor(nativeColor) else { return }
                customDraft[scheme][keyPath: role] = chosenColor
            }
        )
    }

    private var keyboardShortcutsSection: some View {
        Section {
            shortcutCategory(
                "Global Shortcuts",
                detail: "Available from anywhere on your Mac."
            )

            KeyboardShortcuts.Recorder("Toggle Scratchpad", name: .toggleScratchpad)
                .shortcutValidation { shortcut in
                    GlobalShortcutPolicy.validation(
                        proposed: shortcut,
                        other: .toggleHome,
                        otherTitle: "Toggle Home"
                    )
                }
                .accessibilityHint("Editable global shortcut")
                .frame(maxWidth: .infinity, alignment: .trailing)

            if !GlobalShortcutPolicy.isUsingInitialShortcut(.toggleScratchpad) {
                Button("Restore Default") {
                    restoreGlobalShortcut(
                        .toggleScratchpad,
                        other: .toggleHome,
                        title: "Toggle Scratchpad",
                        otherTitle: "Toggle Home"
                    )
                }
                .accessibilityLabel("Restore Toggle Scratchpad")
                .accessibilityHint("Returns Toggle Scratchpad to its default shortcut")
            }

            KeyboardShortcuts.Recorder("Toggle Home", name: .toggleHome)
                .shortcutValidation { shortcut in
                    GlobalShortcutPolicy.validation(
                        proposed: shortcut,
                        other: .toggleScratchpad,
                        otherTitle: "Toggle Scratchpad"
                    )
                }
                .accessibilityHint("Editable global shortcut")
                .frame(maxWidth: .infinity, alignment: .trailing)

            if !GlobalShortcutPolicy.isUsingInitialShortcut(.toggleHome) {
                Button("Restore Default") {
                    restoreGlobalShortcut(
                        .toggleHome,
                        other: .toggleScratchpad,
                        title: "Toggle Home",
                        otherTitle: "Toggle Scratchpad"
                    )
                }
                .accessibilityLabel("Restore Toggle Home")
                .accessibilityHint("Returns Toggle Home to its default shortcut")
            }

            if let shortcutRestoreMessage {
                Text(shortcutRestoreMessage)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            shortcutCategory(
                "Inside Rasc",
                detail: "New, Search, Refine, the Command Palette, and Keep can be changed. Esc, ⌘W, ⌘, and ⌘Q stay with macOS."
            )

            ForEach(InternalCommand.allCases) { command in
                InternalShortcutEditor(command: command)
            }

            Button("Restore Defaults") {
                InternalShortcutStore.shared.restoreDefaults()
            }
            .accessibilityLabel("Restore inside shortcuts")

            ForEach(RascShortcutCatalog.insideRasc.filter { entry in
                !["new-scratch", "refine", "keep", "search-thoughts", "command-palette"].contains(entry.id)
            }) { entry in
                insideRascShortcutRow(entry)
            }
        } header: {
            Text("Keyboard Shortcuts")
        }
        .id(SettingsNavigation.keyboardShortcutsID)
        .listRowBackground(settingsSectionBackground)
    }

    private func shortcutCategory(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.caption)
                .foregroundStyle(palette.secondaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func insideRascShortcutRow(_ entry: RascShortcutEntry) -> some View {
        LabeledContent {
            Text(entry.shortcut)
                .font(.body.monospaced())
                .foregroundStyle(.primary)
                .layoutPriority(1)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                if let detail = entry.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText(for: colorScheme))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title), \(entry.shortcut)")
        .accessibilityHint(entry.detail.map { "\($0). Not customizable." } ?? "Not customizable.")
    }

    private func restoreGlobalShortcut(
        _ name: KeyboardShortcuts.Name,
        other: KeyboardShortcuts.Name,
        title: String,
        otherTitle: String
    ) {
        if GlobalShortcutPolicy.restoreDefault(name, other: other) {
            shortcutRestoreMessage = nil
        } else {
            shortcutRestoreMessage = "\(title) can't return to its default while \(otherTitle) uses that shortcut."
        }
    }

    private func scrollToKeyboardShortcutsIfNeeded(_ proxy: ScrollViewProxy) {
        guard SettingsNavigation.consumeKeyboardShortcutsRequest() else { return }
        let scroll = {
            proxy.scrollTo(SettingsNavigation.keyboardShortcutsID, anchor: .top)
        }
        if reduceMotion {
            scroll()
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                scroll()
            }
        }
    }

    private var languageHelpText: String {
        switch selectedLanguage {
        case .matchNote:
            "Match note language keeps each note in its original language."
        case .fixedLocale:
            "Refine outputs in the selected language. Protected identifiers, URLs, and technical literals stay unchanged."
        }
    }

    private func updateLaunchAtLogin(_ isEnabled: Bool) {
        do {
            try loginItemController.setEnabled(isEnabled)
            launchAtLoginError = nil
            refreshLaunchAtLoginState()
        } catch {
            refreshLaunchAtLoginState()
            launchAtLoginError = isEnabled
                ? "Couldn't enable Launch at Login. Check System Settings and try again."
                : "Couldn't disable Launch at Login. Try again in System Settings."
        }
    }

    private var settingsSectionBackground: some View {
        RoundedRectangle(cornerRadius: RascSurfaceMetrics.feedbackCornerRadius, style: .continuous)
            .fill(palette.raisedFill(for: colorScheme))
    }

    private func refreshLaunchAtLoginState() {
        loginItemState = loginItemController.state()
        launchAtLogin = loginItemState.isEnabled
    }

    private func refreshLanguageSettings() {
        supportedFixedLocales = supportedLocales.supportedFixedLocaleOptions()
        languageResolution = languageSettings.resolveEffectivePreference()
        selectedLanguage = pickerValue(for: languageResolution.stored)
    }

    private func persistLanguageSelection(_ value: RefineLanguagePickerValue) {
        switch value {
        case .matchNote:
            languageSettings.save(.matchNote)
        case let .fixedLocale(identifier):
            languageSettings.save(.fixedLocale(identifier: identifier))
        }
        languageResolution = languageSettings.resolveEffectivePreference()
    }

    private func pickerValue(for stored: RefineLanguageSettingsStore.StoredPreference) -> RefineLanguagePickerValue {
        switch stored {
        case .matchNote:
            .matchNote
        case let .fixedLocale(identifier):
            .fixedLocale(identifier)
        }
    }

    private func refreshRefineStatus() async {
        let availability = await refinementProvider.availability(
            for: RefinementRequest(
                snapshot: NoteSnapshot(
                    noteID: UUID(),
                    revision: 0,
                    text: "status check"
                )
            )
        )
        refineStatus = RefineStatusDescription.make(from: availability)
    }
}

private struct InternalShortcutEditor: View {
    let command: InternalCommand

    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var store = InternalShortcutStore.shared
    @State private var isRecording = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(command.title) {
                Button(isRecording ? "Type shortcut…" : store.displayString(for: command)) {
                    isRecording = true
                    message = nil
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("\(command.title) shortcut")
                .accessibilityHint(isRecording ? "Type the new shortcut" : "Activate to record a new shortcut")
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText(for: colorScheme))
            }
        }
        .background {
            if isRecording {
                InternalShortcutCapture(
                    onCapture: { event in
                        guard let shortcut = InternalShortcut(event: event) else {
                            message = "Use a key with ⌘, ⌥, or ⌃."
                            isRecording = false
                            return
                        }
                        message = store.assign(shortcut, to: command)
                        isRecording = false
                    },
                    onCancel: {
                        message = nil
                        isRecording = false
                    }
                )
            }
        }
    }
}

private struct InternalShortcutCapture: NSViewRepresentable {
    var onCapture: (NSEvent) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        view.onCapture = onCapture
        view.onCancel = onCancel
        guard view.window?.firstResponder !== view else { return }
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
    }

    final class CaptureView: NSView {
        var onCapture: ((NSEvent) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {
                onCancel?()
                return
            }
            onCapture?(event)
        }
    }
}

/// Miniature swatch of the theme in the current native appearance.
private struct ThemePresetSwatch: View {
    let preset: ThemePreset
    let preview: ThemePalette
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var environmentScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                // A miniature page: canvas, raised sheet, two lines of ink — the three
                // things that distinguish the presets.
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: preview.canvas))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(nsColor: preview.border), lineWidth: 1)
                        }

                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(Color(nsColor: preview.raisedFill))
                        .frame(width: 22, height: 17)
                        .overlay {
                            VStack(spacing: 2.5) {
                                RoundedRectangle(cornerRadius: 0.75, style: .continuous)
                                    .fill(Color(nsColor: preview.noteText ?? preview.secondaryText))
                                    .frame(width: 12, height: 2)
                                RoundedRectangle(cornerRadius: 0.75, style: .continuous)
                                    .fill(Color(nsColor: preview.metadataText))
                                    .frame(width: 8, height: 2)
                            }
                        }
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(
                                palette.focus(for: environmentScheme),
                                lineWidth: contrast == .increased ? 2.5 : 1.5
                            )
                            .padding(-3)
                    }
                }
                .frame(width: 40, height: 40)

                Text(preset.displayName)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(
                        isSelected
                            ? Color.primary
                            : palette.metadataText(for: environmentScheme)
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.displayName) theme")
        .accessibilityHint(preset.caption)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .help(preset.caption)
    }
}
