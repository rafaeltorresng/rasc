import AppKit
import AVFoundation
import Foundation
import KeyboardShortcuts
import Observation

extension KeyboardShortcuts.Name {
    static let voiceStudy = Self("rascVoiceStudy")
}

enum Activation: String, CaseIterable, Identifiable {
    case toggle = "Press to start and finish"
    case hold = "Hold to speak"
    var id: Self { self }
}

enum Completion: String, CaseIterable, Identifiable {
    case review = "Review before Keep"
    case quiet = "Keep with confirmation"
    case receipt = "Keep with Open and Undo"
    var id: Self { self }
}

@MainActor @Observable
final class StudySession {
    enum Phase: Equatable {
        case idle, requesting, starting, listening, finishing, review, saving, kept, notice(String), failure(String)
        var text: String {
            switch self {
            case .idle: "Ready to record"
            case .requesting: "Preparing Voice Capture"
            case .starting: "Starting microphone"
            case .listening: "Listening"
            case .finishing: "Transcribing"
            case .review: "Review thought"
            case .saving: "Saving"
            case .kept: "Kept"
            case let .notice(message), let .failure(message): message
            }
        }
    }

    private(set) var phase: Phase = .idle
    var selectedEngine: StudyEngine = .apple {
        didSet { Task { await recognizer.releaseLoadedModel() } }
    }
    var language = "pt-BR"
    var activation: Activation = .toggle
    var completion: Completion = .review
    var theme: ThemePreset = .graphitePaper
    var globalShortcut = false { didSet { setShortcut() } }
    var draft = ""
    var draftIssue: String?
    var edited = ""
    var raw = ""
    var notes: [Note] = []
    var opened: Note?
    var showingOptions = false
    var notice: String?
    var level: Float = 0
    var duration: Double = 0
    var modelReady = false
    private var storageReady = false
    var metrics: [String: Double] = [:]
    private(set) var receipt: Note?
    private(set) var hasAudio = false

    @ObservationIgnored private var repo: NoteRepository?
    @ObservationIgnored private var directory: URL?
    @ObservationIgnored private let testFolder: URL?
    @ObservationIgnored private let mic = Microphone()
    @ObservationIgnored private let recognizer = StudyRecognizer()
    @ObservationIgnored private var capture: Capture?
    @ObservationIgnored private var activeBuffer: MicBuffer?
    @ObservationIgnored private var audio: StudyAudio?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var meter: Task<Void, Never>?
    @ObservationIgnored private var dismiss: Task<Void, Never>?
    @ObservationIgnored private var draftSave: Task<Void, Never>?
    @ObservationIgnored private var keyIsDown = false
    @ObservationIgnored private var endingAudio = false
    @ObservationIgnored private var draftMutation = 0
    @ObservationIgnored var presentStatus: (() -> Void)?
    @ObservationIgnored var hideStatus: (() -> Void)?
    @ObservationIgnored var showStudy: (() -> Void)?

    private struct Capture {
        let id = UUID()
        let start = ContinuousClock.now
        let engine: StudyEngine
        let language: String
        let completion: Completion
        var ended: ContinuousClock.Instant?
        var interrupted = false
    }

    init(folder: URL? = nil) {
        testFolder = folder
        globalShortcut = folder == nil && UserDefaults.standard.bool(forKey: "studyShortcutEnabled")
    }

