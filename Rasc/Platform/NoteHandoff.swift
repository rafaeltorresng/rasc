import AppKit

enum NoteHandoff {
    static func copyPlainText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @MainActor
    static func presentSharePicker(for text: String, relativeTo view: NSView) {
        let picker = NSSharingServicePicker(items: [text])
        picker.show(
            relativeTo: view.bounds,
            of: view,
            preferredEdge: .minY
        )
    }
}
