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
        case .unavailable(.unsupportedEnvironment), .unavailable(.unknown):
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

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTheme: AppTheme = .system
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

    init(
        refinementProvider: any RefinementProvider = FoundationModelsRefinementProvider(),
        loginItemController: LoginItemController = LoginItemController(),
        languageSettings: RefineLanguageSettingsStore = RefineLanguageSettingsStore(),
        themeSettings: AppThemeSettingsStore = AppThemeSettingsStore(),
        supportedLocales: any RefineSupportedLocaleDiscovering = RefineSupportedLocales()
    ) {
        self.refinementProvider = refinementProvider
        self.loginItemController = loginItemController
        self.languageSettings = languageSettings
        self.themeSettings = themeSettings
        self.supportedLocales = supportedLocales
    }

    var body: some View {
        Form {
            Section("General") {
                Picker("Theme", selection: $selectedTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedTheme) { _, theme in
                    themeSettings.save(theme)
                    AppThemeApplicator.apply(theme)
                }

                KeyboardShortcuts.Recorder(
                    "Global shortcut:",
                    name: .toggleScratchpad
                )

                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, isEnabled in
                        updateLaunchAtLogin(isEnabled)
                    }

                if loginItemState == .requiresApproval {
                    HStack {
                        Text("Launch at Login needs approval in System Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items Settings") {
                            loginItemController.openSystemSettings()
                        }
                    }
                }

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .listRowBackground(settingsSectionBackground)

            Section("Refine") {
                LabeledContent(refineStatus.headline) {
                    Text(refineStatus.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
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
                    .foregroundStyle(.secondary)

                if languageResolution.isUsingFallback,
                   let unsupported = languageResolution.unsupportedSavedLocaleIdentifier {
                    Text("Saved language \(unsupported) is unavailable on this Mac. Refine is using Match note language until you choose another option.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(settingsSectionBackground)

            Section {
                Text("Your notes are stored locally on this Mac. Refine runs on-device when available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Send Feedback…") {
                    BetaFeedback.open()
                }
            }
            .listRowBackground(settingsSectionBackground)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(20)
        .frame(width: 460)
        .rascWindowSurface()
        .registersSettingsOpenAction()
        .task {
            selectedTheme = themeSettings.load()
            refreshLaunchAtLoginState()
            refreshLanguageSettings()
            await refreshRefineStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            selectedTheme = themeSettings.load()
            refreshLaunchAtLoginState()
            refreshLanguageSettings()
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
            .fill(RascSurfacePalette.raisedFill(for: colorScheme))
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
