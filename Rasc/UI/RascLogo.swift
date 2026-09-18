import SwiftUI

struct RascLogo: View {
    var size: CGFloat = 64

    var body: some View {
        Image("RascLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
