import Foundation

/// A separate Undo target lets a visible Undo button consume precisely its own
/// registration without removing editor or Refine history from the same session.
@MainActor
final class DiscardUndoRegistration {
    private weak var manager: UndoManager?
    private let actionName: String
    private let perform: @MainActor () -> Void

    init(manager: UndoManager, actionName: String = "Discard Thought", perform: @escaping @MainActor () -> Void) {
        self.manager = manager
        self.actionName = actionName
        self.perform = perform
    }

    func register() {
        manager?.registerUndo(withTarget: self) { registration in registration.perform() }
        manager?.setActionName(actionName)
    }

    func invalidate() {
        manager?.removeAllActions(withTarget: self)
    }
}
