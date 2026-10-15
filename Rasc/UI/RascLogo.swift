import SwiftUI

struct RascLogo: View {
    static let compactSize: CGFloat = 24
    var size: CGFloat = 64

    var body: some View {
        Image(size == Self.compactSize ? "RascLogoCompact" : "RascLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
