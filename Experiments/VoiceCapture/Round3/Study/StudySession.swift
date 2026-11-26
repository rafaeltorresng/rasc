import AppKit
import AVFoundation
import Foundation
import KeyboardShortcuts
import Observation

extension KeyboardShortcuts.Name {
    static let voiceStudy = Self("rascVoiceCaptureStudy")
}

enum Activation: String, CaseIterable, Identifiable, Sendable {
    case toggle = "Press to start and finish"
    case hold = "Hold to speak"
    var id: Self { self }
}

enum Completion: String, CaseIterable, Identifiable, Sendable {
    case review = "Review before Keep"
    case receipt = "Keep with Open and Undo"
    var id: Self { self }
}

@MainActor @Observable
final class StudySession {
    enum Phase: Equatable {
        case idle, setup, permission, starting, listening, ending, preparingTranscript, finishing, review, saving, discarding, kept
        case silent, recovery(Recovery)
        var text: String {
            switch self {
            case .idle: "Ready to record"
            case .setup: "Preparing speech model"
            case .permission: "Microphone access"
            case .starting: "Starting microphone"
            case .listening: "Listening"
            case .ending: "Finishing recording"
            case .preparingTranscript: "Preparing speech"
            case .finishing: "Transcribing"
            case .review: "Review thought"
            case .saving: "Keeping thought"
            case .discarding: "Discarding thought"
            case .kept: "Kept"
            case .silent: "No speech heard"
            case .recovery(let reason): reason.title
            }
        }
    }

    enum Recovery: String, Equatable, Sendable {
        case microphone, permissionDenied, setup, transcript, timeout, save
        var title: String {
            switch self {
            case .microphone: "Microphone unavailable"
            case .permissionDenied: "Microphone access is off"
            case .setup: "Speech model unavailable"
            case .transcript: "Couldn’t transcribe"
            case .timeout: "Transcription took too long"
            case .save: "Couldn’t keep thought"
            }
        }
    }

    var selectedEngine: StudyEngine = .fluid { didSet { remember(selectedEngine.rawValue, "engine") } }
    var language = "pt-BR" { didSet { remember(language, "language") } }
    var activation = Activation.toggle {
        didSet { remember(activation.rawValue, "activation"); shortcutIsDown = false }
    }
    var completion = Completion.review { didSet { remember(completion.rawValue, "completion") } }
    var theme = ThemePreset.graphitePaper
    var appearance = StudyAppearance.system
    var globalShortcut = false {
        didSet {
            remember(globalShortcut, "shortcutEnabled")
            setShortcut()
        }
    }
    var logTimings = false { didSet { remember(logTimings, "logTimings") } }

    private(set) var phase: Phase = .idle
    private(set) var assetReady = false
    private(set) var storageReady = false

    var draft = ""
    var draftIssue: String?
    var edited = ""
    private(set) var raw = ""
    private(set) var notes: [Note] = []
    var opened: Note?
    private(set) var receipt: Note?
    var showingOptions = false
    var editingKeptThought = false
    var notice: String?
    private(set) var level: Float = 0
    private(set) var duration: Double = 0
    private(set) var metrics: [String: Double] = [:]
    private(set) var hasAudio = false

    @ObservationIgnored private var repo: NoteRepository?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var warming: Task<Void, Never>?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var operation: UUID?
    @ObservationIgnored private var meter: Task<Void, Never>?
    @ObservationIgnored private var dismiss: Task<Void, Never>?
    @ObservationIgnored private var scratchSave: Task<Void, Never>?
    @ObservationIgnored private var transcriptSave: Task<Void, Never>?
    @ObservationIgnored private var scratchRevision = 0
    @ObservationIgnored private var directory: URL?
    @ObservationIgnored private var capture: Capture?
    @ObservationIgnored private var activeBuffer: MicBuffer?
    @ObservationIgnored private var audio: StudyAudio?
    private var endingAudio = false
    private var journalBusy = false
    @ObservationIgnored private var fileWork: Task<Void, Never>?
    @ObservationIgnored private var shortcutIsDown = false
    @ObservationIgnored private var shortcutHandlersInstalled = false
    @ObservationIgnored private var reviewBegan: ContinuousClock.Instant?
    @ObservationIgnored private var evaluation: StudyEvaluation?
    @ObservationIgnored private let microphone = Microphone()
    @ObservationIgnored private let recognizer = StudyRecognizer()
    @ObservationIgnored let fixture: StudyFixture?
    @ObservationIgnored let folder: URL?
    @ObservationIgnored let timeout: Duration
    @ObservationIgnored var presentStatus: (() -> Void)?
    @ObservationIgnored var hideStatus: (() -> Void)?
    @ObservationIgnored var showStudy: (() -> Void)?
    @ObservationIgnored var announce: ((String) -> Void)?

