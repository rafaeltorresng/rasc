import SwiftUI

extension View {
    @ViewBuilder
    func transientSurfaceBackground() -> some View {
        if #available(macOS 26.0, *) {
            self.background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 10))
            }
        } else {
            self.background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    func refinementPreviewSurface() -> some View {
        if #available(macOS 26.0, *) {
            self.background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 8))
            }
        } else {
            self.background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            )
        }
    }
}
