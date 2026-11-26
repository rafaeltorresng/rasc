import AppKit
import ApplicationServices
import Foundation

/// Where a finished Voice Capture transcript is delivered.
enum VoiceCaptureOutput: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Save an unfinished thought and open Scratchpad. The historical default.
    case scratchpad
    /// Copy to the clipboard without opening Scratchpad or stealing focus.
    case clipboard
    /// Insert into the currently focused text field, falling back to clipboard.
    case insertAtCursor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scratchpad: "Capture to Scratchpad"
        case .clipboard: "Copy to Clipboard"
        case .insertAtCursor: "Insert at Cursor"
        }
    }

    var detail: String {
        switch self {
        case .scratchpad:
            "Save as an unfinished thought and open Scratchpad."
        case .clipboard:
            "Copy the transcript without opening Scratchpad or moving focus."
        case .insertAtCursor:
            "Insert into the focused text field. Falls back to the clipboard if insertion isn't available."
        }
    }
}

/// Direct text insertion into another application through the Accessibility API.
/// Never activates or steals focus; never posts synthetic keystrokes.
enum VoiceTextInsertion {
    enum Result: Equatable {
        /// The app accepted an AXSelectedText insertion at the cursor.
        case inserted
        /// Text was placed on the clipboard instead.
        case copiedToClipboard(Reason)
    }

    enum Reason: Equatable {
        case noAccessibilityPermission
        case noTargetApplication
        case noFocusedTextField
        case insertionFailed
        case emptyText
    }

    // AX attribute keys as strings; the AppKit constants are shared mutable state
    // under Swift 6 concurrency checking and are otherwise identical.
    private static let focusedElementAttribute = "AXFocusedUIElement"
    private static let selectedTextAttribute = "AXSelectedText"

    @MainActor
    static func insert(
        _ text: String,
        target: NSRunningApplication?,
        pasteboard: NSPasteboard = .general
    ) -> Result {
        guard !text.isEmpty else {
            return .copiedToClipboard(.emptyText)
        }
        guard AXIsProcessTrusted() else {
            copy(text, to: pasteboard)
            return .copiedToClipboard(.noAccessibilityPermission)
        }
        guard let app = target, !app.isTerminated, app != .current else {
            copy(text, to: pasteboard)
            return .copiedToClipboard(.noTargetApplication)
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let element = focusedElement(of: appElement) else {
            copy(text, to: pasteboard)
            return .copiedToClipboard(.noFocusedTextField)
        }
        if setSelectedText(text, on: element) {
            return .inserted
        }
        copy(text, to: pasteboard)
        return .copiedToClipboard(.insertionFailed)
    }

    @MainActor
    static func copy(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func focusedElement(of appElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(appElement, focusedElementAttribute as CFString, &value)
        guard status == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // `value` is an AXUIElementRef delivered as a CFTypeRef.
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func setSelectedText(_ text: String, on element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        let settableStatus = AXUIElementIsAttributeSettable(element, selectedTextAttribute as CFString, &settable)
        guard settableStatus == .success, settable.boolValue else { return false }
        let status = AXUIElementSetAttributeValue(element, selectedTextAttribute as CFString, text as CFTypeRef)
        return status == .success
    }
}
