import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
enum GlobalShortcutFormatting {
    static func currentToggleShortcutDisplay() -> String {
        display(for: .toggleScratchpad)
    }

    static func currentHomeShortcutDisplay() -> String {
        display(for: .toggleHome)
    }

    static func hasValidToggleShortcut() -> Bool {
        KeyboardShortcuts.getShortcut(for: .toggleScratchpad) != nil
    }

    static func hasValidHomeShortcut() -> Bool {
        KeyboardShortcuts.getShortcut(for: .toggleHome) != nil
    }

    private static func display(for name: KeyboardShortcuts.Name) -> String {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else {
            return "—"
        }
        return shortcut.description
    }
}

@MainActor
enum GlobalShortcutPolicy {
    static func validation(
        proposed: KeyboardShortcuts.Shortcut,
        other: KeyboardShortcuts.Name,
        otherTitle: String
    ) -> KeyboardShortcuts.ValidationResult {
        if KeyboardShortcuts.getShortcut(for: other) == proposed {
            return .disallow(reason: "Already used by \(otherTitle).")
        }
        return .allow
    }

    @discardableResult
    static func restoreDefault(
        _ name: KeyboardShortcuts.Name,
        other: KeyboardShortcuts.Name
    ) -> Bool {
        guard let initial = name.initialShortcut else {
            KeyboardShortcuts.setShortcut(nil, for: name)
            return true
        }
        if KeyboardShortcuts.getShortcut(for: other) == initial {
            return false
        }
        KeyboardShortcuts.reset(name)
        return true
    }

    static func isUsingInitialShortcut(_ name: KeyboardShortcuts.Name) -> Bool {
        KeyboardShortcuts.getShortcut(for: name) == name.initialShortcut
    }
}

struct RascShortcutEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let shortcut: String
    let detail: String?
}

enum RascShortcutCatalog {
    static let newScratch = RascShortcutEntry(
        id: "new-scratch",
        title: "New Scratch",
        shortcut: "⌘N",
        detail: nil
    )
    static let refine = RascShortcutEntry(
        id: "refine",
        title: "Refine",
        shortcut: "⌘J",
        detail: nil
    )
    static let keep = RascShortcutEntry(
        id: "keep",
        title: "Keep",
        shortcut: "⇧⌘K",
        detail: nil
    )
    static let searchThoughts = RascShortcutEntry(
        id: "search-thoughts",
        title: "Search thoughts",
        shortcut: "⌘P",
        detail: nil
    )
    static let commandPalette = RascShortcutEntry(
        id: "command-palette",
        title: "Command Palette",
        shortcut: "⌘K",
        detail: nil
    )
    static let settings = RascShortcutEntry(
        id: "settings",
        title: "Settings",
        shortcut: "⌘,",
        detail: nil
    )
    static let hideScratchpad = RascShortcutEntry(
        id: "hide-scratchpad",
        title: "Hide Scratchpad",
        shortcut: "Esc",
        detail: nil
    )
    static let keepOriginal = RascShortcutEntry(
        id: "keep-original",
        title: "Keep original",
        shortcut: "Esc",
        detail: "Refinement preview"
    )
    static let acceptSuggestion = RascShortcutEntry(
        id: "accept-suggestion",
        title: "Accept suggestion",
        shortcut: "↵",
        detail: "Refinement preview"
    )
    static let quit = RascShortcutEntry(
        id: "quit",
        title: "Quit Rasc",
        shortcut: "⌘Q",
        detail: nil
    )

    static let insideRasc: [RascShortcutEntry] = [
        newScratch,
        refine,
        keep,
        searchThoughts,
        commandPalette,
        settings,
        hideScratchpad,
        keepOriginal,
        acceptSuggestion,
        quit
    ]
}

private struct GlobalShortcutChangeObserver: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: GlobalShortcutChange.notification)) { _ in
            action()
        }
    }
}

private enum GlobalShortcutChange {
    /// `KeyboardShortcuts` posts this when a stored shortcut changes. The symbol is internal to the package.
    static let notification = Notification.Name("KeyboardShortcuts_shortcutByNameDidChange")
}

