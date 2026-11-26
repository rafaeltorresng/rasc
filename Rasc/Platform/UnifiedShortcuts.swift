import AppKit
import Carbon.HIToolbox
import Combine
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let voiceDictate = Self("voiceDictate")
}

/// Global user-configurable actions across Rasc.
enum GlobalShortcutAction: String, CaseIterable, Codable, Sendable, Identifiable {
    case toggleScratchpad
    case toggleHome
    case voiceScratchpad
    case voiceDictate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleScratchpad: "Open Scratchpad"
        case .toggleHome: "Open Home"
        case .voiceScratchpad: "Voice to Scratchpad"
        case .voiceDictate: "Dictate"
        }
    }

    var subtitle: String {
        switch self {
        case .toggleScratchpad:
            "Show or hide the floating scratchpad anywhere."
        case .toggleHome:
            "Open your library of kept thoughts."
        case .voiceScratchpad:
            "Record speech and open it as a new thought in Scratchpad."
        case .voiceDictate:
            "Record speech and type or copy it without opening Rasc."
        }
    }

    var keyboardShortcutName: KeyboardShortcuts.Name {
        switch self {
        case .toggleScratchpad: .toggleScratchpad
        case .toggleHome: .toggleHome
        case .voiceScratchpad: .voiceCapture
        case .voiceDictate: .voiceDictate
        }
    }

    var isVoiceAction: Bool {
        self == .voiceScratchpad || self == .voiceDictate
    }

    var defaultTrigger: GlobalShortcutTrigger? {
        switch self {
        case .toggleScratchpad:
            .chord(KeyboardShortcuts.Shortcut(.backslash, modifiers: [.option]))
        case .toggleHome:
            .chord(KeyboardShortcuts.Shortcut(.backslash, modifiers: [.command, .option]))
        case .voiceScratchpad, .voiceDictate:
            nil
        }
    }
}

/// A global trigger stored either as a key chord (`KeyboardShortcuts`) or a
/// standalone modifier tap (`ModifierShortcut`).
enum GlobalShortcutTrigger: Equatable, Hashable, Sendable {
    case chord(KeyboardShortcuts.Shortcut)
    case modifier(ModifierShortcut)

    @MainActor
    var displayString: String {
        switch self {
        case let .chord(shortcut):
            shortcut.description
        case let .modifier(modifier):
            modifier.displayString
        }
    }

    @MainActor
    var accessibilityLabel: String {
        switch self {
        case let .chord(shortcut):
            shortcut.description
        case let .modifier(modifier):
            modifier.displayName
        }
    }

    var needsAccessibilityPermission: Bool {
        if case .modifier = self { return true }
        return false
    }

    var asChord: KeyboardShortcuts.Shortcut? {
        if case let .chord(shortcut) = self { return shortcut }
        return nil
    }

    var asModifier: ModifierShortcut? {
        if case let .modifier(modifier) = self { return modifier }
        return nil
    }
}

enum GlobalShortcutValidationResult: Equatable, Sendable {
    case allow
    case disallow(reason: String)
}

/// Coordinates unified global shortcuts (key chords and standalone modifier taps),
/// validates against macOS/app conflicts, and performs one-time migration from
/// legacy split voice preferences.
@MainActor
final class GlobalShortcutStore: ObservableObject {
    enum ChordBacking {
        /// Uses `KeyboardShortcuts` library storage (for app runtime & live hotkey tests).
        case systemHotkeys
        /// Stores chords locally inside injected `UserDefaults` for isolated unit tests.
        case userDefaultsOnly
    }

    static let shared = GlobalShortcutStore()
    static let didChange = Notification.Name("RascGlobalShortcutDidChange")
    static let migrationCompletedKey = "globalShortcutsMigratedV1"

    private let defaults: UserDefaults
    private let chordBacking: ChordBacking
    private weak var internalStore: InternalShortcutStore?
    private nonisolated(unsafe) var changeObserver: (any NSObjectProtocol)?

    private struct StoredChord: Codable {
        let carbonKeyCode: Int
        let carbonModifiers: Int
    }

