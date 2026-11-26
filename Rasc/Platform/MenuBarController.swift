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

        let scratch = makeItem(
            title: "Open Scratch",
            action: #selector(openScratch),
            keyEquivalent: ""
        )
        scratch.setShortcut(for: .toggleScratchpad)
        menu.addItem(scratch)
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
                makeItem(title: "Voice to Scratchpad…", action: #selector(voiceToScratchpad), keyEquivalent: ""),
                makeItem(title: "Dictate…", action: #selector(voiceDictate), keyEquivalent: ""),
                makeItem(title: "Cancel Recording", action: #selector(cancelVoiceCapture), keyEquivalent: ""),
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
        KeyboardShortcuts.disable(.toggleScratchpad, .toggleHome)
        GlobalModifierDispatcher.shared.isSuspended = true
        guard voiceItems.count == 3 else { return }
        let capture = VoiceCapture.shared
        let phase = capture.phase

        let scratchItem = voiceItems[0]
        let dictateItem = voiceItems[1]
        let cancelItem = voiceItems[2]

        guard capture.enabled else {
            scratchItem.title = "Set Up Voice…"
            scratchItem.isEnabled = true
            scratchItem.isHidden = false
            dictateItem.isHidden = true
            cancelItem.isHidden = true
            return
        }

        scratchItem.isHidden = false
        scratchItem.title = switch phase {
        case .listening where capture.activeIntent == .scratchpad:
            "Finish Voice to Scratchpad"
        case .ready:
            "Open Captured Thought"
        case .issue(.permission) where capture.needsMicrophoneAccess:
            "Open Microphone Settings…"
        case .issue where capture.canRetryAudio:
            "Retry Transcription"
        case .issue:
            "Try Voice to Scratchpad Again"
        default:
            "Voice to Scratchpad"
        }
        scratchItem.isEnabled = switch phase {
        case .idle, .ready, .copied, .inserted, .insertedAndCopied, .copiedFallback, .issue:
            true
        case .listening:
            capture.activeIntent == .scratchpad
        default:
            false
        }

        dictateItem.isHidden = false
        dictateItem.title = switch phase {
        case .listening where capture.activeIntent == .dictate:
            "Finish Dictation"
        default:
            "Dictate"
        }
        dictateItem.isEnabled = switch phase {
        case .idle, .copied, .inserted, .insertedAndCopied, .copiedFallback:
            true
        case .listening:
            capture.activeIntent == .dictate
        default:
            false
        }

        if capture.isConfirmingCancel {
            cancelItem.title = "Confirm Discard Recording"
        } else if phase == .copiedFallback {
            cancelItem.title = "Dismiss Status"
        } else {
            cancelItem.title = "Cancel Recording"
        }
        cancelItem.isHidden = switch phase {
        case .checking, .starting, .listening, .finishing, .transcribing, .waitingForModel, .copiedFallback, .issue:
            false
        default:
            true
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        KeyboardShortcuts.enable(.toggleScratchpad, .toggleHome)
        GlobalModifierDispatcher.shared.isSuspended = false
    }

    @objc private func voiceToScratchpad() {
        VoiceCapture.shared.activate(intent: .scratchpad)
    }

    @objc private func voiceDictate() {
        VoiceCapture.shared.activate(intent: .dictate)
    }

    @objc private func cancelVoiceCapture() {
        VoiceCapture.shared.requestCancel(fromEscape: false)
    }

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
