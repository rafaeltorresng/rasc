import AppKit

/// NSPanel that can receive keyboard focus while remaining a non-activating utility surface.
@MainActor
final class ScratchpadPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { false }

    /// Invoked on each keyDown before the responder chain. Returning true consumes
    /// the event. The panel uses this to drive refinement-preview navigation,
    /// which controls in the responder chain (the comparison picker's segmented
    /// control) would otherwise swallow.
    var keyDownHandler: ((NSEvent) -> Bool)?

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyDownHandler?(event) == true {
            return
        }
        super.sendEvent(event)
    }
}
