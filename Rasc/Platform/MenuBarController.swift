import AppKit
import KeyboardShortcuts

@MainActor
protocol MenuBarControllerDelegate: AnyObject {
    func menuBarOpenHome()
    func menuBarExportThoughts()
    func menuBarOpenScratch()
    func menuBarNewScratch()
    func menuBarOpenSearch()
    func menuBarOpenSettings()
    func menuBarCheckForUpdates()
    func menuBarSendFeedback()
    func menuBarQuit()
    #if DEBUG
    func menuBarResetOnboarding()
    #endif
}

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private weak var delegate: MenuBarControllerDelegate?

    init(delegate: MenuBarControllerDelegate) {
        self.delegate = delegate
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureMenu()
    }

    private var voiceItems: [NSMenuItem] = []

    private func configureMenu() {
        guard let button = statusItem.button else { return }

        if let image = NSImage(named: "MenuBarIcon") {
            button.image = image
        } else if let fallback = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil) {
            fallback.isTemplate = true
            button.image = fallback
        }
        button.setAccessibilityLabel("Rasc")

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        menu.addItem(makeItem(
            title: "Open Scratch",
            action: #selector(openScratch),
            keyEquivalent: ""
        ))
        let home = makeItem(
            title: "Open Home",
            action: #selector(openRasc),
            keyEquivalent: ""
        )
        home.setShortcut(for: .toggleHome)
        menu.addItem(home)
        menu.addItem(makeItem(
            title: "New Scratch",
            action: #selector(newScratch),
            keyEquivalent: "n",
            modifierMask: .command
        ))
        menu.addItem(makeItem(
            title: "Search thoughts",
            action: #selector(openSearch),
            keyEquivalent: "p",
            modifierMask: .command
        ))
        if VoiceCapture.isSupported {
            voiceItems = [
                makeItem(title: "Voice Capture…", action: #selector(voiceCapture), keyEquivalent: ""),
                makeItem(title: "Cancel Voice Capture", action: #selector(cancelVoiceCapture), keyEquivalent: ""),
                makeItem(title: "Open Kept Thought", action: #selector(openVoiceThought), keyEquivalent: ""),
                makeItem(title: "Undo Voice Capture", action: #selector(undoVoiceKeep), keyEquivalent: ""),
            ]
            voiceItems.forEach(menu.addItem)
        }
        menu.addItem(.separator())
        menu.addItem(makeItem(
            title: "Export Thoughts…",
            action: #selector(exportThoughts),
            keyEquivalent: ""
        ))
        menu.addItem(makeItem(
            title: "Settings",
            action: #selector(openSettings),
            keyEquivalent: ",",
            modifierMask: .command
        ))
        menu.addItem(makeItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        ))
        menu.addItem(makeItem(
            title: "Send Feedback…",
            action: #selector(sendFeedback),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        #if DEBUG
        menu.addItem(makeItem(
            title: "Reset Onboarding",
            action: #selector(resetOnboarding),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        #endif
        menu.addItem(makeItem(
            title: "Quit Rasc",
            action: #selector(quit),
            keyEquivalent: "q",
            modifierMask: .command
        ))

        statusItem.menu = menu
        applyInternalShortcuts()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(internalShortcutsDidChange),
            name: InternalShortcutStore.didChange,
            object: nil
        )
    }

    @objc private func internalShortcutsDidChange() {
        applyInternalShortcuts()
    }

    private func applyInternalShortcuts() {
        guard let menu = statusItem.menu else { return }
        for item in menu.items {
            guard let command = InternalCommand.allCases.first(where: { $0.menuTitle == item.title }) else {
                continue
            }
            let shortcut = InternalShortcutStore.shared.shortcut(for: command)
            item.keyEquivalent = shortcut.key
            item.keyEquivalentModifierMask = shortcut.modifierMask
        }
    }

    private func makeItem(
        title: String,
        action: Selector,
        keyEquivalent: String,
        modifierMask: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.keyEquivalentModifierMask = modifierMask
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        KeyboardShortcuts.disable(.toggleScratchpad, .toggleHome, .voiceCapture)
        guard voiceItems.count == 4 else { return }
        let capture = VoiceCapture.shared
        let phase = capture.phase
        voiceItems[0].title = switch phase {
        case .listening: "Finish Voice Capture"
        case .reviewing: "Review Voice Capture"
        case .issue(.permission) where capture.needsMicrophoneAccess: "Open Microphone Settings…"
        case .issue(.transcription) where capture.canRetryAudio: "Retry Transcription"
        case .issue: "Try Voice Capture Again"
        default: capture.enabled ? "Start Voice Capture" : "Voice Capture…"
        }
        voiceItems[0].isEnabled = switch phase {
        case .idle, .listening, .reviewing, .kept, .issue: true
        default: false
        }
        voiceItems[1].isHidden = switch phase {
        case .checking, .starting, .listening, .finishing, .transcribing, .waitingForModel, .issue: false
        default: true
        }
        voiceItems[2].isHidden = phase != .kept
        voiceItems[3].isHidden = phase != .kept
    }

    func menuDidClose(_ menu: NSMenu) {
        KeyboardShortcuts.enable(.toggleScratchpad, .toggleHome, .voiceCapture)
    }

    @objc private func voiceCapture() { VoiceCapture.shared.activate() }
    @objc private func cancelVoiceCapture() { VoiceCapture.shared.cancel() }
    @objc private func openVoiceThought() { VoiceCapture.shared.openThought() }
    @objc private func undoVoiceKeep() { VoiceCapture.shared.undo() }

    @objc private func openScratch() {
        delegate?.menuBarOpenScratch()
    }

    @objc private func openRasc() {
        delegate?.menuBarOpenHome()
    }

    @objc private func exportThoughts() {
        delegate?.menuBarExportThoughts()
    }

    @objc private func newScratch() {
        delegate?.menuBarNewScratch()
    }

    @objc private func openSearch() {
        delegate?.menuBarOpenSearch()
    }

    @objc private func openSettings() {
        delegate?.menuBarOpenSettings()
    }

    @objc private func checkForUpdates() {
        delegate?.menuBarCheckForUpdates()
    }

    @objc private func sendFeedback() {
        delegate?.menuBarSendFeedback()
    }

    @objc private func quit() {
        delegate?.menuBarQuit()
    }

    #if DEBUG
    @objc private func resetOnboarding() {
        delegate?.menuBarResetOnboarding()
    }
    #endif
}
