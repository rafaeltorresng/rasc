import AppKit

@MainActor
protocol MenuBarControllerDelegate: AnyObject {
    func menuBarOpenHome()
    func menuBarNewScratch()
    func menuBarOpenSearch()
    func menuBarOpenSettings()
    func menuBarSendFeedback()
    func menuBarQuit()
    #if DEBUG
    func menuBarResetOnboarding()
    #endif
}

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private weak var delegate: MenuBarControllerDelegate?

    init(delegate: MenuBarControllerDelegate) {
        self.delegate = delegate
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureMenu()
    }

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

        menu.addItem(makeItem(
            title: "Open Home",
            action: #selector(openRasc),
            keyEquivalent: "\\",
            modifierMask: [.command, .option]
        ))
        menu.addItem(makeItem(
            title: "New Scratch",
            action: #selector(newScratch),
            keyEquivalent: "n",
            modifierMask: .command
        ))
        menu.addItem(makeItem(
            title: "History / Search",
            action: #selector(openSearch),
            keyEquivalent: "p",
            modifierMask: .command
        ))
        menu.addItem(.separator())
        menu.addItem(makeItem(
            title: "Settings",
            action: #selector(openSettings),
            keyEquivalent: ",",
            modifierMask: .command
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

    @objc private func openRasc() {
        delegate?.menuBarOpenHome()
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
