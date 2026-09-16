import AppKit

@MainActor
protocol MenuBarControllerDelegate: AnyObject {
    func menuBarOpenRasc()
    func menuBarNewScratch()
    func menuBarOpenSearch()
    func menuBarOpenSettings()
    func menuBarQuit()
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

        if let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Rasc") {
            image.isTemplate = true
            button.image = image
        }
        button.setAccessibilityLabel("Rasc")

        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(makeItem(
            title: "Open Rasc",
            action: #selector(openRasc),
            keyEquivalent: ""
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
        menu.addItem(.separator())
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
        delegate?.menuBarOpenRasc()
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

    @objc private func quit() {
        delegate?.menuBarQuit()
    }
}