    init(
        userDefaults: UserDefaults = .standard,
        chordBacking: ChordBacking? = nil,
        internalStore: InternalShortcutStore? = nil
    ) {
        self.defaults = userDefaults
        self.chordBacking = chordBacking ?? (userDefaults === UserDefaults.standard ? .systemHotkeys : .userDefaultsOnly)
        self.internalStore = internalStore
        if self.chordBacking == .systemHotkeys {
            changeObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.objectWillChange.send()
                    NotificationCenter.default.post(name: Self.didChange, object: self)
                }
            }
        }
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    func trigger(for action: GlobalShortcutAction) -> GlobalShortcutTrigger? {
        if let modifier = storedModifier(for: action) {
            return .modifier(modifier)
        }
        if let chord = storedChord(for: action) {
            return .chord(chord)
        }
        return nil
    }

    func displayString(for action: GlobalShortcutAction) -> String {
        trigger(for: action)?.displayString ?? "—"
    }

    func isUsingDefault(for action: GlobalShortcutAction) -> Bool {
        trigger(for: action) == action.defaultTrigger
    }

    /// Assigns `trigger` after validating against app and system conflicts.
    /// Returns an explanation if rejected, or `nil` on success.
    @discardableResult
    func set(_ trigger: GlobalShortcutTrigger?, for action: GlobalShortcutAction) -> String? {
        if let trigger {
            if case let .disallow(reason) = validate(proposed: trigger, for: action) {
                return reason
            }
        }
        writeTrigger(trigger, for: action)
        return nil
    }

    @discardableResult
    func restoreDefault(for action: GlobalShortcutAction) -> Bool {
        guard let initial = action.defaultTrigger else {
            writeTrigger(nil, for: action)
            return true
        }
        if case .disallow = validate(proposed: initial, for: action) {
            return false
        }
        writeTrigger(initial, for: action)
        return true
    }

    func validate(
        proposed: GlobalShortcutTrigger,
        for action: GlobalShortcutAction
    ) -> GlobalShortcutValidationResult {
        switch proposed {
        case let .chord(shortcut):
            if let systemReason = Self.reservedChordReason(shortcut) {
                return .disallow(reason: systemReason)
            }
            for other in GlobalShortcutAction.allCases where other != action {
                if trigger(for: other) == .chord(shortcut) {
                    return .disallow(reason: "Already used by \(other.title).")
                }
            }
            let normalized = shortcut.description.replacingOccurrences(of: " ", with: "")
            let internals = internalStore ?? (defaults === UserDefaults.standard ? InternalShortcutStore.shared : nil)
            if let internals {
                for command in InternalCommand.allCases where internals.shortcut(for: command).displayString == normalized {
                    return .disallow(reason: "Already used inside Rasc by \(command.title).")
                }
            }
            return .allow

        case let .modifier(modifier):
            for other in GlobalShortcutAction.allCases where other != action {
                if trigger(for: other) == .modifier(modifier) {
                    return .disallow(reason: "Already used by \(other.title).")
                }
            }
            return .allow
        }
    }

    func activeModifierBindings(
        isEnabled: (GlobalShortcutAction) -> Bool
    ) -> [GlobalShortcutAction: ModifierShortcut] {
        var result: [GlobalShortcutAction: ModifierShortcut] = [:]
        for action in GlobalShortcutAction.allCases where isEnabled(action) {
            if case let .modifier(modifier) = trigger(for: action) {
                result[action] = modifier
            }
        }
        return result
    }

    /// Migrates pre-split Voice Capture shortcuts and output preferences once, idempotently.
    func migrateLegacyPreferencesIfNeeded() {
        guard !defaults.bool(forKey: Self.migrationCompletedKey) else { return }

        let legacyOutputRaw = defaults.string(forKey: VoiceCapture.outputPreferenceKey)
        let targetAction: GlobalShortcutAction =
            (legacyOutputRaw == "clipboard" || legacyOutputRaw == "insertAtCursor")
            ? .voiceDictate
            : .voiceScratchpad

        let legacyModifier = defaults.string(forKey: ModifierShortcutStore.preferenceKey)
            .flatMap(ModifierShortcut.init(rawValue:))
        let existingScratchChord = storedChord(for: .voiceScratchpad)

        if targetAction == .voiceDictate {
            // Preserve previous standalone delivery mode when migrating dictation users.
            defaults.set(legacyOutputRaw, forKey: VoiceCapture.dictationDeliveryPreferenceKey)
            if let existingScratchChord {
                writeTrigger(nil, for: .voiceScratchpad)
                writeTrigger(.chord(existingScratchChord), for: .voiceDictate)
            } else if let legacyModifier {
                writeTrigger(.modifier(legacyModifier), for: .voiceDictate)
            }
        } else {
            defaults.set(VoiceDictationDelivery.insertAtCursor.rawValue, forKey: VoiceCapture.dictationDeliveryPreferenceKey)
            if existingScratchChord == nil, let legacyModifier {
                writeTrigger(.modifier(legacyModifier), for: .voiceScratchpad)
            }
        }

        if defaults.object(forKey: VoiceCapture.standaloneHistoryPreferenceKey) != nil {
            let legacyHistory = defaults.bool(forKey: VoiceCapture.standaloneHistoryPreferenceKey)
            defaults.set(legacyHistory, forKey: VoiceCapture.dictationSaveCopyPreferenceKey)
        }

        defaults.removeObject(forKey: ModifierShortcutStore.preferenceKey)
        defaults.set(true, forKey: Self.migrationCompletedKey)
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    // MARK: - Storage Helpers

    private func modifierKey(for action: GlobalShortcutAction) -> String {
        "globalShortcutModifier.\(action.rawValue)"
    }

    private func chordKey(for action: GlobalShortcutAction) -> String {
        "globalShortcutChord.\(action.rawValue)"
    }

    private func storedModifier(for action: GlobalShortcutAction) -> ModifierShortcut? {
        if let raw = defaults.string(forKey: modifierKey(for: action)),
           let modifier = ModifierShortcut(rawValue: raw) {
            return modifier
        }
        // Fallback if migration hasn't run yet and caller reads legacy scratchpad modifier.
        if action == .voiceScratchpad,
           !defaults.bool(forKey: Self.migrationCompletedKey),
           let raw = defaults.string(forKey: ModifierShortcutStore.preferenceKey) {
            return ModifierShortcut(rawValue: raw)
        }
        return nil
    }

    private func storedChord(for action: GlobalShortcutAction) -> KeyboardShortcuts.Shortcut? {
        switch chordBacking {
        case .systemHotkeys:
            return KeyboardShortcuts.getShortcut(for: action.keyboardShortcutName)
        case .userDefaultsOnly:
            if let data = defaults.data(forKey: chordKey(for: action)),
               let stored = try? JSONDecoder().decode(StoredChord.self, from: data) {
                return KeyboardShortcuts.Shortcut(
                    carbonKeyCode: stored.carbonKeyCode,
                    carbonModifiers: stored.carbonModifiers
                )
            }
            if !defaults.bool(forKey: chordKey(for: action) + ".cleared") {
                return action.defaultTrigger?.asChord
            }
            return nil
        }
    }

    private func writeTrigger(_ trigger: GlobalShortcutTrigger?, for action: GlobalShortcutAction) {
        switch trigger {
        case let .chord(shortcut):
            defaults.removeObject(forKey: modifierKey(for: action))
            if action == .voiceScratchpad {
                defaults.removeObject(forKey: ModifierShortcutStore.preferenceKey)
            }
            writeChord(shortcut, for: action)
        case let .modifier(modifier):
            writeChord(nil, for: action)
            defaults.set(modifier.rawValue, forKey: modifierKey(for: action))
        case nil:
            defaults.removeObject(forKey: modifierKey(for: action))
            if action == .voiceScratchpad {
                defaults.removeObject(forKey: ModifierShortcutStore.preferenceKey)
            }
            writeChord(nil, for: action)
        }
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private func writeChord(_ chord: KeyboardShortcuts.Shortcut?, for action: GlobalShortcutAction) {
        switch chordBacking {
        case .systemHotkeys:
            KeyboardShortcuts.setShortcut(chord, for: action.keyboardShortcutName)
        case .userDefaultsOnly:
            if let chord {
                if let data = try? JSONEncoder().encode(StoredChord(
                    carbonKeyCode: chord.carbonKeyCode,
                    carbonModifiers: chord.carbonModifiers
                )) {
                    defaults.set(data, forKey: chordKey(for: action))
                    defaults.removeObject(forKey: chordKey(for: action) + ".cleared")
                }
            } else {
                defaults.removeObject(forKey: chordKey(for: action))
                defaults.set(true, forKey: chordKey(for: action) + ".cleared")
            }
        }
    }

    static func reservedChordReason(_ shortcut: KeyboardShortcuts.Shortcut) -> String? {
        let mods = shortcut.modifiers.intersection([.command, .option, .control, .shift])
        let isFunctionKey = Self.isFunctionKeyCode(shortcut.carbonKeyCode)
        if !isFunctionKey && mods.subtracting(.shift).isEmpty {
            return "Include ⌘, ⌥, or ⌃, or choose a function key."
        }
        if shortcut.carbonKeyCode == kVK_Escape && mods.subtracting([.option, .command]).isEmpty {
            return "Escape is reserved by macOS and Rasc."
        }
        if Self.reservedSystemChords.contains(shortcut) || shortcut.isTakenBySystem {
            return "That shortcut is reserved by macOS."
        }
        return nil
    }

    private static let reservedSystemChords: Set<KeyboardShortcuts.Shortcut> = [
        KeyboardShortcuts.Shortcut(.q, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.w, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.h, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.m, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.comma, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.tab, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.tab, modifiers: [.command, .shift]),
        KeyboardShortcuts.Shortcut(.backtick, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.space, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.escape, modifiers: [.command, .option]),
    ]

    private static func isFunctionKeyCode(_ keyCode: Int) -> Bool {
        let functionKeyCodes: Set<Int> = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
            kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
            kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18,
            kVK_F19, kVK_F20
        ]
        return functionKeyCodes.contains(keyCode)
    }
}

