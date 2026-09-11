import KeyboardShortcuts
import SwiftUI

struct ShortcutSettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder(
                "Toggle scratchpad:",
                name: .toggleScratchpad
            )
        }
        .padding(20)
        .frame(width: 420)
    }
}
