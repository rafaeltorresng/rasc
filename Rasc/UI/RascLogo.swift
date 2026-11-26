import AppKit
import SwiftUI

struct RascLogo: View {
    static let compactSize: CGFloat = 24
    var size: CGFloat = 64

    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let assetName = size == Self.compactSize ? "RascLogoCompact" : "RascLogo"
        if NSImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(palette.raisedFill(for: colorScheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                            .strokeBorder(palette.border(for: colorScheme), lineWidth: 1)
                    }
                Image(systemName: "note.text")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(palette.noteText(for: colorScheme))
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }
}