/// Coordinates a single `ModifierShortcutMonitor` across all active global
/// actions configured with a single-modifier trigger.
@MainActor
final class GlobalModifierDispatcher {
    static let shared = GlobalModifierDispatcher()

    private let monitor = ModifierShortcutMonitor()
    private var actions: [GlobalShortcutAction: ModifierShortcut] = [:]

    var isRunning: Bool { monitor.isRunning }

    var isSuspended: Bool {
        get { monitor.isSuspended }
        set { monitor.isSuspended = newValue }
    }

    func activeShortcut(for action: GlobalShortcutAction) -> ModifierShortcut? {
        actions[action]
    }

    func sync(
        bindings: [GlobalShortcutAction: ModifierShortcut],
        onTrigger: @escaping (GlobalShortcutAction) -> Void
    ) {
        actions = bindings
        var perModifier: [ModifierShortcut: () -> Void] = [:]
        for (action, modifier) in bindings {
            perModifier[modifier] = { onTrigger(action) }
        }
        monitor.start(bindings: perModifier)
    }

    func stop() {
        actions = [:]
        monitor.stop()
    }

    func reset() {
        monitor.reset()
    }

    func noteOtherKeyDown() {
        monitor.noteOtherKeyDown()
    }
}

/// Intercepts Escape (`Esc`) globally and locally ONLY while Voice Capture is active,
/// without requiring Accessibility permissions.
@MainActor
final class ActiveCaptureEscapeInterceptor {
    static let shared = ActiveCaptureEscapeInterceptor()

    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var handlerRef: EventHandlerRef?
    private nonisolated(unsafe) var localMonitor: Any?
    private var onEscape: (() -> Void)?
    private var lastTriggerAt: ContinuousClock.Instant?
    private let signature: OSType = 0x52415343 // 'RASC'
    private let hotKeyIdentifier: UInt32 = 1

