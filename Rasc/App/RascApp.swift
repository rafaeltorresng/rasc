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
                Button("Open Home") {
                    appDelegate.openHome()
                }

                Button("Search thoughts") {
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

            CommandGroup(after: .pasteboard) {
                Button("Keep") {
                    appDelegate.keepActiveNote()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Copy Note") {
                    appDelegate.copyActiveNote()
                }

                Button("Share…") {
                    appDelegate.shareActiveNote()
                }

                Button("Discard Note") {
                    appDelegate.discardActiveNote()
                }
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
