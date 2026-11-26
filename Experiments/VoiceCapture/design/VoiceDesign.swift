import AppKit
import SwiftUI
#if canImport(KeyboardShortcuts)
import KeyboardShortcuts
#endif

private enum Concept: String, CaseIterable, Identifiable {
    case capsule = "Floating capsule"
    case live = "Live thought"
    case menu = "Menu bar"
    case scratchpad = "Scratchpad"
    var id: Self { self }
    var insight: String {
        switch self {
        case .capsule: "Keep the current app in focus. Show when the microphone is ready and when the thought is saved."
        case .live: "Make recognition visible during speech. Keep provisional text distinct from finished segments."
        case .menu: "Make recording findable from the menu bar. Check whether the indicator stays visible in fullscreen."
        case .scratchpad: "Put the spoken text in a new editor for review. Leave any open thought intact."
        }
    }
}

private enum Stage: String, CaseIterable, Identifiable {
    case setup = "First use"
    case assets = "Preparing language"
    case preparing = "Starting microphone"
    case recording = "Listening"
    case finishing = "Finishing transcription"
    case saving = "Saving thought"
    case kept = "Kept"
    case review = "Review before keeping"
    case opened = "Open kept thought"
    case undone = "Capture undone"
    case cancelled = "Cancelled"
    case silence = "No speech heard"
    case denied = "Microphone access is off"
    case unavailable = "Voice Capture unavailable"
    case interrupted = "Recording interrupted"
    case transcription = "Couldn’t transcribe"
    case persistence = "Couldn’t save"
    var id: Self { self }
    var detail: String? {
        switch self {
        case .setup: "Speak a thought and find it in Home. Transcription runs on this Mac."
        case .assets: "Rasc needs the speech files for Português (Brasil)."
        case .denied: "Allow Rasc to use your microphone in System Settings."
        case .unavailable: "This Mac can’t transcribe this language with Voice Capture."
        case .interrupted: "The microphone disconnected. Review what Rasc heard."
        case .transcription: "Your audio is available to retry while Rasc is open."
        case .persistence: "Your transcript is still here. Retry saving or copy the text."
        default: nil
        }
    }
    var symbol: String {
        switch self {
        case .preparing: "mic"
        case .recording: "mic.fill"
        case .kept: "checkmark"
        case .cancelled, .undone: "xmark"
        case .silence, .denied: "mic.slash"
        case .unavailable, .interrupted, .transcription, .persistence: "exclamationmark"
        case .review, .opened: "text.alignleft"
        default: "ellipsis"
        }
    }
    var showsErrorDetail: Bool { [.denied, .unavailable, .interrupted, .transcription, .persistence].contains(self) }
    var offersCancel: Bool { [.assets, .preparing, .recording, .finishing].contains(self) }
}

private let sample = "Talvez seja a migração. Preciso conferir o log antes de reiniciar o worker."