    var isActive: Bool {
        hotKeyRef != nil || localMonitor != nil
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    func start(onEscape: @escaping () -> Void) {
        self.onEscape = onEscape
        guard !isActive else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        var installedHandler: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            Self.carbonHandler,
            1,
            &eventType,
            selfPointer,
            &installedHandler
        )
        if installStatus == noErr {
            handlerRef = installedHandler
        }

        var registeredHotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: hotKeyIdentifier)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Escape),
            0,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &registeredHotKey
        )
        if registerStatus == noErr {
            hotKeyRef = registeredHotKey
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                self?.handleLocalKeyDown(event) ?? false
            }
            return handled ? nil : event
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        handlerRef = nil
        onEscape = nil
        lastTriggerAt = nil
    }

    private func handleLocalKeyDown(_ event: NSEvent) -> Bool {
        guard event.keyCode == UInt16(kVK_Escape),
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        else { return false }
        fireIfNotDebounced()
        return true
    }

    private func handleHotKey(_ event: EventRef?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == signature,
              hotKeyID.id == hotKeyIdentifier
        else {
            return OSStatus(eventNotHandledErr)
        }
        fireIfNotDebounced()
        return noErr
    }

    private func fireIfNotDebounced() {
        let now = ContinuousClock.now
        if let lastTriggerAt, lastTriggerAt.duration(to: now) < .milliseconds(80) {
            return
        }
        lastTriggerAt = now
        onEscape?()
    }

    private nonisolated static let carbonHandler: EventHandlerUPP = { _, event, userData in
        guard let userData, Thread.isMainThread else {
            return OSStatus(eventNotHandledErr)
        }
        let interceptor = Unmanaged<ActiveCaptureEscapeInterceptor>.fromOpaque(userData).takeUnretainedValue()
        let eventAddress = event.map { UInt(bitPattern: $0) }
        return MainActor.assumeIsolated {
            interceptor.handleHotKey(eventAddress.flatMap { EventRef(bitPattern: $0) })
        }
    }
}