extension View {
    func onGlobalShortcutChange(perform action: @escaping () -> Void) -> some View {
        modifier(GlobalShortcutChangeObserver(action: action))
    }
}

enum InternalCommand: String, CaseIterable, Identifiable {
    case newScratch
    case search
    case refine
    case commandPalette
    case keep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newScratch: "New Scratch"
        case .search: "Search thoughts"
        case .refine: "Refine"
        case .commandPalette: "Command Palette"
        case .keep: "Keep"
        }
    }

    var menuTitle: String { title }

    var defaultShortcut: InternalShortcut {
        switch self {
        case .newScratch: InternalShortcut(key: "n", command: true)
        case .search: InternalShortcut(key: "p", command: true)
        case .refine: InternalShortcut(key: "j", command: true)
        case .commandPalette: InternalShortcut(key: "k", command: true)
        case .keep: InternalShortcut(key: "k", command: true, shift: true)
        }
    }
}

struct InternalShortcut: Equatable, Codable, Sendable {
    var key: String
    var command = false
    var option = false
    var control = false
    var shift = false

    init(key: String, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false) {
        self.key = key
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let raw = event.charactersIgnoringModifiers?.lowercased(), raw.count == 1 else { return nil }
        self.init(
            key: raw,
            command: flags.contains(.command),
            option: flags.contains(.option),
            control: flags.contains(.control),
            shift: flags.contains(.shift)
        )
    }

    var includesChordModifier: Bool {
        command || option || control
    }

    var displayString: String {
        var glyphs = ""
        if control { glyphs.append("⌃") }
        if option { glyphs.append("⌥") }
        if shift { glyphs.append("⇧") }
        if command { glyphs.append("⌘") }
        glyphs.append(key == "," ? "," : key.uppercased())
        return glyphs
    }

    var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if command { modifiers.insert(.command) }
        if option { modifiers.insert(.option) }
        if control { modifiers.insert(.control) }
        if shift { modifiers.insert(.shift) }
        return modifiers
    }

    var keyEquivalent: KeyEquivalent {
        KeyEquivalent(Character(key))
    }

    var modifierMask: NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if command { mask.insert(.command) }
        if option { mask.insert(.option) }
        if control { mask.insert(.control) }
        if shift { mask.insert(.shift) }
        return mask
    }
}

@MainActor
final class InternalShortcutStore: ObservableObject {
    static let shared = InternalShortcutStore()
    static let didChange = Notification.Name("RascInternalShortcutDidChange")

    private let defaults: UserDefaults
    private let storageKey = "internalCommandShortcuts"
    private var overrides: [InternalCommand: InternalShortcut]

    init(userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
        overrides = Self.load(from: userDefaults, key: storageKey)
    }

    func shortcut(for command: InternalCommand) -> InternalShortcut {
        overrides[command] ?? command.defaultShortcut
    }

    func displayString(for command: InternalCommand) -> String {
        shortcut(for: command).displayString
    }

    func command(matching event: NSEvent) -> InternalCommand? {
        guard let shortcut = InternalShortcut(event: event) else { return nil }
        return command(matching: shortcut)
    }

    func command(matching shortcut: InternalShortcut) -> InternalCommand? {
        guard shortcut.includesChordModifier else { return nil }
        return InternalCommand.allCases.first { self.shortcut(for: $0) == shortcut }
    }

    @discardableResult
    func assign(_ shortcut: InternalShortcut, to command: InternalCommand) -> String? {
        if let reason = rejectionReason(for: shortcut, ignoring: command) {
            return reason
        }
        overrides[command] = shortcut
        persist()
        return nil
    }

    func restoreDefaults() {
        overrides = [:]
        persist()
    }

    func isUsingDefault(for command: InternalCommand) -> Bool {
        overrides[command] == nil || overrides[command] == command.defaultShortcut
    }

