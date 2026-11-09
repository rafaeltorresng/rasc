import SwiftUI

@main
struct RascApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var shortcuts = InternalShortcutStore.shared

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Scratch") {
                    appDelegate.startNewScratch()
                }
                .keyboardShortcut(
                    shortcuts.shortcut(for: .newScratch).keyEquivalent,
                    modifiers: shortcuts.shortcut(for: .newScratch).eventModifiers
                )
            }

            CommandGroup(after: .newItem) {
                Button("Open Home") {
                    appDelegate.openHome()
                }

                Button("Search thoughts") {
                    appDelegate.openSearch()
                }
                .keyboardShortcut(
                    shortcuts.shortcut(for: .search).keyEquivalent,
                    modifiers: shortcuts.shortcut(for: .search).eventModifiers
                )

                Button("Refine") {
                    appDelegate.refine()
                }
                .keyboardShortcut(
                    shortcuts.shortcut(for: .refine).keyEquivalent,
                    modifiers: shortcuts.shortcut(for: .refine).eventModifiers
                )

                Button("Command Palette") {
                    appDelegate.openCommandPalette()
                }
                .keyboardShortcut(
                    shortcuts.shortcut(for: .commandPalette).keyEquivalent,
                    modifiers: shortcuts.shortcut(for: .commandPalette).eventModifiers
                )
            }

            CommandGroup(after: .pasteboard) {
                Button("Keep") {
                    appDelegate.keepActiveNote()
                }
                .keyboardShortcut(
                    shortcuts.shortcut(for: .keep).keyEquivalent,
                    modifiers: shortcuts.shortcut(for: .keep).eventModifiers
                )

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
                Button("Settings…") {
                    appDelegate.openSettings()
                }
                .keyboardShortcut(",")
            }
        }
    }
}
