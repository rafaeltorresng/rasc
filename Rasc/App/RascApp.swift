import SwiftUI

@main
struct RascApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            ShortcutSettingsView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Scratch") {
                    appDelegate.startNewScratch()
                }
                .keyboardShortcut("n")
            }

            CommandGroup(after: .newItem) {
                Button("Find Note") {
                    appDelegate.openSearch()
                }
                .keyboardShortcut("p")
            }
        }
    }
}
