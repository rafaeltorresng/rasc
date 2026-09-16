import AppKit

/// NSPanel that can receive keyboard focus while remaining a non-activating utility surface.
@MainActor
final class ScratchpadPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { false }

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
}
