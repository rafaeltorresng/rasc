import AppKit
import ApplicationServices
import Foundation

/// A single modifier key used as a global trigger. Unlike `KeyboardShortcuts`,
/// this cannot be registered with Carbon, so it relies on a global event monitor
/// and therefore on Accessibility access for events from other applications.
enum ModifierShortcut: String, CaseIterable, Codable, Sendable, Identifiable {
    case option
    case control
    case shift
    case command

    var id: String { rawValue }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .option: .option
        case .control: .control
        case .shift: .shift
        case .command: .command
        }
    }

    var displayString: String {
        switch self {
        case .option: "⌥"
        case .control: "⌃"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }

    var displayName: String {
        switch self {
        case .option: "Option (⌥)"
        case .control: "Control (⌃)"
        case .shift: "Shift (⇧)"
        case .command: "Command (⌘)"
        }
    }

    static func matching(_ flags: NSEvent.ModifierFlags) -> ModifierShortcut? {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        return allCases.first { flags.contains($0.flag) }
    }
}

/// The pure part of modifier tap detection. Kept free of AppKit so the
/// isolated-tap versus chord rules can be tested without event monitors.
struct ModifierTapRecognizer: Equatable {
    enum Input: Equatable {
        case modifierPressed(ModifierShortcut, otherModifiersDown: Bool)
        case modifierReleased(ModifierShortcut, otherModifiersDown: Bool)
        case otherKeyDown
        case otherInput
        case reset
    }

    var shortcut: ModifierShortcut?
    var maximumTapDuration: Duration = .milliseconds(400)
    private(set) var candidateStartedAt: ContinuousClock.Instant?
    private(set) var interfered = false

    init(shortcut: ModifierShortcut? = nil, maximumTapDuration: Duration = .milliseconds(400)) {
        self.shortcut = shortcut
        self.maximumTapDuration = maximumTapDuration
    }

    /// Returns true only for a clean press and release of the configured
    /// modifier, with no other modifier, key or pointer input in between and
    /// within the tap threshold.
    @discardableResult
    mutating func handle(_ input: Input, at now: ContinuousClock.Instant = .now) -> Bool {
        switch input {
        case let .modifierPressed(modifier, otherModifiersDown):
            guard modifier == shortcut else {
                if candidateStartedAt != nil { interfered = true }
                return false
            }
            // A repeated flagsChanged for the same modifier restarts the
            // candidate rather than firing on a stale press.
            candidateStartedAt = now
            interfered = otherModifiersDown
            return false

        case let .modifierReleased(modifier, otherModifiersDown):
            guard modifier == shortcut, let started = candidateStartedAt else { return false }
            let elapsed = started.duration(to: now)
            let isCleanTap = !interfered
                && !otherModifiersDown
                && elapsed <= maximumTapDuration
            reset()
            return isCleanTap

        case .otherKeyDown, .otherInput:
            if candidateStartedAt != nil { interfered = true }
            return false

        case .reset:
            reset()
            return false
        }
    }

    private mutating func reset() {
        candidateStartedAt = nil
        interfered = false
    }
}

enum ModifierShortcutAccess {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func request() {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
final class ModifierShortcutStore: ObservableObject {
    static let shared = ModifierShortcutStore()
    static let didChange = Notification.Name("RascModifierShortcutDidChange")
    static let preferenceKey = "voiceCaptureModifierShortcut"

    @Published private(set) var shortcut: ModifierShortcut?

    private let defaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
        shortcut = userDefaults.string(forKey: Self.preferenceKey).flatMap(ModifierShortcut.init(rawValue:))
    }

    func set(_ shortcut: ModifierShortcut?) {
        guard shortcut != self.shortcut else { return }
        self.shortcut = shortcut
        if let shortcut {
            defaults.set(shortcut.rawValue, forKey: Self.preferenceKey)
        } else {
            defaults.removeObject(forKey: Self.preferenceKey)
        }
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

/// Installs global and local `flagsChanged` monitoring for the configured
/// modifier. Global events require Accessibility trust; local events work
/// whenever Rasc is the active application.
@MainActor
final class ModifierShortcutMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var recognizer = ModifierTapRecognizer()
    private var lastFlags: NSEvent.ModifierFlags = []
    private var shortcut: ModifierShortcut?
    private var onTap: (() -> Void)?

    var isSuspended = false {
        didSet { if isSuspended { recognizer.handle(.reset) } }
    }

    var isRunning: Bool { globalMonitor != nil || localMonitor != nil }

    func start(shortcut: ModifierShortcut, onTap: @escaping () -> Void) {
        if isRunning, self.shortcut == shortcut { self.onTap = onTap; return }
        stop()
        self.shortcut = shortcut
        self.onTap = onTap
        recognizer = ModifierTapRecognizer(shortcut: shortcut)
        lastFlags = []

        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.process(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.process(event)
            }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        shortcut = nil
        onTap = nil
        recognizer.handle(.reset)
        lastFlags = []
    }

    private func process(_ event: NSEvent) {
        guard !isSuspended else {
            if event.type == .flagsChanged { lastFlags = relevantFlags(event) }
            return
        }
        switch event.type {
        case .flagsChanged:
            let next = relevantFlags(event)
            let pressed = next.subtracting(lastFlags)
            let released = lastFlags.subtracting(next)
            lastFlags = next
            for modifier in ModifierShortcut.allCases {
                if pressed.contains(modifier.flag) {
                    let others = !next.subtracting(modifier.flag).isEmpty
                    _ = recognizer.handle(.modifierPressed(modifier, otherModifiersDown: others))
                }
                if released.contains(modifier.flag) {
                    let others = !next.isEmpty
                    if recognizer.handle(.modifierReleased(modifier, otherModifiersDown: others)) {
                        onTap?()
                    }
                }
            }
        case .keyDown:
            _ = recognizer.handle(.otherKeyDown)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            _ = recognizer.handle(.otherInput)
        default:
            break
        }
    }

    private func relevantFlags(_ event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection([.command, .option, .control, .shift])
    }
}

/// Records a single modifier in a Settings control without triggering capture.
@MainActor
final class ModifierShortcutRecorderModel: ObservableObject {
    @Published private(set) var isRecording = false

    private var monitor: Any?
    private var onAssign: ((ModifierShortcut?) -> Void)?

    func begin(onAssign: @escaping (ModifierShortcut?) -> Void) {
        end()
        isRecording = true
        self.onAssign = onAssign
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    func end() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        onAssign = nil
    }

    func cancel() { end() }

    func assign(_ shortcut: ModifierShortcut?) {
        onAssign?(shortcut)
        end()
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let shortcut = ModifierShortcut.matching(flags), flags.subtracting(shortcut.flag).isEmpty else { return }
        assign(shortcut)
    }
}
