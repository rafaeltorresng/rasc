import AppKit
import SwiftUI

/// Captures app-owned views only. Uses the real session and signed SQLite store
/// with an explicit, bundled synthetic fixture instead of the microphone.
@MainActor
enum NativeEvidence {
    static func run() async {
        let root = FileManager.default.temporaryDirectory.appending(path: "VoiceCaptureVisual-\(UUID())")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            guard let fixtureURL = Bundle.main.resourceURL?.appending(path: "en-clip.wav") else { exit(1) }
            let samples = try LocalBenchmark.loadFixture(fixtureURL)
            let signal = StudyFixture(recognition: .actual)
            let study = StudySession(folder: root.appending(path: "test-data"), fixture: signal, timeout: .seconds(45))
            study.selectedEngine = .apple
            study.language = "en-US"
            await study.load()
            study.draft = "Check whether the retry needs to wait until Monday."
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 690, height: 408),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "Rasc Voice Capture"
            window.isReleasedWhenClosed = false
            window.center()
            let panel = CapturePanel(contentRect: .init(origin: .zero, size: CaptureSurface.windowSize),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.setFrameOrigin(.init(x: window.frame.midX - panel.frame.width / 2, y: window.frame.minY + 26))
            study.presentStatus = { panel.orderFrontRegardless() }
            study.hideStatus = { panel.orderOut(nil) }
            study.showStudy = { window.orderFrontRegardless() }
            let deck = root.appending(path: "frames")
            try FileManager.default.createDirectory(at: deck, withIntermediateDirectories: true)

            func appearance(_ appearance: StudyAppearance) {
                study.appearance = appearance
                let scheme = appearance.scheme
                window.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
                panel.appearance = window.appearance
                window.contentView = NSHostingView(rootView: StudyView(session: study).preferredColorScheme(scheme))
                panel.contentView = NSHostingView(rootView: CaptureSurface(session: study).preferredColorScheme(scheme))
            }

            func pause() async throws { try await Task.sleep(for: .milliseconds(70)) }
            func save(_ name: String, in directory: URL, panelOnly: Bool = false) throws {
                let selected = panelOnly ? panel.contentView : (window.contentView?.superview ?? window.contentView)
                guard let selected else { throw EvidenceError.image }
                let content = try bitmap(selected)
                if panelOnly || !panel.isVisible {
                    try write(content, to: directory.appending(path: name + ".png"))
                } else if let panelView = panel.contentView {
                    let capsule = try bitmap(panelView)
                    let merged = NSImage(size: content.size, flipped: false) { bounds in
                        content.draw(in: bounds)
                        capsule.draw(in: .init(x: (bounds.width - capsule.size.width) / 2.0,
                                               y: 24, width: capsule.size.width, height: capsule.size.height))
                        return true
                    }
                    try write(merged, to: directory.appending(path: name + ".png"))
                }
            }

            var index = 0
            func frame(_ count: Int = 1) throws {
                for _ in 0..<count {
                    try save(String(format: "frame-%04d", index), in: deck)
                    index += 1
                }
            }

            appearance(.light)
            window.orderFrontRegardless()
            try await pause()
            try save("01-scratch-light", in: root)
            try frame(8)

            let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
            study.start()
            try await StudyValidation.wait("synthetic input") { await signal.activity().active }
            try await pause()
            try save("02-starting-light", in: root, panelOnly: true)
            try frame(4)
            LocalBenchmark.output(["panel_nonactivation": before == NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                   "panel_is_key": panel.isKeyWindow, "panel_visible": panel.isVisible])
            for start in stride(from: 0, to: samples.count, by: 1600) {
                await signal.send(Array(samples[start..<min(start + 1600, samples.count)]))
                try await pause()
                if index == 16 { try save("03-listening-light", in: root, panelOnly: true) }
                try frame()
            }
            study.finish()
            try await pause()
            try frame(3)
            try await StudyValidation.wait("synthetic review") { study.phase == .review }
            try await pause()
            try save("04-review-light", in: root)
            try frame(12)
            study.edited = "Don’t deploy yet. Revisit on Monday."
            try await pause()
            try frame(6)
            study.keep()
            try await StudyValidation.wait("synthetic commit") { study.phase == .kept }
            try await pause()
            try save("05-kept-thought-light", in: root)
            try frame(9)

            appearance(.dark)
            window.setContentSize(.init(width: 600, height: 365))
            study.opened = nil
            study.completion = .receipt
            try await pause()
            try save("06-scratch-dark-compact", in: root)
            study.start()
            try await StudyValidation.wait("dark input") { await signal.activity().active }
            await signal.send(samples)
            try await StudyValidation.wait("dark ready") { study.phase == .listening }
            try await pause()
            try save("07-listening-dark", in: root, panelOnly: true)
            study.finish()
            try await StudyValidation.wait("automatic commit") { study.phase == .kept }
            try await pause()
            try save("08-kept-dark", in: root, panelOnly: true)
            study.openReceipt()
            try await pause()
            try save("09-opened-dark-compact", in: root)
            study.undo()
            try await StudyValidation.wait("undo") { study.notes.count == 1 }
            try await pause()
            try save("10-undone-dark-compact", in: root)
            study.completion = .receipt
            try await study.injectStoreFailure(true)
            study.start()
            try await StudyValidation.wait("failed save input") { await signal.activity().active }
            await signal.send(samples)
            try await StudyValidation.wait("failed save listening") { study.phase == .listening }
            study.finish()
            try await StudyValidation.wait("recover from save failure") { study.phase == .recovery(.save) }
            try await pause()
            try save("11-save-failure-dark-compact", in: root)
            study.cancel()
            window.orderOut(nil)
            panel.orderOut(nil)
            print("Visual output \(root.path)")
            exit(0)
        } catch {
            print("Visual evidence failed: \(error)")
            exit(1)
        }
    }

    private enum EvidenceError: Error { case image }

    private static func bitmap(_ view: NSView) throws -> NSImage {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw EvidenceError.image }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private static func write(_ image: NSImage, to url: URL) throws {
        guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:]) else { throw EvidenceError.image }
        try png.write(to: url, options: .atomic)
    }
}