/// Temporarily suspends active global shortcuts (both Carbon chords and
/// modifier-tap monitors) while a Settings or Onboarding recorder is active.
@MainActor
enum GlobalShortcutRecordingSuspension {
    private static var isSuspended = false
    private static var suspendedActions: [GlobalShortcutAction] = []

    static func begin() {
        guard !isSuspended else { return }
        isSuspended = true
        suspendedActions = GlobalShortcutAction.allCases.filter {
            KeyboardShortcuts.isEnabled(for: $0.keyboardShortcutName)
        }
        let names = suspendedActions.map(\.keyboardShortcutName)
        if !names.isEmpty {
            KeyboardShortcuts.disable(names)
        }
        GlobalModifierDispatcher.shared.isSuspended = true
        GlobalModifierDispatcher.shared.reset()
    }

    static func end() {
        guard isSuspended else { return }
        isSuspended = false
        let toRestore = suspendedActions.filter { action in
            !action.isVoiceAction || VoiceCapture.shared.enabled
        }
        suspendedActions = []
        let names = toRestore.map(\.keyboardShortcutName)
        if !names.isEmpty {
            KeyboardShortcuts.enable(names)
        }
        GlobalModifierDispatcher.shared.isSuspended = false
        GlobalModifierDispatcher.shared.reset()
    }
}

