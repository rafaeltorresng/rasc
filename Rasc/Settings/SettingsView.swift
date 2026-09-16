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

struct SettingsView: View {
    private let refinementProvider: any RefinementProvider
    private let loginItemController: LoginItemController

    @State private var launchAtLogin = false
    @State private var loginItemState = LoginItemState.disabled
    @State private var launchAtLoginError: String?
    @State private var refineStatus = RefineStatusDescription(
        headline: "Checking…",
        detail: "Checking Refine availability."
    )

    init(
        refinementProvider: any RefinementProvider = FoundationModelsRefinementProvider(),
        loginItemController: LoginItemController = LoginItemController()
    ) {
        self.refinementProvider = refinementProvider
        self.loginItemController = loginItemController
    }

    var body: some View {
        Form {
            Section("General") {
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

            Section("Refine") {
                LabeledContent(refineStatus.headline) {
                    Text(refineStatus.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }

            Section {
                Text("Your notes are stored locally on this Mac. Refine runs on-device when available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460)
        .task {
            refreshLaunchAtLoginState()
            await refreshRefineStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLaunchAtLoginState()
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

    private func refreshLaunchAtLoginState() {
        loginItemState = loginItemController.state()
        launchAtLogin = loginItemState.isEnabled
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