private struct VoiceSurface: View {
    var concept: Concept
    var stage: Stage
    var action: @MainActor (Stage) -> Void = { _ in }
    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if [.review, .opened].contains(stage) || (concept == .scratchpad && stage != .setup && stage != .assets && !stage.showsErrorDetail) {
                scratchpad
            } else if stage == .setup || stage == .assets || stage.showsErrorDetail {
                expanded
            } else {
                switch concept {
                case .capsule: capsule
                case .live: live
                case .menu: menu
                case .scratchpad: scratchpad
                }
            }
        }
        .foregroundStyle(palette.noteText(for: scheme))
        .accessibilityElement(children: .contain)
    }

    private func shell<V: View>(
        width: CGFloat, radius: CGFloat = 16, @ViewBuilder _ interior: () -> V
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return interior()
            .frame(width: width)
            .background(palette.canvas(for: scheme), in: shape)
            .overlay { shape.strokeBorder(palette.border(for: scheme), lineWidth: contrast == .increased ? 2 : 1) }
            .clipShape(shape)
            .shadow(color: .black.opacity(scheme == .dark ? 0.26 : 0.12), radius: 16, y: 7)
    }

    private var stateLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: stage.symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(stage.rawValue).font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(stage == .kept ? palette.keepAccent(for: scheme) : palette.noteText(for: scheme))
        .padding(.horizontal, stage == .kept ? 8 : 0)
        .padding(.vertical, stage == .kept ? 4 : 0)
        .background(stage == .kept ? palette.keepFill(for: scheme) : .clear, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func link(_ label: String, _ next: Stage, symbol: String? = nil) -> some View {
        Button {
            action(next)
        } label: {
            Group {
                if let symbol {
                    Image(systemName: symbol).frame(width: 14)
                } else {
                    Text(label)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .frame(minWidth: 40, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.secondaryText(for: scheme))
        .accessibilityLabel(label)
        .help(label)
    }

    @ViewBuilder private var recordingActions: some View {
        if stage == .recording {
            link("Finish", .finishing, symbol: "stop.fill")
            link("Cancel recording", .cancelled, symbol: "xmark")
        } else if stage.offersCancel {
            link("Cancel recording", .cancelled, symbol: "xmark")
        } else if stage == .kept {
            link("Open", .opened)
            link("Undo", .undone)
        }
    }

    private var capsule: some View {
        shell(width: 268, radius: 22) {
            HStack(spacing: 6) {
                stateLabel
                Spacer(minLength: 6)
                if stage == .recording {
                    Text("0:08")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(palette.metadataText(for: scheme))
                        .accessibilityLabel("8 seconds")
                }
                recordingActions
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(minHeight: 48)
        }
    }

    private var live: some View {
        shell(width: 375) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 2) {
                    stateLabel
                    Spacer()
                    recordingActions
                }
                .frame(minHeight: 44)
                Divider()
                if [.recording, .finishing, .saving, .kept].contains(stage) {
                    VStack(alignment: .leading, spacing: 6) {
                        if stage == .recording {
                            Text("Talvez seja a migração.").font(.system(size: 16))
                            Text("Preciso conferir o log antes de…")
                                .font(.system(size: 16))
                                .foregroundStyle(palette.secondaryText(for: scheme))
                                .accessibilityLabel("Provisional transcript")
                        } else {
                            Text(sample).font(.system(size: 16))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 14)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var menu: some View {
        VStack(alignment: .trailing, spacing: 7) {
            HStack(spacing: 13) {
                Spacer()
                Text("Rasc").font(.system(size: 13, weight: .semibold))
                Image(systemName: "mic.fill").font(.system(size: 12))
                Text("9:41").monospacedDigit()
            }
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(palette.subtleFill(for: scheme), in: RoundedRectangle(cornerRadius: 6))
            shell(width: 234, radius: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    stateLabel.padding(.top, 13).padding(.bottom, 10)
                    Divider()
                    if stage == .recording {
                        menuItem("Finish recording", "■", .finishing)
                        menuItem("Cancel recording", "×", .cancelled)
                    } else if stage == .kept {
                        menuItem("Open thought", "↗", .opened)
                        menuItem("Undo capture", "↶", .undone)
                    } else {
                        menuItem("Voice Capture", "↵", .preparing)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 5)
            }
            .padding(.trailing, 24)
        }
        .frame(width: 308)
    }

    private func menuItem(_ label: String, _ symbol: String, _ next: Stage) -> some View {
        Button {
            action(next)
        } label: {
            HStack {
                Text(label)
                Spacer()
                Text(symbol).foregroundStyle(palette.metadataText(for: scheme))
            }
            .font(.system(size: 13))
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var scratchpad: some View {
        shell(width: 384) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    if stage == .review || stage == .opened {
                        Text(stage == .opened ? "Thought" : "New thought").font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.secondaryText(for: scheme))
                    } else {
                        stateLabel
                    }
                    Spacer()
                    if stage == .opened {
                        Text("Kept").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.keepAccent(for: scheme))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(palette.keepFill(for: scheme), in: Capsule())
                    } else if stage == .review {
                        Button { action(.kept) } label: {
                            Text("Keep").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.keepAccent(for: scheme))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(palette.keepFill(for: scheme), in: Capsule())
                                .frame(minHeight: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        recordingActions
                    }
                }
                .frame(minHeight: 44)
                Divider()
                Text(stage == .recording ? "Talvez seja a migração…" : sample)
                    .font(.system(size: 16))
                    .lineSpacing(4.5)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .padding(.vertical, 17)
            }
            .padding(.horizontal, 17)
            .frame(height: 141)
        }
    }

    private var expanded: some View {
        shell(width: 360) {
            VStack(alignment: .leading, spacing: 10) {
                if stage == .setup {
                    Label("Voice Capture", systemImage: "mic").font(.title3.weight(.semibold))
                } else {
                    stateLabel
                }
                if let detail = stage.detail {
                    Text(detail).font(.callout)
                        .foregroundStyle(palette.secondaryText(for: scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if stage == .setup {
                    HStack {
                        Text("Language").foregroundStyle(palette.secondaryText(for: scheme))
                        Spacer()
                        Text("Português (Brasil)")
                    }
                    .font(.system(size: 12))
                    .padding(.vertical, 4)
                }
                if stage == .assets {
                    HStack(spacing: 10) {
                        GeometryReader { geometry in
                            Capsule().fill(palette.subtleFill(for: scheme))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(palette.actionPrimaryFill(for: scheme))
                                        .frame(width: geometry.size.width * 0.44)
                                }
                        }
                        .frame(height: 4)
                        Text("44%").font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(palette.metadataText(for: scheme))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Language download")
                    .accessibilityValue("44 percent")
                }
                if stage == .persistence || stage == .interrupted {
                    Text(sample).font(.system(size: 14))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 13) { expandedActions }
            }
            .padding(16)
        }
    }

    @ViewBuilder private var expandedActions: some View {
        switch stage {
        case .setup: link("Continue", .assets); link("Cancel", .cancelled)
        case .assets: link("Cancel", .cancelled)
        case .denied: link("Open System Settings", .setup); link("Dismiss", .cancelled)
        case .transcription: link("Retry transcription", .finishing); link("Discard", .cancelled)
        case .persistence: link("Retry save", .saving); link("Copy text", .review)
        case .interrupted: link("Review text", .review); link("Discard", .cancelled)
        default: link("Dismiss", .cancelled)
        }
    }
}

private struct DesignBoard: View {
    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Voice Capture").font(.system(size: 32, weight: .semibold))
                Text("Four ways to speak a thought").font(.system(size: 14))
                    .foregroundStyle(palette.secondaryText(for: scheme))
            }
            HStack(alignment: .top, spacing: 16) {
                boardTile(.capsule, stage: .recording)
                boardTile(.live, stage: .recording)
            }
            HStack(alignment: .top, spacing: 16) {
                boardTile(.menu, stage: .recording)
                boardTile(.scratchpad, stage: .review)
            }
            HStack(spacing: 18) {
                Text("After finishing").font(.system(size: 14, weight: .semibold))
                VoiceSurface(concept: .capsule, stage: .kept)
                Text("Open the thought or undo the capture.")
                    .font(.system(size: 13)).foregroundStyle(palette.secondaryText(for: scheme))
            }
            .padding(.top, 3)
        }
        .padding(27)
        .frame(width: 932, alignment: .leading)
        .foregroundStyle(palette.noteText(for: scheme))
        .background(palette.canvas(for: scheme))
    }

    private func boardTile(_ concept: Concept, stage: Stage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(concept.rawValue).font(.system(size: 15, weight: .semibold))
                Text(concept.insight).font(.system(size: 12))
                    .foregroundStyle(palette.secondaryText(for: scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 53, alignment: .topLeading)
            VoiceSurface(concept: concept, stage: stage)
                .frame(width: 406, height: 153)
                .background(palette.subtleFill(for: scheme), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(12)
        .background(palette.raisedFill(for: scheme), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(palette.border(for: scheme)) }
    }
}

private struct JourneyBoard: View {
    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Capture and recovery").font(.system(size: 30, weight: .semibold))
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 18) {
                    VoiceSurface(concept: .capsule, stage: .setup)
                    VoiceSurface(concept: .capsule, stage: .assets)
                    VoiceSurface(concept: .capsule, stage: .denied)
                    VoiceSurface(concept: .capsule, stage: .unavailable)
                }
                VStack(alignment: .leading, spacing: 18) {
                    VoiceSurface(concept: .capsule, stage: .preparing)
                    VoiceSurface(concept: .capsule, stage: .recording)
                    VoiceSurface(concept: .capsule, stage: .finishing)
                    VoiceSurface(concept: .capsule, stage: .saving)
                    VoiceSurface(concept: .capsule, stage: .kept)
                    VoiceSurface(concept: .capsule, stage: .silence)
                    VoiceSurface(concept: .capsule, stage: .cancelled)
                    VoiceSurface(concept: .capsule, stage: .undone)
                }
                VStack(alignment: .leading, spacing: 18) {
                    VoiceSurface(concept: .capsule, stage: .interrupted)
                    VoiceSurface(concept: .capsule, stage: .transcription)
                    VoiceSurface(concept: .capsule, stage: .persistence)
                    VoiceSurface(concept: .capsule, stage: .review)
                    VoiceSurface(concept: .capsule, stage: .opened)
                }
            }
        }
        .padding(27)
        .foregroundStyle(palette.noteText(for: scheme))
        .background(palette.canvas(for: scheme))
    }
}

private final class DemoPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class DesignSession: ObservableObject {
    @Published var stage: Stage = .setup
    @Published var concept: Concept = .capsule
    @Published var theme: ThemePreset = .graphitePaper
    @Published var hotkeyEnabled = false { didSet { updateHotkey() } }
    @Published var hotkeyEvents: [String] = []
    private var panel: DemoPanel?
    private var work: Task<Void, Never>?
    private var held = false

    func select(_ next: Stage) {
        work?.cancel()
        stage = next
    }

    func transition(_ next: Stage) {
        select(next)
        let destination: Stage
        switch next {
        case .assets: destination = .preparing
        case .preparing: destination = .recording
        case .finishing: destination = .saving
        case .saving: destination = .kept
        default: return
        }
        work = Task { [weak self] in
            try? await Task.sleep(for: next == .assets ? .seconds(2) : .milliseconds(480))
            guard !Task.isCancelled else { return }
            self?.transition(destination)
        }
    }

    func demonstratePanel() {
        let variant = concept
        let width: CGFloat = variant == .capsule ? 280 : 400
        let height: CGFloat = variant == .capsule ? 62 : 200
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = panel ?? DemoPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                        backing: .buffered, defer: false)
        window.setContentSize(frame.size)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = NSHostingView(rootView: PanelContent(session: self))
        let pointer = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.minY + 50))
        }
        let activePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let start = ContinuousClock.now
        window.orderFrontRegardless()
        panel = window
        let elapsed = start.duration(to: .now).components
        let milliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
        log("orderFront returned in \(String(format: "%.1f", milliseconds)) ms")
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            self?.log("Frontmost app unchanged: \(activePID != nil && NSWorkspace.shared.frontmostApplication?.processIdentifier == activePID), panel key: \(window.isKeyWindow), panel visible: \(window.isVisible)")
        }
    }

    func hidePanel() { panel?.orderOut(nil) }

    private func log(_ entry: String) {
        hotkeyEvents.append(entry)
        if hotkeyEvents.count > 8 { hotkeyEvents.removeFirst() }
        print(entry)
        fflush(nil)
    }

    private func updateHotkey() {
        #if canImport(KeyboardShortcuts)
        KeyboardShortcuts.removeAllHandlers()
        held = false
        guard hotkeyEnabled else { return }
        KeyboardShortcuts.onKeyDown(for: .voiceLab) { [weak self] in
            guard let self else { return }
            self.log("Hotkey down, repeat: \(self.held)")
            self.held = true
        }
        KeyboardShortcuts.onKeyUp(for: .voiceLab) { [weak self] in
            guard let self else { return }
            self.log("Hotkey up, previously down: \(self.held)")
            guard self.held else { return }
            self.held = false
            switch self.stage {
            case .recording:
                self.log("Hotkey action: finish")
                self.transition(.finishing)
            case .preparing, .finishing, .saving, .assets:
                self.log("Hotkey action: ignored busy")
            default:
                self.log("Hotkey action: start")
                self.concept = .capsule
                self.transition(.preparing)
                self.demonstratePanel()
            }
        }
        #endif
    }
}

