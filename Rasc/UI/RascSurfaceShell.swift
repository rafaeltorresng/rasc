import SwiftUI

enum RascSurfaceLayout {
    static let horizontalInset: CGFloat = 20
    static let topInset: CGFloat = 2
    static let orbSize: CGFloat = 20
    static let orbToAccessoryGap: CGFloat = 9
    static let scratchpadContentGap: CGFloat = 14
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

    static var scratchpadEditorTopPadding: CGFloat {
        topInset + orbSize + scratchpadContentGap
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