    struct Capture {
        let id: UUID
        let start = ContinuousClock.now
        let engine: StudyEngine
        let language: String
        let completion: Completion
        var ended: ContinuousClock.Instant?
        var interrupted = false

        init(id: UUID = UUID(), engine: StudyEngine, language: String, completion: Completion) {
            self.id = id
            self.engine = engine
            self.language = language
            self.completion = completion
        }
    }

    init(folder: URL? = nil, fixture: StudyFixture? = nil, timeout: Duration = .seconds(45)) {
        self.folder = folder
        self.fixture = fixture
        self.timeout = timeout
        if folder == nil {
            let defaults = UserDefaults.standard
            selectedEngine = defaults.string(forKey: "engine").flatMap(StudyEngine.init(rawValue:)) ?? .fluid
            language = defaults.string(forKey: "language") ?? "pt-BR"
            activation = defaults.string(forKey: "activation").flatMap(Activation.init(rawValue:)) ?? .toggle
            completion = defaults.string(forKey: "completion").flatMap(Completion.init(rawValue:)) ?? .review
            globalShortcut = defaults.bool(forKey: "shortcutEnabled")
            logTimings = defaults.bool(forKey: "logTimings")
        }
    }

    private func remember(_ value: Any, _ key: String) {
        if folder == nil { UserDefaults.standard.set(value, forKey: key) }
    }

    var dataBusy: Bool { journalBusy }
    var canStart: Bool { optionsEnabled && !showingOptions && !editingKeptThought }
    var optionsEnabled: Bool {
        storageReady && !endingAudio && !journalBusy && capture == nil &&
            (phase == .idle || phase == .kept || phase == .silent || recoverableSetup)
    }

    private var recoverableSetup: Bool {
        [.recovery(.microphone), .recovery(.setup), .recovery(.permissionDenied)].contains(phase)
    }

    var canCancel: Bool {
        [.setup, .permission, .starting, .listening, .ending, .preparingTranscript, .finishing, .review].contains(phase) ||
            (capture != nil && (canRetry || canRetryWrite))
    }

    var canRetry: Bool { [.recovery(.transcript), .recovery(.timeout)].contains(phase) && hasAudio }
    var canRetryWrite: Bool { phase == .recovery(.save) && capture != nil }