    func rejectionReason(for shortcut: InternalShortcut, ignoring command: InternalCommand) -> String? {
        guard shortcut.includesChordModifier else {
            return "Use ⌘, ⌥, or ⌃."
        }
        let reserved = Set(["cmd+q", "cmd+w", "cmd+,"])
        if reserved.contains(canonical(shortcut)) || shortcut.key == "\u{1b}" {
            return "That shortcut belongs to macOS."
        }
        if let other = InternalCommand.allCases.first(where: { $0 != command && self.shortcut(for: $0) == shortcut }) {
            return "Already used by \(other.title)."
        }
        if let global = conflictingGlobalTitle(shortcut) {
            return "Already used by \(global)."
        }
        return nil
    }

    func applyToMainMenu() {
        MainMenuShortcutBridge.shared.attachToMainMenu()
        applyKeyEquivalents()
    }

    func applyKeyEquivalents() {
        guard let app = NSApp, let menu = app.mainMenu else { return }
        for item in menu.items.flatMap({ $0.submenu?.items ?? [] }) {
            guard let command = InternalCommand.allCases.first(where: { $0.menuTitle == item.title }) else {
                continue
            }
            let shortcut = shortcut(for: command)
            item.keyEquivalent = shortcut.key
            item.keyEquivalentModifierMask = shortcut.modifierMask
        }
    }

    private func conflictingGlobalTitle(_ shortcut: InternalShortcut) -> String? {
        let pairs: [(KeyboardShortcuts.Name, String)] = [
            (.toggleScratchpad, "Toggle Scratchpad"),
            (.toggleHome, "Toggle Home"),
        ]
        for (name, title) in pairs {
            guard let global = KeyboardShortcuts.getShortcut(for: name) else { continue }
            let normalized = global.description.replacingOccurrences(of: " ", with: "")
            if normalized == shortcut.displayString {
                return title
            }
        }
        return nil
    }

    private func canonical(_ shortcut: InternalShortcut) -> String {
        var parts: [String] = []
        if shortcut.control { parts.append("ctrl") }
        if shortcut.option { parts.append("opt") }
        if shortcut.shift { parts.append("shift") }
        if shortcut.command { parts.append("cmd") }
        return parts.joined(separator: "+") + "+" + shortcut.key
    }

    private func persist() {
        let payload = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: storageKey)
        }
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        applyToMainMenu()
    }

    private static func load(from defaults: UserDefaults, key: String) -> [InternalCommand: InternalShortcut] {
        guard let data = defaults.data(forKey: key),
              let payload = try? JSONDecoder().decode([String: InternalShortcut].self, from: data)
        else {
            return [:]
        }
        var overrides: [InternalCommand: InternalShortcut] = [:]
        for (raw, shortcut) in payload {
            guard let command = InternalCommand(rawValue: raw), shortcut.includesChordModifier else { continue }
            overrides[command] = shortcut
        }
        return overrides
    }
}

/// SwiftUI applies `.keyboardShortcut` when it builds the menu. Reapply after that
/// so the item the user sees is the combination that will run.
@MainActor
final class MainMenuShortcutBridge: NSObject, NSMenuDelegate {
    static let shared = MainMenuShortcutBridge()

    private var forwarded: [ObjectIdentifier: NSMenuDelegate] = [:]

    func attachToMainMenu() {
        guard let menu = NSApp?.mainMenu else { return }
        attach(menu)
        for item in menu.items {
            if let submenu = item.submenu {
                attach(submenu)
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        forwarded[ObjectIdentifier(menu)]?.menuWillOpen?(menu)
        InternalShortcutStore.shared.applyKeyEquivalents()
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return forwarded.values.contains { $0.responds(to: aSelector) }
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if aSelector == #selector(NSMenuDelegate.menuWillOpen(_:)) {
            return nil
        }
        return forwarded.values.first { $0.responds(to: aSelector) }
            ?? super.forwardingTarget(for: aSelector)
    }

    private func attach(_ menu: NSMenu) {
        if menu.delegate === self { return }
        if let delegate = menu.delegate {
            forwarded[ObjectIdentifier(menu)] = delegate
        }
        menu.delegate = self
    }
}
