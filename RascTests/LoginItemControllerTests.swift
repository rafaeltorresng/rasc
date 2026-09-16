import ServiceManagement
import Testing
@testable import Rasc

struct LoginItemControllerTests {
    @Test
    func requiresApprovalRemainsDistinctFromEnabled() {
        #expect(LoginItemState.make(from: .requiresApproval) == .requiresApproval)
        #expect(LoginItemState.make(from: .enabled) == .enabled)
        #expect(LoginItemState.make(from: .notRegistered) == .disabled)
    }

    @Test
    func reflectsRegisteredServiceStatus() {
        let controller = LoginItemController()
        let status = controller.status()

        switch status {
        case .enabled, .requiresApproval:
            #expect(controller.isEnabled())
        case .notRegistered, .notFound:
            #expect(!controller.isEnabled())
        @unknown default:
            #expect(Bool(false), "Unexpected SMAppService status")
        }
    }

    @Test
    func disablingWhenNotRegisteredDoesNotThrow() throws {
        let controller = LoginItemController()
        guard !controller.isEnabled() else { return }

        try controller.setEnabled(false)
        #expect(!controller.isEnabled())
    }
}
