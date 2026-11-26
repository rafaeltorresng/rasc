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

    static let relevantMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    static func matching(_ flags: NSEvent.ModifierFlags) -> ModifierShortcut? {
        let flags = flags.intersection(relevantMask)
        return allCases.first { flags.contains($0.flag) }
    }

    static func exclusive(in flags: NSEvent.ModifierFlags) -> ModifierShortcut? {
        let relevant = flags.intersection(relevantMask)
        guard let shortcut = allCases.first(where: { relevant.contains($0.flag) }),
              relevant.subtracting(shortcut.flag).isEmpty else {
            return nil
        }
        return shortcut
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
            if candidateStartedAt != nil {
                // Keep prior interference sticky until a release or explicit reset.
                interfered = true
                return false
            }
            candidateStartedAt = now
            interfered = otherModifiersDown
            return false

        case let .modifierReleased(modifier, otherModifiersDown):
            guard modifier == shortcut, let started = candidateStartedAt else { return false }
            let elapsed = started.duration(to: now)
            let isCleanTap = !interfered
                && !otherModifiersDown
                && elapsed >= .zero
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
    private nonisolated(unsafe) var globalMonitor: Any?
    private nonisolated(unsafe) var localMonitor: Any?
    private nonisolated(unsafe) var workspaceObserver: (any NSObjectProtocol)?
    private nonisolated(unsafe) var appObservers: [any NSObjectProtocol] = []
    private var recognizer = ModifierTapRecognizer()
    private var lastFlags: NSEvent.ModifierFlags = []
    private var shortcut: ModifierShortcut?
    private var onTap: (() -> Void)?

    var isSuspended = false {
        didSet {
            if isSuspended {
                recognizer.handle(.reset)
            } else {
                lastFlags = currentFlags()
            }
        }
    }

    var isRunning: Bool { globalMonitor != nil || localMonitor != nil }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        for observer in appObservers { NotificationCenter.default.removeObserver(observer) }
    }

    func start(shortcut: ModifierShortcut, onTap: @escaping () -> Void) {
        if isRunning, self.shortcut == shortcut { self.onTap = onTap; return }
        stop()
        self.shortcut = shortcut
        self.onTap = onTap
        recognizer = ModifierTapRecognizer(shortcut: shortcut)
        lastFlags = currentFlags()

        let mask: NSEvent.EventTypeMask = [
            .flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel
        ]
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
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reset()
            }
        }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            appObservers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.reset()
                    }
                }
            )
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        for observer in appObservers { NotificationCenter.default.removeObserver(observer) }
        globalMonitor = nil
        localMonitor = nil
        workspaceObserver = nil
        appObservers = []
        shortcut = nil
        onTap = nil
        recognizer.handle(.reset)
        lastFlags = []
    }

    func reset() {
        _ = recognizer.handle(.reset)
        lastFlags = currentFlags()
    }

    /// Marks non-modifier key input when an external handler (such as Carbon
    /// hotkeys) consumes a chord before the global `keyDown` monitor receives it.
    func noteOtherKeyDown() {
        _ = recognizer.handle(.otherKeyDown)
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
            if event.keyCode == 53 {
                _ = recognizer.handle(.reset)
            } else {
                _ = recognizer.handle(.otherKeyDown)
            }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            _ = recognizer.handle(.otherInput)
        default:
            break
        }
    }

    private func relevantFlags(_ event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection(ModifierShortcut.relevantMask)
    }

    private func currentFlags() -> NSEvent.ModifierFlags {
        NSEvent.modifierFlags.intersection(ModifierShortcut.relevantMask)
    }
}

/// Records a single modifier in a Settings control without triggering capture.
@MainActor
final class ModifierShortcutRecorderModel: ObservableObject {
    @Published private(set) var isRecording = false

    private nonisolated(unsafe) var monitor: Any?
    private var onAssign: ((ModifierShortcut?) -> Void)?
    private var pendingShortcut: ModifierShortcut?
    private var interfered = false

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    func begin(onAssign: @escaping (ModifierShortcut?) -> Void) {
        end()
        isRecording = true
        self.onAssign = onAssign
        pendingShortcut = nil
        interfered = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            let consume = MainActor.assumeIsolated {
                self?.handle(event) ?? false
            }
            return consume ? nil : event
        }
    }

    func end() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        onAssign = nil
        pendingShortcut = nil
        interfered = false
    }

    func cancel() { end() }

    func assign(_ shortcut: ModifierShortcut?) {
        onAssign?(shortcut)
        end()
    }

    /// Returns `true` when the event should be consumed while recording.
    private func handle(_ event: NSEvent) -> Bool {
        if event.type == .keyDown {
            if event.keyCode == 53 {
                cancel()
                return true
            }
            pendingShortcut = nil
            interfered = true
            return true
        }

        let relevant = event.modifierFlags.intersection(ModifierShortcut.relevantMask)
        if relevant.isEmpty {
            if !interfered, let pendingShortcut {
                assign(pendingShortcut)
                return false
            }
            pendingShortcut = nil
            interfered = false
            return false
        }

        if let exclusive = ModifierShortcut.exclusive(in: relevant) {
            if pendingShortcut == nil && !interfered {
                pendingShortcut = exclusive
            } else if pendingShortcut != exclusive {
                pendingShortcut = nil
                interfered = true
            }
        } else {
            pendingShortcut = nil
            interfered = true
        }
        return false
    }
}
