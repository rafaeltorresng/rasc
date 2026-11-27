import AppKit
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

enum SettingsTab: String, CaseIterable, Hashable {
    case general
    case shortcuts
    case voice
    case refine

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .voice: "Voice"
        case .refine: "Refine"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "command"
        case .voice: "waveform"
        case .refine: "sparkles"
        }
    }
}

struct SettingsView: View {
    private let refinementProvider: any RefinementProvider
    private let loginItemController: LoginItemController
    private let languageSettings: RefineLanguageSettingsStore
    private let themeSettings: AppThemeSettingsStore
    private let supportedLocales: any RefineSupportedLocaleDiscovering

    @ObservedObject private var themeStore: ThemeStore
    @ObservedObject private var voiceCapture = VoiceCapture.shared
    @ObservedObject private var globalShortcuts = GlobalShortcutStore.shared
    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(NoteTextSize.preferenceKey) private var noteTextSize: NoteTextSize = .standard

    @State private var selectedTab: SettingsTab
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
    @State private var showStandardShortcuts = false

    init(
        refinementProvider: any RefinementProvider = FoundationModelsRefinementProvider(),
        loginItemController: LoginItemController = LoginItemController(),
        languageSettings: RefineLanguageSettingsStore = RefineLanguageSettingsStore(),
        themeSettings: AppThemeSettingsStore = AppThemeSettingsStore(),
        themeStore: ThemeStore = .shared,
        supportedLocales: any RefineSupportedLocaleDiscovering = RefineSupportedLocales(),
        initialTab: SettingsTab = .general
    ) {
        self.refinementProvider = refinementProvider
        self.loginItemController = loginItemController
        self.languageSettings = languageSettings
        self.themeSettings = themeSettings
        _selectedTheme = State(initialValue: themeSettings.load())
        self.themeStore = themeStore
        _customDraft = State(initialValue: themeStore.custom)
        self.supportedLocales = supportedLocales
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsTabBar
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Divider()
                .overlay(palette.border(for: colorScheme).opacity(0.45))

            Group {
                switch selectedTab {
                case .general:
                    generalTab
                case .shortcuts:
                    shortcutsTab
                case .voice:
                    voiceTab
                case .refine:
                    refineTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: 500,
            idealWidth: 540,
            maxWidth: 600,
            minHeight: SettingsWindowPresentation.fittedMinimumHeight(
                visibleHeight: NSScreen.main?.visibleFrame.height ?? 680
            )
        )
        .rascWindowSurface()
        .registersSettingsOpenAction()
        .onAppear {
            handlePendingNavigation()
        }
        .onReceive(NotificationCenter.default.publisher(for: SettingsNavigation.revealNotification)) { _ in
            handlePendingNavigation()
        }
        .task {
            refreshLaunchAtLoginState()
            refreshLanguageSettings()
            await refreshRefineStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            selectMode(themeSettings.load())
            refreshLaunchAtLoginState()
            refreshLanguageSettings()
            voiceCapture.refreshAccessibilityStatus()
            Task { await refreshRefineStatus() }
        }
    }

    private var settingsTabBar: some View {
        HStack(spacing: 6) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                let isSelected = (selectedTab == tab)
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 12, weight: .medium))
                        Text(tab.title)
                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    }
                    .foregroundStyle(
                        isSelected
                            ? palette.noteText(for: colorScheme)
                            : palette.secondaryText(for: colorScheme)
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(palette.selectionFill(for: colorScheme))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(palette.border(for: colorScheme).opacity(0.65), lineWidth: 1)
                                }
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
    }

    // MARK: - General

    private var generalTab: some View {
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
                                preset: preset,
                                scheme: colorScheme,
                                custom: themeStore.custom
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

            Section("Startup") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { updateLaunchAtLogin($0) }
                ))

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

            Section("About & Privacy") {
                Text("Your thoughts live locally in SQLite on this Mac. Capture works instantaneously without AI.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText(for: colorScheme))

                Link("Source on GitHub", destination: URL(string: "https://github.com/rafaeltorresng/rasc")!)

                Button("Welcome Guide…") {
                    NotificationCenter.default.post(name: OnboardingCoordinator.replayNotification, object: nil)
                }

                Button("Send Feedback…") {
                    BetaFeedback.open()
                }
            }
            .listRowBackground(settingsSectionBackground)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Shortcuts

    private var shortcutsTab: some View {
        Form {
            Section {
                UnifiedShortcutRow(action: .toggleScratchpad)
                UnifiedShortcutRow(action: .toggleHome)
                if VoiceCapture.isSupported {
                    UnifiedShortcutRow(action: .voiceScratchpad, showsRestoreDefault: false)
                    UnifiedShortcutRow(action: .voiceDictate, showsRestoreDefault: false)

                    if !voiceCapture.enabled &&
                        (globalShortcuts.trigger(for: .voiceScratchpad) != nil ||
                         globalShortcuts.trigger(for: .voiceDictate) != nil) {
                        HStack {
                            Text("Voice shortcuts stay inactive while Voice is turned off.")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText(for: colorScheme))
                            Spacer()
                            Button("Open Voice Tab") {
                                selectedTab = .voice
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                }

                if anyGlobalShortcutUsesModifier && !voiceCapture.hasAccessibilityAccess {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Accessibility access required for single-modifier triggers outside Rasc.")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText(for: colorScheme))
                        HStack(spacing: 8) {
                            Button("Allow Rasc…") {
                                voiceCapture.requestAccessibilityForInsertion()
                            }
                            Button("Open System Settings…") {
                                voiceCapture.openAccessibilitySettings()
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Global")
            } footer: {
                Text("Works anywhere on your Mac. Click a field and press a key shortcut or tap a single modifier key (⌥, ⌃, ⇧, or ⌘).")
            }
            .id(SettingsNavigation.keyboardShortcutsID)
            .listRowBackground(settingsSectionBackground)

            Section {
                ForEach(InternalCommand.allCases) { command in
                    InternalShortcutEditor(command: command)
                }

                Button("Restore Defaults") {
                    InternalShortcutStore.shared.restoreDefaults()
                }
                .accessibilityLabel("Restore inside shortcuts")

                DisclosureGroup("System & Navigation Shortcuts", isExpanded: $showStandardShortcuts) {
                    ForEach(RascShortcutCatalog.insideRasc.filter { entry in
                        !["new-scratch", "refine", "keep", "search-thoughts", "command-palette"].contains(entry.id)
                    }) { entry in
                        insideRascShortcutRow(entry)
                    }
                }
            } header: {
                Text("Inside Rasc")
            } footer: {
                Text("Esc, ⌘W, ⌘,, ⌘Q, ⌘H, ⌘M, and editing shortcuts are reserved by macOS.")
            }
            .listRowBackground(settingsSectionBackground)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var anyGlobalShortcutUsesModifier: Bool {
        GlobalShortcutAction.allCases.contains { action in
            globalShortcuts.trigger(for: action)?.needsAccessibilityPermission == true
        }
    }

    // MARK: - Voice

    private var voiceTab: some View {
        Form {
            VoiceCaptureSettings(capture: voiceCapture)
                .listRowBackground(settingsSectionBackground)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .id(SettingsNavigation.voiceCaptureID)
    }

    // MARK: - Refine

    private var refineTab: some View {
        Form {
            Section("Apple Intelligence") {
                LabeledContent(refineStatus.headline) {
                    Text(refineStatus.detail)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText(for: colorScheme))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(settingsSectionBackground)

            Section("Output Language") {
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
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Helpers

    private func handlePendingNavigation() {
        guard let target = SettingsNavigation.consumeRevealRequest() else { return }
        switch target {
        case SettingsNavigation.keyboardShortcutsID:
            selectedTab = .shortcuts
        case SettingsNavigation.voiceCaptureID:
            selectedTab = .voice
        default:
            break
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
        selectedLanguage = languageResolution.isUsingFallback
            ? .matchNote
            : pickerValue(for: languageResolution.stored)
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

@MainActor
private final class InternalShortcutRecorderModel: ObservableObject {
    @Published private(set) var isRecording = false
    @Published var errorMessage: String?

    private static weak var activeRecorder: InternalShortcutRecorderModel?

    private let command: InternalCommand
    private let store: InternalShortcutStore
    private nonisolated(unsafe) var monitor: Any?
    private nonisolated(unsafe) var resignObserver: (any NSObjectProtocol)?
    private weak var anchorView: NSView?

    init(command: InternalCommand, store: InternalShortcutStore = .shared) {
        self.command = command
        self.store = store
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    func attachAnchor(_ view: NSView) {
        anchorView = view
    }

    func toggle() {
        if isRecording {
            cancel()
        } else {
            begin()
        }
    }

    func begin() {
        if let active = Self.activeRecorder, active !== self {
            active.cancel()
        }
        endMonitor()
        Self.activeRecorder = self
        errorMessage = nil
        isRecording = true
        GlobalShortcutRecordingSuspension.begin()

        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            let consume = MainActor.assumeIsolated {
                self?.processEvent(event) ?? false
            }
            return consume ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cancel()
            }
        }
    }

    func cancel() {
        endMonitor()
        isRecording = false
    }

    private func processEvent(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        switch event.type {
        case .keyDown:
            if event.keyCode == 53,
               event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                errorMessage = nil
                cancel()
                return true
            }
            guard let shortcut = InternalShortcut(event: event) else {
                errorMessage = "Use a key with ⌘, ⌥, or ⌃."
                cancel()
                return true
            }
            errorMessage = store.assign(shortcut, to: command)
            cancel()
            return true
        case .leftMouseDown, .rightMouseDown:
            if let anchorView, event.window === anchorView.window {
                let point = anchorView.convert(event.locationInWindow, from: nil)
                if anchorView.bounds.contains(point) {
                    return false
                }
            }
            cancel()
            return false
        default:
            return false
        }
    }

    private func endMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if Self.activeRecorder === self {
            Self.activeRecorder = nil
            GlobalShortcutRecordingSuspension.end()
        }
    }
}

private struct InternalShortcutEditor: View {
    let command: InternalCommand

    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var store = InternalShortcutStore.shared
    @StateObject private var model: InternalShortcutRecorderModel

    init(command: InternalCommand) {
        self.command = command
        _model = StateObject(wrappedValue: InternalShortcutRecorderModel(command: command))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(command.title) {
                Button(model.isRecording ? "Type shortcut…" : store.displayString(for: command)) {
                    model.toggle()
                }
                .buttonStyle(.bordered)
                .background(InternalRecorderAnchorView { view in
                    model.attachAnchor(view)
                })
                .accessibilityLabel("\(command.title) shortcut")
                .accessibilityHint(model.isRecording ? "Type the new shortcut, or Escape to cancel" : "Activate to record a new shortcut")
            }
            if let message = model.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText(for: colorScheme))
            }
        }
        .onDisappear {
            model.cancel()
        }
    }
}

private struct InternalRecorderAnchorView: NSViewRepresentable {
    let onAttach: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            onAttach(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        onAttach(nsView)
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