/// Pure event state machine for capturing either a key chord or a single modifier tap.
@MainActor
final class UnifiedShortcutRecorderModel: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var pendingModifier: ModifierShortcut?
    @Published var errorMessage: String?

    private static weak var activeRecorder: UnifiedShortcutRecorderModel?

    private let action: GlobalShortcutAction
    private let store: GlobalShortcutStore
    private var modifierInterfered = false
    private nonisolated(unsafe) var monitor: Any?
    private nonisolated(unsafe) var resignObserver: (any NSObjectProtocol)?
    private weak var anchorView: NSView?

    init(action: GlobalShortcutAction, store: GlobalShortcutStore = .shared) {
        self.action = action
        self.store = store
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    func attachAnchor(_ view: NSView) {
        anchorView = view
    }

    func toggle() {
        if isRecording {
            cancel()
        } else {
            begin()
        }
    }

    func begin() {
        if let active = Self.activeRecorder, active !== self {
            active.cancel()
        }
        endMonitor()
        Self.activeRecorder = self
        errorMessage = nil
        pendingModifier = nil
        modifierInterfered = false
        isRecording = true

        GlobalShortcutRecordingSuspension.begin()

        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            let consume = MainActor.assumeIsolated {
                self?.processEvent(event) ?? false
            }
            return consume ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cancel()
            }
        }
    }

    func cancel() {
        endMonitor()
        isRecording = false
        pendingModifier = nil
        modifierInterfered = false
    }

    // MARK: - Testable Input Processing

    /// Processes a synthetic or real key press during recording. Returns `true` if consumed.
    @discardableResult
    func handleKeyInput(
        keyCode: Int,
        modifiers: NSEvent.ModifierFlags,
        chordCandidate: KeyboardShortcuts.Shortcut?
    ) -> Bool {
        guard isRecording else { return false }

        pendingModifier = nil
        modifierInterfered = true

        let mods = modifiers.intersection([.command, .option, .control, .shift])

        // Esc (bare) cancels recording without modifying the current shortcut.
        if keyCode == kVK_Escape && mods.isEmpty {
            cancel()
            return true
        }

        // Delete / Forward Delete (bare) clears the current shortcut.
        if (keyCode == kVK_Delete || keyCode == kVK_ForwardDelete) && mods.isEmpty {
            errorMessage = store.set(nil, for: action)
            endRecordingAfterCommit()
            return true
        }

        if let chord = chordCandidate {
            errorMessage = store.set(.chord(chord), for: action)
            endRecordingAfterCommit()
            return true
        }

        errorMessage = "Include ⌘, ⌥, or ⌃, or choose a function key."
        NSSound.beep()
        endRecordingAfterCommit()
        return true
    }

    /// Processes modifier flag changes to recognize a clean single-modifier tap.
    func handleModifierFlags(_ flags: NSEvent.ModifierFlags) {
        guard isRecording else { return }
        let relevant = flags.intersection(ModifierShortcut.relevantMask)
        if relevant.isEmpty {
            if !modifierInterfered, let modifier = pendingModifier {
                errorMessage = store.set(.modifier(modifier), for: action)
                endRecordingAfterCommit()
                return
            }
            pendingModifier = nil
            modifierInterfered = false
            return
        }

        if let exclusive = ModifierShortcut.exclusive(in: relevant) {
            if pendingModifier == nil && !modifierInterfered {
                pendingModifier = exclusive
            } else if pendingModifier != exclusive {
                pendingModifier = nil
                modifierInterfered = true
            }
        } else {
            pendingModifier = nil
            modifierInterfered = true
        }
    }

    private func processEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            let chord = KeyboardShortcuts.Shortcut(event: event)
            return handleKeyInput(
                keyCode: Int(event.keyCode),
                modifiers: event.modifierFlags,
                chordCandidate: chord
            )
        case .flagsChanged:
            handleModifierFlags(event.modifierFlags)
            return false
        case .leftMouseDown, .rightMouseDown:
            if let anchorView,
               event.window === anchorView.window {
                let point = anchorView.convert(event.locationInWindow, from: nil)
                if anchorView.bounds.contains(point) {
                    // Let the button handle the toggle click cleanly.
                    return false
                }
            }
            cancel()
            return false
        default:
            return false
        }
    }

    private func endRecordingAfterCommit() {
        endMonitor()
        isRecording = false
        pendingModifier = nil
        modifierInterfered = false
    }

    private func endMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if Self.activeRecorder === self {
            Self.activeRecorder = nil
            GlobalShortcutRecordingSuspension.end()
        }
    }
}

/// Single control that captures either a conventional key chord (`⌥\`, `F5`) or a
/// single modifier tap (`⌥`, `⌃`, `⇧`, `⌘`) cleanly inside SwiftUI.
struct UnifiedShortcutRecorder: View {
    let action: GlobalShortcutAction
    var prominent: Bool = false
    var showsValidationError: Bool = true
    var showsClearButton: Bool = true

    @StateObject private var model: UnifiedShortcutRecorderModel

    init(
        action: GlobalShortcutAction,
        prominent: Bool = false,
        showsValidationError: Bool = true,
        showsClearButton: Bool = true
    ) {
        self.action = action
        self.prominent = prominent
        self.showsValidationError = showsValidationError
        self.showsClearButton = showsClearButton
        _model = StateObject(wrappedValue: UnifiedShortcutRecorderModel(action: action))
    }

    var body: some View {
        UnifiedShortcutControl(
            action: action,
            model: model,
            prominent: prominent,
            showsValidationError: showsValidationError,
            showsClearButton: showsClearButton
        )
    }
}

/// Companion settings row with title, optional subtitle, recorder, Reset, and inline error.
struct UnifiedShortcutRow: View {
    let action: GlobalShortcutAction
    let title: String
    let subtitle: String?
    var showsRestoreDefault: Bool = true
    var onRestore: (() -> Void)? = nil

    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var store = GlobalShortcutStore.shared
    @StateObject private var model: UnifiedShortcutRecorderModel

