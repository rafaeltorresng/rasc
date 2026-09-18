import SwiftUI

@main
struct RascApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
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

                Button("Refine") {
                    appDelegate.refine()
                }
                .keyboardShortcut("j")

                Button("Command Palette") {
                    appDelegate.openCommandPalette()
                }
                .keyboardShortcut("k")
            }

            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Settings…")
                }
                .keyboardShortcut(",")
            }
        }
    }
}