#if canImport(KeyboardShortcuts)
private extension KeyboardShortcuts.Name {
    static let voiceLab = Self("testVoiceCapture", initial: .init(.f9, modifiers: [.control, .option]))
}
#endif

private struct PanelContent: View {
    @ObservedObject var session: DesignSession
    var body: some View {
        VoiceSurface(concept: session.concept, stage: session.stage, action: { next in session.transition(next) })
            .environment(\.rascPalette, RascSurfacePalette(preset: session.theme))
    }
}

private struct DesignLab: View {
    @StateObject private var session = DesignSession()
    @State private var dark = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Voice Capture").font(.title2.weight(.semibold))
                Picker("Concept", selection: $session.concept) {
                    ForEach(Concept.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("State", selection: Binding(get: { session.stage }, set: { next in session.select(next) })) {
                    ForEach(Stage.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Rasc theme", selection: $session.theme) {
                    ForEach(ThemePreset.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Dark appearance", isOn: $dark)
                Divider()
                Button("Show non-key panel") { session.demonstratePanel() }
                Button("Hide panel") { session.hidePanel() }
                #if canImport(KeyboardShortcuts)
                Toggle("Enable experimental shortcut", isOn: $session.hotkeyEnabled)
                if session.hotkeyEnabled {
                    KeyboardShortcuts.Recorder("Shortcut", name: .voiceLab)
                }
                #endif
                ForEach(Array(session.hotkeyEvents.enumerated()), id: \.offset) { _, entry in
                    Text(entry).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Simulated capture with sample text.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(width: 255)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text(session.concept.insight)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(0.4))
                    VoiceSurface(concept: session.concept, stage: session.stage, action: { next in session.transition(next) })
                }
                .frame(minWidth: 416, minHeight: 377)
            }
            .padding(22)
            .environment(\.rascPalette, RascSurfacePalette(preset: session.theme))
        }
        .preferredColorScheme(dark ? .dark : .light)
        .frame(minWidth: 725, minHeight: 475)
    }
}

@main
struct VoiceDesign: App {
    init() {
        let args = CommandLine.arguments
        #if canImport(KeyboardShortcuts)
        if args.contains("--hotkey-smoke") {
            NSApplication.shared.setActivationPolicy(.accessory)
            let session = DesignSession()
            KeyboardShortcuts.setShortcut(.init(.f19, modifiers: [.command, .control, .shift]), for: .voiceLab)
            session.select(.cancelled)
            session.hotkeyEnabled = true
            print("Hotkey probe ready, registered: \(KeyboardShortcuts.isEnabled(for: .voiceLab))")
            fflush(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                session.hidePanel()
                session.hotkeyEnabled = false
                KeyboardShortcuts.reset(.voiceLab)
                exit(0)
            }
            NSApplication.shared.run()
            exit(0)
        }
        #endif
        if args.contains("--focus-smoke") {
            NSApplication.shared.setActivationPolicy(.accessory)
            let session = DesignSession()
            session.select(.recording)
            session.demonstratePanel()
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            session.hidePanel()
            exit(0)
        }
        guard let index = args.firstIndex(of: "--render"), args.count > index + 1 else { return }
        let directory = args[index + 1] == "@container"
            ? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "DesignRenders", directoryHint: .isDirectory)
            : URL(fileURLWithPath: args[index + 1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.render(DesignBoard(), appearance: .light, output: directory.appending(path: "concepts-light.png"))
            try Self.render(DesignBoard(), appearance: .dark, output: directory.appending(path: "concepts-dark.png"))
            try Self.render(JourneyBoard(), appearance: .light, output: directory.appending(path: "journey-light.png"))
            try Self.render(JourneyBoard(), appearance: .dark, output: directory.appending(path: "journey-dark.png"))
            exit(0)
        } catch {
            fputs("\(error)\n", stderr)
            exit(1)
        }
    }

    var body: some Scene {
        WindowGroup("Rasc Voice Capture Lab") { DesignLab() }
            .defaultSize(width: 735, height: 520)
    }

    @MainActor
    private static func render<V: View>(_ view: V, appearance: ColorScheme, output: URL) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, appearance))
        renderer.scale = 2
        guard let cgImage = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: output)
    }
}