    init(
        action: GlobalShortcutAction,
        title: String? = nil,
        subtitle: String? = nil,
        showsRestoreDefault: Bool = true,
        onRestore: (() -> Void)? = nil
    ) {
        self.action = action
        self.title = title ?? action.title
        self.subtitle = subtitle ?? action.subtitle
        self.showsRestoreDefault = showsRestoreDefault
        self.onRestore = onRestore
        _model = StateObject(wrappedValue: UnifiedShortcutRecorderModel(action: action))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText(for: colorScheme))
                    }
                }
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    UnifiedShortcutControl(
                        action: action,
                        model: model,
                        prominent: false,
                        showsValidationError: false,
                        showsClearButton: true
                    )

                    if showsRestoreDefault && !store.isUsingDefault(for: action) && !model.isRecording {
                        Button("Reset") {
                            model.errorMessage = nil
                            if !store.restoreDefault(for: action) {
                                model.errorMessage = "Default shortcut is already used by another action."
                            }
                            onRestore?()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText(for: colorScheme))
                        .help("Restore default shortcut")
                    }
                }
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(palette.destructiveText(for: colorScheme))
            }
        }
    }
}

private struct UnifiedShortcutControl: View {
    let action: GlobalShortcutAction
    @ObservedObject var model: UnifiedShortcutRecorderModel
    let prominent: Bool
    let showsValidationError: Bool
    let showsClearButton: Bool

    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var store = GlobalShortcutStore.shared

    private var currentTrigger: GlobalShortcutTrigger? {
        store.trigger(for: action)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    model.toggle()
                } label: {
                    Text(buttonLabel)
                        .font(.system(size: prominent ? 13 : 12, weight: .medium))
                        .foregroundStyle(labelColor)
                        .monospacedDigit()
                        .lineLimit(1)
                        .padding(.horizontal, prominent ? 14 : 10)
                        .padding(.vertical, prominent ? 6 : 4)
                        .frame(minWidth: prominent ? 168 : 132)
                        .background(backgroundShape)
                }
                .buttonStyle(.plain)
                .background(RecorderAnchorView { view in
                    model.attachAnchor(view)
                })
                .accessibilityLabel("\(action.title) shortcut")
                .accessibilityValue(currentTrigger?.accessibilityLabel ?? "None")
                .accessibilityHint(model.isRecording
                    ? "Press a key shortcut, tap a modifier key, Delete to clear, or Escape to cancel"
                    : "Activate to record a shortcut or single modifier")

                if showsClearButton && currentTrigger != nil && !model.isRecording {
                    Button {
                        model.errorMessage = store.set(nil, for: action)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.secondaryText(for: colorScheme))
                    }
                    .buttonStyle(.plain)
                    .help("Clear \(action.title) shortcut")
                    .accessibilityLabel("Clear \(action.title) shortcut")
                }
            }

            if showsValidationError, let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(palette.destructiveText(for: colorScheme))
            }
        }
        .onDisappear {
            model.cancel()
        }
    }

    private var buttonLabel: String {
        if model.isRecording {
            if let pending = model.pendingModifier {
                return "\(pending.displayString) …"
            }
            return "Press shortcut…"
        }
        return currentTrigger?.displayString ?? "Record Shortcut"
    }

    private var labelColor: Color {
        if model.isRecording || currentTrigger != nil {
            return palette.noteText(for: colorScheme)
        }
        return palette.secondaryText(for: colorScheme)
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: prominent ? 8 : 6, style: .continuous)
            .fill(palette.subtleFill(for: colorScheme))
            .overlay {
                RoundedRectangle(cornerRadius: prominent ? 8 : 6, style: .continuous)
                    .strokeBorder(
                        model.isRecording
                            ? palette.focus(for: colorScheme)
                            : palette.border(for: colorScheme).opacity(colorScheme == .dark ? 0.9 : 0.7),
                        lineWidth: model.isRecording ? 1.5 : 1
                    )
            }
    }
}

private struct RecorderAnchorView: NSViewRepresentable {
    let onAttach: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            onAttach(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        onAttach(nsView)
    }
}