    func load() async {
        let folder = folder
        do {
            let (target, opened) = try await Task.detached(priority: .userInitiated) {
                let location = if let folder { folder } else {
                    try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)
                        .appending(path: "Rasc Voice Capture", directoryHint: .isDirectory)
                }
                try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
                return (location, try NoteRepository(databaseURL: location.appending(path: "Study.sqlite")))
            }.value
            directory = target
            let initial = try await opened.initializeStudyStorage()
            repo = opened
            if scratchRevision == 0 { draft = initial.scratch }
            notes = try await opened.fetchAllNonDeleted().filter(\.isKept)
            if let pending = initial.pending {
                capture = Capture(id: pending.id, engine: selectedEngine, language: language, completion: .review)
                raw = pending.recognized
                edited = pending.text
                notice = "Your previous transcript is ready to review."
                changePhase(.review)
            }
            storageReady = true
            setShortcut()
        } catch {
            draftIssue = "The study database couldn’t open."
        }
        await checkModel()
    }

    private func changePhase(_ next: Phase) {
        phase = next
        switch next {
        case .listening, .finishing, .kept, .silent:
            announce?(next.text)
        default: break
        }
    }

    func checkModel() async {
        let engine = selectedEngine
        let locale = language
        if await microphoneAuthorization() == .authorized && phase == .recovery(.permissionDenied) {
            notice = "Microphone access restored."
            changePhase(.idle)
        }
        let available = (try? await StudyRecognizer.ready(engine, language: locale)) == true
        if engine == selectedEngine, locale == language { assetReady = available }
    }

    func chooseEngine(_ engine: StudyEngine) {
        guard optionsEnabled, selectedEngine != engine else { return }
        selectedEngine = engine
        notice = nil
        assetReady = false
        Task { await checkModel() }
    }

    func prepareModel() {
        guard optionsEnabled, !editingKeptThought else { return }
        let locale = language
        let engine = selectedEngine
        let token = UUID()
        operation = token
        changePhase(.setup)
        notice = nil
        work = Task {
            do {
                if engine == .apple {
                    try await StudyRecognizer.installApple(language: locale)
                } else {
                    try await recognizer.preparePortable(engine)
                }
                guard operation == token, !Task.isCancelled else { return }
                await checkModel()
                guard operation == token, !Task.isCancelled else { return }
                operation = nil
                changePhase(.idle)
                notice = "Speech is ready."
            } catch {
                guard operation == token, !Task.isCancelled else { return }
                operation = nil
                changePhase(.recovery(.setup))
            }
        }
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
        evaluation = nil
        level = 0
        duration = 0
        let next = Capture(engine: selectedEngine, language: language, completion: completion)
        capture = next
        metrics = [:]
        changePhase(.starting)
        presentStatus?()
        metrics["Status ordered"] = milliseconds(next.start)
        work = Task {
            do {
                let ready = (try? await StudyRecognizer.ready(next.engine, language: next.language)) == true
                guard isCurrent(next), !Task.isCancelled else { return }
                guard ready else { failStart(.setup); return }
                let status = await microphoneAuthorization()
                guard isCurrent(next), !Task.isCancelled else { return }
                if status == .notDetermined {
                    changePhase(.permission)
                    hideStatus?()
                    showStudy?()
                    let allowed = if let fixture { await fixture.requestAuthorization() }
                                  else { await AVCaptureDevice.requestAccess(for: .audio) }
                    guard isCurrent(next), !Task.isCancelled else { return }
                    capture = nil
                    changePhase(allowed ? .idle : .recovery(.permissionDenied))
                    if allowed {
                        notice = "Microphone allowed. Start when you’re ready."
                        beginWarmup(next.engine)
                    }
                    return
                }
                guard status == .authorized else { failStart(.permissionDenied); return }
                armMicrophoneWatchdog(next)
                let buffer: MicBuffer
                if let fixture {
                    buffer = try await fixture.start(id: next.id) { [weak self] in
                        Task { @MainActor in self?.routeChanged(id: next.id) }
                    }
                } else {
                    buffer = try await microphone.start(id: next.id) { [weak self] in
                        Task { @MainActor in self?.routeChanged(id: next.id) }
                    }
                }
                guard isCurrent(next), !Task.isCancelled, phase == .starting else {
                    await stopInput(next.id)
                    return
                }
                activeBuffer = buffer
                beginWarmup(next.engine)
                monitor(buffer, capture: next)
            } catch {
                guard isCurrent(next), !Task.isCancelled else { return }
                failStart(.microphone)
            }
        }
    }

    private func microphoneAuthorization() async -> AVAuthorizationStatus {
        if let fixture { return await fixture.authorizationStatus() }
        return AVCaptureDevice.authorizationStatus(for: .audio)
    }

    private func armMicrophoneWatchdog(_ current: Capture) {
        watchdog?.cancel()
        watchdog = Task {
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            guard isCurrent(current), phase == .starting else { return }
            cancel()
            changePhase(.recovery(.microphone))
            showStudy?()
        }
    }

    private func beginWarmup(_ engine: StudyEngine) {
        guard engine != .apple, fixture?.usesRealEngine != false else { return }
        warming?.cancel()
        let recognizer = recognizer
        warming = Task { try? await recognizer.preparePortable(engine) }
    }

    func memoryPressure() {
        Task { await recognizer.releaseForMemoryPressure() }
    }

    private func monitor(_ buffer: MicBuffer, capture current: Capture) {
        meter?.cancel()
        meter = Task {
            while !Task.isCancelled, isCurrent(current) {
                let status = buffer.status()
                if let first = status.first, phase == .starting {
                    watchdog?.cancel()
                    metrics["Microphone ready"] = milliseconds(current.start, to: first)
                    changePhase(.listening)
                }
                level = status.rms
                duration = Double(status.count) / buffer.rate
                if status.full || (phase == .listening && status.last.map { $0.duration(to: .now) > .seconds(3) } == true) {
                    finish(interrupted: true)
                    return
                }
                do { try await Task.sleep(for: .milliseconds(32)) } catch { return }
            }
        }
    }

    private func routeChanged(id: UUID) {
        guard capture?.id == id else { return }
        if phase == .ending {
            discardTail = true
            Task { await stopInput(id) }
        } else {
            finish(interrupted: true)
        }
    }

    @ObservationIgnored private var discardTail = false

    func finish(interrupted: Bool = false) {
        guard var current = capture, [.starting, .listening].contains(phase) else { return }
        let tailAllowed = phase == .listening && !interrupted
        current.ended = .now
        current.interrupted = interrupted
        capture = current
        work?.cancel()
        watchdog?.cancel()
        meter?.cancel()
        let buffer = activeBuffer
        activeBuffer = nil
        discardTail = false
        changePhase(tailAllowed ? .ending : .finishing)
        work = Task {
            if tailAllowed {
                do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            }
            await stopInput(current.id)
            guard isCurrent(current), !Task.isCancelled else { return }
            if discardTail {
                current.interrupted = true
                capture = current
            }
            if let ended = current.ended { metrics["Finish to microphone stop"] = milliseconds(ended) }
            level = 0
            guard let buffer, let first = buffer.status().first else { noSpeech(current); return }
            metrics["Microphone ready"] = metrics["Microphone ready"] ?? milliseconds(current.start, to: first)
            await acceptAudio(buffer.audio(), current: current)
        }
    }

    func interrupt() {
        shortcutIsDown = false
        if let current = capture, phase == .ending { routeChanged(id: current.id) }
        else if phase == .starting || phase == .listening { finish(interrupted: true) }
        if capture == nil, phase == .setup { cancel() }
        Task { await recognizer.releaseForMemoryPressure() }
    }

    private func stopInput(_ id: UUID) async {
        if let fixture { await fixture.stop(id: id) }
        else { await microphone.stop(id: id) }
    }

    private func acceptAudio(_ received: StudyAudio, current: Capture) async {
        guard isCurrent(current) else { return }
        duration = received.seconds
        metrics["Audio duration"] = received.seconds * 1000
        // A click or device transient must not become a note. A quiet recording
        // with speech above this conservative floor still goes to recognition.
        guard received.activitySeconds >= 0.055,
              received.seconds >= 0.085 else { noSpeech(current); return }
        audio = received
        hasAudio = true
        await transcribe(received, current: current)
    }

    func retryTranscription() {
        guard let audio, let current = capture, canRetry else { return }
        changePhase(.finishing)
        work = Task { await transcribe(audio, current: current) }
    }

    private func transcribe(_ audio: StudyAudio, current: Capture) async {
        let token = UUID()
        operation = token
        changePhase(.finishing)
        armDecodeWatchdog(token, current: current)
        do {
            let started = ContinuousClock.now
            let frames = try await Task.detached(priority: .userInitiated) {
                try audio.mono16k()
            }.value
            try Task.checkCancellation()
            guard isCurrent(current, token) else { return }
            metrics["Conversion"] = milliseconds(started)
            let result: (String, Double)
            if let fixture, !fixture.usesRealEngine {
                result = (try await fixture.recognize(frames), 0)
            } else {
                if current.engine != .apple, await !recognizer.isPrepared(current.engine), isCurrent(current, token) {
                    changePhase(.preparingTranscript)
                }
                result = try await recognizer.decode(frames, engine: current.engine, language: current.language,
                    onPartial: { [weak self] in
                        Task { @MainActor in
                            guard self?.isCurrent(current, token) == true else { return }
                            self?.metrics["First partial after Finish"] = milliseconds(started)
                        }
                    },
                    onModelReady: { [weak self] in
                        Task { @MainActor in
                            guard let self, self.isCurrent(current, token), self.phase == .preparingTranscript else { return }
                            self.changePhase(.finishing)
                        }
                    }
                )
            }
            guard isCurrent(current, token), !Task.isCancelled else { return }
            let text = result.0.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.contains(where: { $0.isLetter || $0.isNumber }) else { throw RecognitionIssue.noTranscript }
            if let stopped = current.ended { metrics["Finish to text"] = milliseconds(stopped) }
            metrics["Model wait after Finish"] = result.1
            raw = text
            edited = text
            watchdog?.cancel()
            operation = nil
            if current.completion == .review || current.interrupted {
                do { try await repo?.stageVoiceText(.init(id: current.id, recognized: text, text: text)) }
                catch {
                    guard isCurrent(current), !Task.isCancelled else { return }
                    notice = "The transcript is here, but its recovery copy couldn’t be saved."
                }
                guard isCurrent(current), !Task.isCancelled else { return }
                if current.interrupted && notice == nil { notice = "Recording ended early. Review what was captured." }
                hideStatus?()
                reviewBegan = .now
                changePhase(.review)
                showStudy?()
            } else {
                await write(current)
            }
        } catch {
            guard isCurrent(current, token), !Task.isCancelled else { return }
            watchdog?.cancel()
            operation = nil
            fail(.transcript, current: current)
        }
    }

    private func armDecodeWatchdog(_ token: UUID, current: Capture) {
        watchdog?.cancel()
        watchdog = Task {
            do { try await Task.sleep(for: timeout) } catch { return }
            guard isCurrent(current, token), [.preparingTranscript, .finishing].contains(phase) else { return }
            operation = nil
            work?.cancel()
            fail(.timeout, current: current)
        }
    }

    private func isCurrent(_ candidate: Capture, _ token: UUID? = nil) -> Bool {
        capture?.id == candidate.id && (token == nil || operation == token)
    }

    private func failStart(_ reason: Recovery) {
        watchdog?.cancel()
        if reason == .setup { assetReady = false }
        capture = nil
        hideStatus?()
        changePhase(.recovery(reason))
        showStudy?()
    }

    private func fail(_ reason: Recovery, current: Capture) {
        changePhase(.recovery(reason))
        hideStatus?()
        showStudy?()
        log(current, outcome: reason.rawValue)
    }

    private func noSpeech(_ current: Capture) {
        audio = nil
        capture = nil
        hasAudio = false
        warming?.cancel()
        changePhase(.silent)
        log(current, outcome: "silence")
        scheduleHide()
    }

    func cancel() {
        guard canCancel else { return }
        let current = capture
        let hadTranscript = !raw.isEmpty && current != nil
        let previous = work
        let previousEdit = transcriptSave
        operation = nil
        work?.cancel()
        watchdog?.cancel()
        meter?.cancel()
        warming?.cancel()
        transcriptSave?.cancel()
        activeBuffer = nil
        hideStatus?()
        endingAudio = true
        changePhase(hadTranscript ? .discarding : .idle)
        if !hadTranscript { clearCapture() }
        work = Task {
            defer { endingAudio = false }
            if let current { await stopInput(current.id) }
            await recognizer.cancelPreparation()
            if let current, hadTranscript {
                // A stage already enqueued can win cancellation. Delete only
                // after it and any debounced edit can no longer write the row.
                await previous?.value
                await previousEdit?.value
                do { try await repo?.discardVoiceText(current.id) }
                catch {
                    notice = "The recovery copy couldn’t be discarded. Try again or keep the thought."
                    changePhase(.review)
                    showStudy?()
                    return
                }
                clearCapture()
                changePhase(.idle)
            }
            if let current { log(current, outcome: "cancelled") }
        }
    }

    private func clearCapture() {
        capture = nil
        audio = nil
        hasAudio = false
        raw = ""
        edited = ""
        level = 0
        duration = 0
        reviewBegan = nil
    }

    func keep() {
        guard let current = capture, phase == .review || canRetryWrite else { return }
        let text = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return }
        changePhase(.saving)
        let priorEdit = transcriptSave
        transcriptSave?.cancel()
        work = Task {
            await priorEdit?.value
            await write(current)
        }
    }

    private func write(_ current: Capture) async {
        guard isCurrent(current), let repo else { return }
        let text = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        changePhase(.saving)
        do {
            let start = ContinuousClock.now
            let note = try await repo.keepStudyVoice(id: current.id, content: text)
            metrics["Database commit"] = milliseconds(start)
            metrics["Start to Keep"] = milliseconds(current.start)
            if let reviewed = reviewBegan { metrics["Review and correction"] = milliseconds(reviewed, to: start) }
            reviewBegan = nil
            receipt = note
            edited = note.content
            notes = [note] + notes.filter { $0.id != note.id }
            if current.completion == .review || current.interrupted { opened = note }
            evaluation = StudyEvaluation(capture: current, metrics: metrics, outcome: "kept")
            log(current, outcome: "kept")
            audio = nil
            hasAudio = false
            capture = nil
            changePhase(.kept)
            if current.completion == .receipt, !current.interrupted {
                presentStatus?()
                scheduleHide()
            }
        } catch {
            // A failed automatic Keep has no review journal yet. Capture it
            // when storage is still available so a relaunch can recover it.
            try? await repo.stageVoiceText(.init(id: current.id, recognized: raw, text: text))
            fail(.save, current: current)
        }
    }

    func saveReviewEdit() {
        guard let id = capture?.id, phase == .review || canRetryWrite else { return }
        transcriptSave?.cancel()
        let pending = NoteRepository.PendingVoiceText(id: id, recognized: raw, text: edited)
        transcriptSave = Task {
            do {
                try await Task.sleep(for: .milliseconds(220))
                try await repo?.stageVoiceText(pending)
            } catch is CancellationError {}
            catch { notice = "The recovery draft couldn’t be updated." }
        }
    }

    func saveDraft(_ text: String) {
        guard !journalBusy else { return }
        scratchRevision += 1
        let revision = scratchRevision
        scratchSave?.cancel()
        scratchSave = Task {
            do {
                try await Task.sleep(for: .milliseconds(220))
                guard revision == scratchRevision else { return }
                try await repo?.saveStudyDraft(text)
                if revision == scratchRevision { draftIssue = nil }
            } catch is CancellationError {}
            catch { if revision == scratchRevision { draftIssue = "The scratch couldn’t save." } }
        }
    }

    func editThought(_ snapshot: Note, text: String) async -> Bool {
        guard let repo else { return false }
        do {
            let updated = try await repo.editStudyThought(snapshot, text: text)
            if opened?.id == snapshot.id { opened = updated }
            if let index = notes.firstIndex(where: { $0.id == snapshot.id }) { notes[index] = updated }
            // The original capture receipt cannot undo subsequent edits.
            notice = "Changes saved."
            return true
        } catch {
            notice = "The changes couldn’t be saved. Your edits are still here."
            return false
        }
    }

    func undo() {
        guard let receipt, let repo, !journalBusy else { return }
        journalBusy = true
        Task {
            defer { journalBusy = false }
            do {
                guard try await repo.undoStudyCapture(receipt) else {
                    notice = "This thought changed. Its capture can’t be undone."
                    return
                }
                self.receipt = nil
                if opened?.id == receipt.id { opened = nil }
                notes.removeAll { $0.id == receipt.id }
                if phase == .kept { changePhase(.idle); hideStatus?() }
                notice = "Capture undone."
            } catch { notice = "The capture couldn’t be undone. Try again." }
        }
    }

    func openReceipt() {
        guard let receipt, let current = notes.first(where: { $0.id == receipt.id }) else { return }
        opened = current
        hideStatus?()
        showStudy?()
    }

    func prepareToQuit() async -> Bool {
        guard !journalBusy, !endingAudio else { return false }
        if capture != nil, phase != .review, !canRetryWrite { return false }
        journalBusy = true
        defer { journalBusy = false }
        let pendingScratch = scratchSave
        scratchSave?.cancel()
        await pendingScratch?.value
        do {
            try await repo?.saveStudyDraft(draft)
            if let current = capture, phase == .review || canRetryWrite {
                let pendingEdit = transcriptSave
                transcriptSave?.cancel()
                await pendingEdit?.value
                try await repo?.stageVoiceText(.init(id: current.id, recognized: raw, text: edited))
            } else if capture != nil { return false }
            await recognizer.releaseLoadedModel()
            return true
        } catch { return false }
    }

    func resetStudyData() {
        guard optionsEnabled, !editingKeptThought, let repo, let directory else { return }
        journalBusy = true
        let pendingScratch = scratchSave
        scratchSave?.cancel()
        transcriptSave?.cancel()
        Task {
            defer { journalBusy = false }
            do {
                await pendingScratch?.value
                await fileWork?.value
                try await repo.resetStudyNotes()
                notes = []
                receipt = nil
                opened = nil
                raw = ""
                edited = ""
                draft = ""
                evaluation = nil
                metrics = [:]
                hideStatus?()
                changePhase(.idle)
                try await StudyEvaluation.removeFiles(in: directory)
                notice = "Study data reset."
            } catch { notice = "The study data couldn’t be fully reset." }
        }
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealStudyFiles() {
        if let directory { NSWorkspace.shared.open(directory) }
    }

    func exportEvaluationAudio() {
        guard !journalBusy, let audio, let directory, let current = capture else { return }
        let prior = fileWork
        fileWork = Task {
            await prior?.value
            do {
                try await StudyEvaluation.writeAudio(audio, id: current.id, directory: directory)
                notice = "Audio saved in Evaluation Clips."
            } catch { notice = "The evaluation audio couldn’t be saved." }
        }
    }

    func exportTranscriptComparison() {
        guard !journalBusy, let directory, let evaluation, !raw.isEmpty else { return }
        let result = evaluation
        let recognized = raw
        let correction = edited
        let prior = fileWork
        fileWork = Task {
            await prior?.value
            do {
                try await result.write(in: directory, comparison: .init(recognized: recognized, kept: correction))
                notice = "Transcript comparison saved in Evaluation."
            } catch { notice = "The transcript comparison couldn’t be saved." }
        }
    }

    private func log(_ capture: Capture, outcome: String) {
        guard logTimings, let directory else { return }
        let event = StudyEvaluation(capture: capture, metrics: metrics, outcome: outcome)
        let prior = fileWork
        fileWork = Task {
            await prior?.value
            try? await event.write(in: directory)
        }
    }

    private func scheduleHide() {
        dismiss?.cancel()
        dismiss = Task {
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            hideStatus?()
        }
    }

    private func setShortcut() {
        guard folder == nil else { return }
        if !shortcutHandlersInstalled {
            shortcutHandlersInstalled = true
            KeyboardShortcuts.onKeyDown(for: .voiceStudy) { [weak self] in self?.shortcutDown() }
            KeyboardShortcuts.onKeyUp(for: .voiceStudy) { [weak self] in self?.shortcutUp() }
        }
        shortcutIsDown = false
        if globalShortcut { KeyboardShortcuts.enable(.voiceStudy) }
        else { KeyboardShortcuts.disable(.voiceStudy) }
    }

    func shortcutDown() {
        guard globalShortcut, !shortcutIsDown else { return }
        shortcutIsDown = true
        if activation == .hold { start() }
        else { shortcutAction() }
    }

    func shortcutUp() {
        guard shortcutIsDown else { return }
        shortcutIsDown = false
        if activation == .hold { finish() }
    }

    func exerciseSynthetic(_ samples: [Float]) async throws {
        let current = Capture(engine: .apple, language: "en-US", completion: .review)
        capture = current
        await acceptAudio(StudyAudio(samples: samples, rate: 16000, peak: 0.2, activitySeconds: 0.3), current: current)
        guard phase == .review, raw.localizedCaseInsensitiveContains("deploy") else { throw RecognitionIssue.noTranscript }
        edited = "Do not deploy yet."
        keep()
        await work?.value
        guard notes.count == 1, receipt?.content == "Do not deploy yet." else { throw AudioIssue.noFrames }
        undo()
        for _ in 0..<80 where journalBusy { try await Task.sleep(for: .milliseconds(10)) }
        guard notes.isEmpty else { throw AudioIssue.noFrames }
    }

    func injectDiscardFailure(_ enabled: Bool) async throws {
        guard let repo else { throw AudioIssue.noFrames }
        try await repo.rejectStudyDiscardForValidation(enabled)
    }

    func injectStoreFailure(_ enabled: Bool) async throws {
        guard let repo else { throw AudioIssue.noFrames }
        try await repo.rejectStudyCommitForValidation(enabled)
    }
}
