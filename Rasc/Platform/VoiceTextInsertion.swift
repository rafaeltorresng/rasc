import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Deliberate voice workflow selected by the user.
enum VoiceCaptureIntent: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Save an unfinished thought and open Scratchpad.
    case scratchpad
    /// Dictate directly into the focused app or clipboard without opening Scratchpad.
    case dictate

    var id: String { rawValue }
}

/// Primary delivery target when invoking Dictate.
enum VoiceDictationDelivery: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Insert into the currently focused text field, falling back to clipboard.
    case insertAtCursor
    /// Copy directly to the clipboard without stealing focus.
    case clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .insertAtCursor: "Insert at cursor"
        case .clipboard: "Copy to clipboard"
        }
    }

    var detail: String {
        switch self {
        case .insertAtCursor:
            "Type into the focused text field when allowed, falling back to the clipboard if unavailable."
        case .clipboard:
            "Copy the transcript straight to the clipboard without opening Rasc or moving focus."
        }
    }
}

/// Where a finished Voice Capture transcript is delivered (legacy preference key).
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
    enum Result: Equatable, Sendable {
        /// The app accepted an AXSelectedText insertion at the cursor.
        case inserted
        /// Text was placed on the clipboard instead.
        case copiedToClipboard(Reason)
        /// Secure input or a secure text field is active; nothing was inserted or copied.
        case blockedBySecureInput
    }

    enum Reason: Equatable, Sendable {
        case noAccessibilityPermission
        case noTargetApplication
        case noFocusedTextField
        case insertionFailed
        case focusChanged
        case emptyText
    }

    // AX attribute keys as strings; the AppKit constants are shared mutable state
    // under Swift 6 concurrency checking and are otherwise identical.
    private static let focusedElementAttribute = "AXFocusedUIElement"
    private static let selectedTextAttribute = "AXSelectedText"
    private static let roleAttribute = "AXRole"
    private static let subroleAttribute = "AXSubrole"
    private static let valueAttribute = "AXValue"
    private static let selectedTextRangeAttribute = "AXSelectedTextRange"
    private static let manualAccessibilityAttribute = "AXManualAccessibility"
    private static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface"
    private static let secureTextFieldIdentifier = "AXSecureTextField"
    private static let smartSpaceOpeningCharacters: Set<Character> = [
        "(", "[", "{", "\"", "'", "“", "‘", "/", "-", "\n", "\t"
    ]

    @MainActor
    static func insert(
        _ text: String,
        target: NSRunningApplication?,
        pasteboard: NSPasteboard = .general,
        isTrusted: @Sendable () -> Bool = { AXIsProcessTrusted() },
        isSecureInputEnabled: @Sendable () -> Bool = { IsSecureEventInputEnabled() }
    ) -> Result {
        guard !text.isEmpty else {
            return .copiedToClipboard(.emptyText)
        }
        if isSecureInputEnabled() {
            return .blockedBySecureInput
        }
        guard isTrusted() else {
            copy(text, to: pasteboard)
            return .copiedToClipboard(.noAccessibilityPermission)
        }
        guard let app = target, !app.isTerminated, app != .current else {
            copy(text, to: pasteboard)
            return .copiedToClipboard(.noTargetApplication)
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let element: AXUIElement?
        if let direct = focusedElement(of: appElement) {
            element = direct
        } else {
            // Electron and Chromium apps often defer exposing their AX tree until requested.
            AXUIElementSetAttributeValue(appElement, manualAccessibilityAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(appElement, enhancedUserInterfaceAttribute as CFString, kCFBooleanTrue)
            element = focusedElement(of: appElement)
        }
        guard let element else {
            copy(text, to: pasteboard)
            return .copiedToClipboard(.noFocusedTextField)
        }
        if isFocusedElementSecure(element) {
            return .blockedBySecureInput
        }
        let snapshot = textSnapshot(of: element)
        let preparedText = textWithSmartLeadingSpace(text, precedingCharacter: precedingCharacter(in: snapshot))
        if setSelectedText(preparedText, on: element, beforeSnapshot: snapshot)
            || setSelectedTextViaValue(preparedText, on: element, before: snapshot) {
            return .inserted
        }
        copy(text, to: pasteboard)
        return .copiedToClipboard(.insertionFailed)
    }

    @discardableResult
    @MainActor
    static func copy(_ text: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// Inserts `text` at the current caret when `window` holds an editable `NSTextView`
    /// first responder (such as an in-app SwiftUI `TextField` field editor).
    @MainActor
    static func insertIntoWindowEditor(_ text: String, window: NSWindow?) -> Bool {
        guard !text.isEmpty,
              let window,
              let textView = window.firstResponder as? NSTextView,
              textView.isEditable
        else {
            return false
        }
        let range = textView.selectedRange()
        let preceding = precedingCharacter(in: textView.string, beforeUTF16Location: range.location)
        let prepared = textWithSmartLeadingSpace(text, precedingCharacter: preceding)
        textView.insertText(prepared, replacementRange: range)
        return true
    }

    static func textWithSmartLeadingSpace(_ text: String, precedingCharacter: Character?) -> String {
        guard !text.isEmpty,
              let prev = precedingCharacter,
              !prev.isWhitespace,
              !smartSpaceOpeningCharacters.contains(prev),
              let first = text.first,
              first.isLetter || first.isNumber
        else {
            return text
        }
        return " " + text
    }

    private struct AXTextSnapshot: Equatable {
        let value: String?
        let rangeLocation: Int?
        let rangeLength: Int?

        var isReadable: Bool {
            value != nil && rangeLocation != nil && rangeLength != nil
        }
    }

    private static func focusedElement(of appElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(appElement, focusedElementAttribute as CFString, &value)
        guard status == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // `value` is an AXUIElementRef delivered as a CFTypeRef.
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func isFocusedElementSecure(_ element: AXUIElement) -> Bool {
        for attribute in [roleAttribute, subroleAttribute] {
            var value: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            if status == .success, let stringValue = value as? String, stringValue == secureTextFieldIdentifier {
                return true
            }
        }
        return false
    }

    private static func textSnapshot(of element: AXUIElement) -> AXTextSnapshot {
        var rawValue: CFTypeRef?
        let textValue: String? =
            if AXUIElementCopyAttributeValue(element, valueAttribute as CFString, &rawValue) == .success {
                rawValue as? String
            } else {
                nil
            }

        var rawRange: CFTypeRef?
        var location: Int?
        var length: Int?
        if AXUIElementCopyAttributeValue(element, selectedTextRangeAttribute as CFString, &rawRange) == .success,
           let rawRange,
           CFGetTypeID(rawRange) == AXValueGetTypeID() {
            let axValue = unsafeDowncast(rawRange, to: AXValue.self)
            var range = CFRange()
            if AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) {
                location = range.location
                length = range.length
            }
        }

        return AXTextSnapshot(value: textValue, rangeLocation: location, rangeLength: length)
    }

    private static func precedingCharacter(in snapshot: AXTextSnapshot) -> Character? {
        guard let value = snapshot.value, let location = snapshot.rangeLocation else { return nil }
        return precedingCharacter(in: value, beforeUTF16Location: location)
    }

    private static func precedingCharacter(in string: String, beforeUTF16Location location: Int) -> Character? {
        guard location > 0 else { return nil }
        let utf16 = string.utf16
        guard location <= utf16.count else { return nil }
        let targetIndex = utf16.index(utf16.startIndex, offsetBy: location)
        guard let scalarIndex = targetIndex.samePosition(in: string), scalarIndex > string.startIndex else {
            return nil
        }
        return string[string.index(before: scalarIndex)]
    }

    private static func setSelectedText(_ text: String, on element: AXUIElement, beforeSnapshot: AXTextSnapshot) -> Bool {
        var settable: DarwinBoolean = false
        let settableStatus = AXUIElementIsAttributeSettable(element, selectedTextAttribute as CFString, &settable)
        guard settableStatus == .success, settable.boolValue else { return false }
        let status = AXUIElementSetAttributeValue(element, selectedTextAttribute as CFString, text as CFTypeRef)
        guard status == .success else { return false }

        if !text.isEmpty, beforeSnapshot.isReadable {
            let afterSnapshot = textSnapshot(of: element)
            if afterSnapshot.isReadable, afterSnapshot == beforeSnapshot {
                return false
            }
        }
        return true
    }

    /// Some editors (notably Chromium/Electron and a few SwiftUI fields) expose
    /// a focused element but do not implement `AXSelectedText`. Replace the
    /// freshly read selection in `AXValue` instead, then move the caret after
    /// the inserted text. This stays inside Accessibility and never posts
    /// synthetic keystrokes.
    private static func setSelectedTextViaValue(
        _ text: String,
        on element: AXUIElement,
        before snapshot: AXTextSnapshot
    ) -> Bool {
        guard let value = snapshot.value,
              let location = snapshot.rangeLocation,
              let length = snapshot.rangeLength,
              location >= 0, length >= 0
        else {
            return false
        }
        let utf16 = value.utf16
        guard location <= utf16.count, length <= utf16.count - location else { return false }
        let start = utf16.index(utf16.startIndex, offsetBy: location)
        let end = utf16.index(start, offsetBy: length)
        guard let startIndex = start.samePosition(in: value),
              let endIndex = end.samePosition(in: value)
        else {
            return false
        }
        let replaced = String(value[value.startIndex..<startIndex]) + text + String(value[endIndex..<value.endIndex])
        guard AXUIElementSetAttributeValue(element, valueAttribute as CFString, replaced as CFTypeRef) == .success,
              textSnapshot(of: element).value == replaced
        else {
            return false
        }
        var caret = CFRange(location: location + text.utf16.count, length: 0)
        if let rangeValue = withUnsafeMutablePointer(to: &caret, { AXValueCreate(.cfRange, $0) }) {
            AXUIElementSetAttributeValue(element, selectedTextRangeAttribute as CFString, rangeValue)
        }
        return true
    }
}