    func load() async {
        let folder = testFolder
        do {
            let (base, opened) = try await Task.detached(priority: .userInitiated) {
                let target = if let folder { folder } else {
                    try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)
                        .appending(path: "Rasc Voice Study", directoryHint: .isDirectory)
                }
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                return (target, try NoteRepository(databaseURL: target.appending(path: "Study.sqlite")))
            }.value
            directory = base
            repo = opened
            let saved = try await opened.loadStudyDraft()
            if draftMutation == 0 { draft = saved }
            notes = try await opened.fetchAllNonDeleted().filter(\.isKept)
            storageReady = true
            setShortcut()
        } catch {
            draftIssue = "The study database couldn’t open."
        }
        await checkModel()
    }

    func checkModel() async {
        let engine = selectedEngine
        let locale = language
        let ready = (try? await StudyRecognizer.ready(engine, language: locale)) ?? false
        if engine == selectedEngine, locale == language { modelReady = ready }
    }

    func prepareModel() {
        guard phase == .idle || phase == .kept || isPassiveNotice else { return }
        let locale = language
        let engine = selectedEngine
        phase = .requesting
        notice = nil
        work = Task {
            do {
                if engine == .apple {
                    try await StudyRecognizer.installApple(language: locale)
                } else {
                    try await recognizer.preparePortable(engine)
                }
                try Task.checkCancellation()
                await checkModel()
                phase = .idle
                notice = engine == .apple ? "Speech model ready." : "Model prepared for your next recording."
            } catch {
                if !Task.isCancelled { phase = .notice("The speech model couldn’t be prepared.") }
            }
        }
    }

    private var isPassiveNotice: Bool {
        if case .notice = phase { return true }
        return false
    }

    var canStart: Bool { storageReady && !endingAudio && (phase == .idle || phase == .kept || isPassiveNotice) }
    var optionsEnabled: Bool { canStart && capture == nil || phase == .kept }
    var canCancel: Bool {
        switch phase {
        case .requesting, .starting, .listening, .finishing, .review, .failure: true
        default: false
        }
    }
    var canRetry: Bool { if case .failure = phase { return hasAudio }; return false }
    var canRetryWrite: Bool { if case .failure = phase { return !edited.isEmpty && capture != nil }; return false }

    func saveDraft(_ text: String) {
        draftMutation += 1
        let version = draftMutation
        draftSave?.cancel()
        draftSave = Task {
            do {
                try await Task.sleep(for: .milliseconds(220))
                guard version == draftMutation else { return }
                try await repo?.saveStudyDraft(text)
                if version == draftMutation { draftIssue = nil }
            } catch is CancellationError { }
            catch { if version == draftMutation { draftIssue = "The scratch couldn’t save." } }
        }
    }

    func prepareToQuit() async -> Bool {
        guard capture == nil || phase == .kept else { return false }
        draftSave?.cancel()
        do { try await repo?.saveStudyDraft(draft); return true }
        catch { draftIssue = "The scratch couldn’t save."; return false }
    }

    func shortcutAction() {
        if canStart { start() }
        else if phase == .listening || phase == .starting { finish() }
    }

    func start() {
        guard canStart else { return }
        dismiss?.cancel()
        notice = nil
        raw = ""
        edited = ""
        audio = nil
        hasAudio = false
        level = 0
        duration = 0
        let new = Capture(engine: selectedEngine, language: language, completion: completion)
        capture = new
        metrics = [:]
        phase = .starting
        presentStatus?()
        metrics["Status request"] = milliseconds(new.start)
        work = Task {
            do {
                guard try await StudyRecognizer.ready(new.engine, language: new.language) else {
                    throw RecognitionIssue.needsSetup
                }
                guard capture?.id == new.id else { return }
                let permission = AVCaptureDevice.authorizationStatus(for: .audio)
                if permission == .notDetermined {
                    hideStatus?()
                    showStudy?()
                    phase = .requesting
                    let allowed = await AVCaptureDevice.requestAccess(for: .audio)
                    guard capture?.id == new.id else { return }
                    capture = nil
                    notice = allowed ? "Microphone ready. Start when you’re ready to speak." :
                        "Allow microphone access in System Settings, then Start again."
                    phase = .idle
                    return
                }
                guard permission == .authorized else {
                    capture = nil
                    notice = "Microphone access is turned off. Allow access in System Settings."
                    phase = .idle
                    hideStatus?()
                    showStudy?()
                    return
                }
                let buffer = try await mic.start(id: new.id) { [weak self] in
                    Task { @MainActor in
                        guard self?.capture?.id == new.id else { return }
                        self?.finish(interrupted: true)
                    }
                }
                guard capture?.id == new.id, !Task.isCancelled, phase == .starting else {
                    await mic.stop(id: new.id)
                    return
                }
                activeBuffer = buffer
                monitor(buffer, capture: new)
            } catch {
                guard capture?.id == new.id, !Task.isCancelled else { return }
                capture = nil
                phase = .notice(error.localizedDescription)
                hideStatus?()
                showStudy?()
            }
        }
    }

    private func monitor(_ buffer: MicBuffer, capture: Capture) {
        meter?.cancel()
        meter = Task {
            while !Task.isCancelled, self.capture?.id == capture.id {
                let status = buffer.status()
                if let first = status.first, phase == .starting {
                    metrics["Microphone"] = milliseconds(capture.start, to: first)
                    phase = .listening
                }
                level = status.rms
                duration = Double(status.count) / buffer.rate
                if status.full { finish(interrupted: true); return }
                if phase == .starting && milliseconds(capture.start) > 5000 {
                    cancel()
                    phase = .notice("No microphone frames arrived. Check the input and try again.")
                    showStudy?()
                    return
                }
                try? await Task.sleep(for: .milliseconds(32))
            }
        }
    }

    func finish(interrupted: Bool = false) {
        guard var current = capture, [.starting, .listening].contains(phase) else { return }
        current.ended = .now
        current.interrupted = interrupted
        capture = current
        work?.cancel()
        meter?.cancel()
        let buffer = activeBuffer
        activeBuffer = nil
        phase = .finishing
        work = Task {
            await mic.stop(id: current.id)
            guard capture?.id == current.id, !Task.isCancelled else { return }
            guard let buffer, buffer.status().first != nil else { noSpeech(); return }
            metrics["Microphone"] = metrics["Microphone"] ?? buffer.status().first.map { milliseconds(current.start, to: $0) }
            let audio = buffer.audio()
            guard audio.peak > 0.002, !audio.samples.isEmpty else { noSpeech(); return }
            self.audio = audio
            hasAudio = true
            await transcribe(audio, current: current)
        }
    }

    func retryTranscription() {
        guard let audio, let current = capture, canRetry else { return }
        phase = .finishing
        work = Task { await transcribe(audio, current: current) }
    }

    private func transcribe(_ audio: StudyAudio, current: Capture) async {
        do {
            let start = ContinuousClock.now
            let samples = try await Task.detached(priority: .userInitiated) { try audio.mono16k() }.value
            try Task.checkCancellation()
            let result = try await recognizer.decode(samples, engine: current.engine, language: current.language) { [weak self] in
                Task { @MainActor in
                    guard self?.capture?.id == current.id else { return }
                    self?.metrics["First partial after Finish"] = milliseconds(start)
                }
            }
            guard capture?.id == current.id, !Task.isCancelled else { return }
            let text = result.0.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.contains(where: { $0.isLetter || $0.isNumber }) else { throw RecognitionIssue.noTranscript }
            if let stopped = current.ended { metrics["Finish to text"] = milliseconds(stopped) }
            metrics["Model prepare"] = result.1
            raw = text
            edited = text
            if current.completion == .review || current.interrupted {
                hideStatus?()
                phase = .review
                if current.interrupted { notice = "Recording ended early. Review the words that were captured." }
                showStudy?()
            } else {
                await write(current: current)
            }
        } catch {
            guard capture?.id == current.id, !Task.isCancelled else { return }
            fail("Transcription didn’t finish. Retry or discard this recording.")
        }
    }

    private func noSpeech() {
        capture = nil
        audio = nil
        hasAudio = false
        phase = .notice("No speech heard")
        scheduleHide()
    }

    func keep() {
        guard let current = capture, phase == .review || canRetryWrite else { return }
        work = Task { await write(current: current) }
    }

    private func write(current: Capture) async {
        guard capture?.id == current.id, phase != .saving else { return }
        let text = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let repo else { return }
        phase = .saving
        do {
            let start = ContinuousClock.now
            let note = try await repo.createKeptVoiceCapture(id: current.id, content: text)
            metrics["Database commit"] = milliseconds(start)
            metrics["Start to Keep"] = milliseconds(current.start)
            receipt = note
            opened = nil
            phase = .kept
            audio = nil
            hasAudio = false
            activeBuffer = nil
            capture = nil
            notes = (try? await repo.fetchAllNonDeleted().filter(\.isKept)) ?? [note] + notes.filter { $0.id != note.id }
            if current.completion != .review, phase == .kept, receipt?.id == note.id {
                presentStatus?()
                scheduleHide()
            }
        } catch { fail("Couldn’t save. The transcript is still here.") }
    }

    func undo() {
        guard let receipt, let repo else { return }
        Task {
            do {
                guard try await repo.undoStudyCapture(receipt) else {
                    notice = "This thought changed. The capture wasn’t undone."
                    return
                }
                if self.receipt?.id == receipt.id { self.receipt = nil }
                if opened?.id == receipt.id { opened = nil }
                notes.removeAll { $0.id == receipt.id }
                if phase == .kept { phase = .idle; hideStatus?() }
                notice = "Capture undone."
            } catch { notice = "The capture couldn’t be undone. Try again." }
        }
    }

    func openReceipt() {
        opened = receipt
        hideStatus?()
        showStudy?()
    }

    func cancel() {
        guard canCancel else { return }
        let id = capture?.id
        capture = nil
        work?.cancel()
        meter?.cancel()
        activeBuffer = nil
        audio = nil
        hasAudio = false
        raw = ""
        edited = ""
        level = 0
        duration = 0
        hideStatus?()
        phase = .idle
        if let id {
            endingAudio = true
            Task { await mic.stop(id: id); endingAudio = false }
        }
    }

    private func fail(_ message: String) {
        phase = .failure(message)
        hideStatus?()
        showStudy?()
    }

    private func scheduleHide() {
        dismiss?.cancel()
        dismiss = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { hideStatus?() }
        }
    }

    func exportEvaluationAudio() {
        guard let audio, let directory, let current = capture else { return }
        let sampleID = current.id.uuidString
        Task {
            do {
                try await Task.detached(priority: .utility) {
                    let base = directory.appending(path: "Evaluation Clips", directoryHint: .isDirectory)
                    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                    let mono = try audio.mono16k()
                    guard let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1),
                          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(mono.count)) else {
                        throw AudioIssue.conversion
                    }
                    buffer.frameLength = UInt32(mono.count)
                    mono.withUnsafeBufferPointer { source in
                        if let address = source.baseAddress { buffer.floatChannelData?[0].update(from: address, count: source.count) }
                    }
                    let url = base.appending(path: sampleID + ".wav")
                    let writer = try AVAudioFile(forWriting: url, settings: format.settings)
                    try writer.write(from: buffer)
                }.value
                notice = "Test audio saved in Evaluation Clips."
            } catch { notice = "The evaluation clip couldn’t be saved." }
        }
    }

    func revealEvaluationClips() {
        if let directory { NSWorkspace.shared.open(directory) }
    }

    private func setShortcut() {
        keyIsDown = false
        KeyboardShortcuts.removeAllHandlers()
        if testFolder == nil { UserDefaults.standard.set(globalShortcut, forKey: "studyShortcutEnabled") }
        guard globalShortcut else { return }
        KeyboardShortcuts.onKeyDown(for: .voiceStudy) { [weak self] in
            guard let self, !self.keyIsDown else { return }
            self.keyIsDown = true
            if self.activation == .hold { self.start() }
        }
        KeyboardShortcuts.onKeyUp(for: .voiceStudy) { [weak self] in
            guard let self, self.keyIsDown else { return }
            self.keyIsDown = false
            if self.activation == .hold { self.finish() }
            else { self.shortcutAction() }
        }
    }
}

extension StudySession {
    func exerciseSynthetic(_ samples: [Float]) async throws {
        enum ValidationError: Error { case review, commit, undo }
        guard let repo else { throw ValidationError.commit }
        let preserved = "Existing test scratch stays here."
        draft = preserved
        try await repo.saveStudyDraft(preserved)
        let current = Capture(engine: .apple, language: "en-US", completion: .review, ended: .now)
        capture = current
        phase = .finishing
        await transcribe(StudyAudio(samples: samples, rate: 16000, peak: 0.2), current: current)
        guard phase == .review, raw.localizedCaseInsensitiveContains("deploy") else { throw ValidationError.review }
        edited += " Still unsure."
        await write(current: current)
        await write(current: current)
        guard phase == .kept, let receipt, notes.count == 1, receipt.content.contains("Still unsure."),
              try await repo.loadStudyDraft() == preserved,
              try await repo.search("deploy", limit: 5).map(\.id) == [receipt.id] else { throw ValidationError.commit }
        undo()
        for _ in 0..<100 where self.receipt != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard self.receipt == nil, try await repo.fetch(id: receipt.id) == nil else { throw ValidationError.undo }
    }
}
