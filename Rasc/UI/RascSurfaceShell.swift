import AppKit
import SwiftUI

enum RascSurfaceLayout {
    static let horizontalInset: CGFloat = 20
    static let topInset: CGFloat = 2
    static let orbSize: CGFloat = 20
    static let orbToAccessoryGap: CGFloat = 9
    static let scratchpadContentGap: CGFloat = 14
    static let scratchpadEmptySupportingGap: CGFloat = 8
    /// Structural separation between chrome and body — spacing only, no rule line.
    static let scratchpadChromeToBodyGap: CGFloat = 8
    static let scratchpadChromeBottomPadding: CGFloat = 10
    static let scratchpadEditorContentTopPadding: CGFloat = 12
    /// Nudges the NSTextView caret to the same cap line as the SwiftUI empty-state prompt.
    static let scratchpadEditorCaretTopInset: CGFloat = 3
    static let transientHeaderBodyGap: CGFloat = 8
    static let bottomInset: CGFloat = 12
    static let textContainerHorizontalInset: CGFloat = 5
    static let searchFieldHeight: CGFloat = 38
    static let searchFieldCornerRadius: CGFloat = 11
    static let listRowCornerRadius: CGFloat = 10
    static let listRowHorizontalPadding: CGFloat = 10
    static let listRowSpacing: CGFloat = 2
    static let listRowVerticalPadding: CGFloat = 10
    static let commandRowMinHeight: CGFloat = 50
    static let searchRowMinHeight: CGFloat = 56

    static var noteTextLeadingInset: CGFloat {
        horizontalInset + textContainerHorizontalInset
    }

    /// Top inset for editor text below the scratchpad chrome row.
    static var scratchpadEditorTopPadding: CGFloat {
        scratchpadEditorContentTopPadding
    }

    static var scratchpadChromeHeight: CGFloat {
        topInset + orbSize + scratchpadChromeBottomPadding
    }

    /// Authoritative top-leading orb anchor shared across Scratchpad, Search, and Command Palette.
    static var orbLeading: CGFloat { horizontalInset }
    static var orbTop: CGFloat { topInset }

    /// Raises the search field so it centers on the orb; tuned below full geometric centering.
    static var searchFieldOrbVerticalOffset: CGFloat {
        (searchFieldHeight - orbSize) / 2 - 3
    }
}

/// Top-anchored header row: orb at `orbLeading`/`orbTop`, accessory beside it.
struct RascSurfaceOrbHeaderRow<Accessory: View>: View {
    let orbState: RascOrbState
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .top, spacing: RascSurfaceLayout.orbToAccessoryGap) {
            RascOrb(state: orbState, size: .inline, decorative: true)
                .frame(
                    width: RascSurfaceLayout.orbSize,
                    height: RascSurfaceLayout.orbSize,
                    alignment: .topLeading
                )

            accessory()
        }
        .padding(.leading, RascSurfaceLayout.orbLeading)
        .padding(.trailing, RascSurfaceLayout.horizontalInset)
        .padding(.top, RascSurfaceLayout.orbTop)
    }
}

private struct RascTransientListRowModifier: ViewModifier {
    let isSelected: Bool
    let minHeight: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, RascSurfaceLayout.listRowHorizontalPadding)
            .padding(.vertical, RascSurfaceLayout.listRowVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .background {
                if isSelected {
                    RascTransientSelectionBackground(
                        cornerRadius: RascSurfaceLayout.listRowCornerRadius
                    )
                }
            }
            .contentShape(Rectangle())
    }
}

extension View {
    func rascTransientListRow(isSelected: Bool, minHeight: CGFloat) -> some View {
        modifier(RascTransientListRowModifier(isSelected: isSelected, minHeight: minHeight))
    }
}

/// Keyboard command the shared transient text field forwards to its owner.
enum RascTransientFieldCommand: Equatable {
    case moveUp
    case moveDown
    case execute
    case close

    init?(commandSelector: Selector) {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            self = .moveUp
        case #selector(NSResponder.moveDown(_:)):
            self = .moveDown
        case #selector(NSResponder.insertNewline(_:)):
            self = .execute
        case #selector(NSResponder.cancelOperation(_:)):
            self = .close
        default:
            return nil
        }
    }
}

/// Shared single-line input for the transient surfaces. Search finds notes,
/// Commands runs actions — both fields share the same shell, focus behavior and
/// keyboard grammar.
struct RascTransientInputTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let focusRequest: Int
    let placeholder: String
    let accessibilityLabel: String
    let onCommand: (RascTransientFieldCommand) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 15)
        textField.placeholderString = placeholder
        textField.setAccessibilityLabel(accessibilityLabel)
        textField.cell?.usesSingleLineMode = true
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self

        if textField.stringValue != text {
            textField.stringValue = text
        }

        context.coordinator.focus(textField, for: focusRequest)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RascTransientInputTextField
        private var fulfilledFocusRequest: Int?

        init(parent: RascTransientInputTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            if let textField = notification.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard let command = RascTransientFieldCommand(commandSelector: commandSelector) else {
                return false
            }
            parent.onCommand(command)
            return true
        }

        func focus(_ textField: NSTextField, for request: Int) {
            guard fulfilledFocusRequest != request else { return }

            DispatchQueue.main.async { [weak self, weak textField] in
                guard let self, let textField, let window = textField.window else { return }
                window.makeFirstResponder(textField)
                fulfilledFocusRequest = request
                parent.isFocused = window.firstResponder === textField.currentEditor()
                    || window.firstResponder === textField
            }
        }
    }
}

/// Content-driven sizing for the transient (Search / Command Palette) panel.
/// Keeps the compact keyboard-first feel: one or two results never leave a
/// large empty panel behind. Transient modes may go below the editor's
/// minimum height; the window `minSize` follows the active surface.
enum RascTransientPanelSizing {
    /// Orb row plus the trailing gap below it.
    static let headerHeight: CGFloat = 45
    static let bottomInset: CGFloat = 12
    static let transientMinimumHeight: CGFloat = 132
    static let maximumHeight: CGFloat = 700
    /// Search never grows past the editor's default height.
    static let searchMaximumHeight: CGFloat = 440

    static func searchHeight(resultCount: Int) -> CGFloat {
        clamp(rowCount: resultCount, rowHeight: RascSurfaceLayout.searchRowMinHeight, maximum: searchMaximumHeight)
    }

    static func paletteHeight(commandCount: Int) -> CGFloat {
        clamp(rowCount: commandCount, rowHeight: RascSurfaceLayout.commandRowMinHeight, maximum: maximumHeight)
    }

    private static func clamp(rowCount: Int, rowHeight: CGFloat, maximum: CGFloat) -> CGFloat {
        let rows = CGFloat(max(rowCount, 0)) * (rowHeight + RascSurfaceLayout.listRowSpacing)
        let rowsHeight = rowCount > 0 ? rows - RascSurfaceLayout.listRowSpacing : 0
        let raw = headerHeight + rowsHeight + bottomInset
        return min(max(raw, transientMinimumHeight), maximum)
    }
}
