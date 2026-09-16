import Foundation
import ServiceManagement

enum LoginItemError: Error, Equatable {
    case registrationFailed
    case unregistrationFailed
}

enum LoginItemState: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval

    static func make(from status: SMAppService.Status) -> Self {
        switch status {
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notRegistered, .notFound:
            .disabled
        @unknown default:
            .disabled
        }
    }

    var isEnabled: Bool {
        self != .disabled
    }
}

struct LoginItemController: Sendable {
    func status() -> SMAppService.Status {
        SMAppService.mainApp.status
    }

    func state() -> LoginItemState {
        LoginItemState.make(from: status())
    }

    func isEnabled() -> Bool {
        state().isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard !isEnabled() else { return }
            do {
                try SMAppService.mainApp.register()
            } catch {
                throw LoginItemError.registrationFailed
            }
        } else {
            guard isEnabled() else { return }
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                throw LoginItemError.unregistrationFailed
            }
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
