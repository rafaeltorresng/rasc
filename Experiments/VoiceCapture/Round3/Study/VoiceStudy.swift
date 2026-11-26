import AppKit
import AVFoundation
import Dispatch
import SwiftUI

@MainActor
final class StudyDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let session = StudySession()
    weak var window: NSWindow?
    private(set) var panel: CapturePanel?
    private var statusItem: NSStatusItem?
    private var pressureSource: (any DispatchSourceMemoryPressure)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        session.presentStatus = { [weak self] in self?.showStatus() }
        session.hideStatus = { [weak self] in self?.panel?.orderOut(nil) }
        session.showStudy = { [weak self] in self?.bringForward() }
        session.announce = { [weak self] in self?.announce($0) }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleep),
                                                          name: NSWorkspace.willSleepNotification, object: nil)
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        pressure.setEventHandler { [weak self] in self?.session.memoryPressure() }
        pressure.resume()
        pressureSource = pressure
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Rasc Voice Capture")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        Task { await session.load() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let running = [.starting, .listening].contains(session.phase)
        addItem(running ? "Finish Recording" : "Start Recording", #selector(toggle), enabled: running || session.canStart)
        if session.canCancel { addItem("Cancel Capture", #selector(cancel)) }
        if session.receipt != nil {
            menu.addItem(.separator())
            addItem("Open Last Thought", #selector(openLast))
            addItem("Undo Last Capture", #selector(undo))
        }
        menu.addItem(.separator())
        addItem("Open Rasc Voice Capture", #selector(openWindow))
    }

    private func addItem(_ title: String, _ selector: Selector, enabled: Bool = true) {
        let item = NSMenuItem(title: title, action: enabled ? selector : nil, keyEquivalent: "")
        item.target = self
        statusItem?.menu?.addItem(item)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await session.checkModel() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            let allowed = await session.prepareToQuit()
            if !allowed {
                bringForward()
                session.notice = "Finish or discard the current capture before quitting."
            }
            sender.reply(toApplicationShouldTerminate: allowed)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bringForward()
        return true
    }

    func showStatus() {
        let size = CaptureSurface.windowSize
        let panel = panel ?? CapturePanel(contentRect: .init(origin: .zero, size: size),
                                          styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
        if self.panel == nil {
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.contentView = NSHostingView(rootView: CaptureSurface(session: session))
            self.panel = panel
        }
        if !panel.isVisible, let screen = WindowFramePlacement.targetPresentationScreen(
            excludingProcessID: ProcessInfo.processInfo.processIdentifier
        ) {
            panel.setFrameOrigin(.init(x: screen.visibleFrame.midX - size.width / 2,
                                       y: screen.visibleFrame.minY + 22))
        }
        panel.appearance = switch session.appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        panel.orderFrontRegardless()
    }

    private func bringForward() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func announce(_ message: String) {
        let target: NSResponder = panel ?? window ?? NSApplication.shared
        NSAccessibility.post(element: target, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    @objc private func toggle() { session.shortcutAction() }
    @objc private func cancel() { session.cancel() }
    @objc private func openLast() { session.openReceipt() }
    @objc private func undo() { session.undo() }
    @objc private func openWindow() { bringForward() }
    @objc private func sleep() { session.interrupt() }
}

private struct WindowRegistration: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct StudyScene: App {
    @NSApplicationDelegateAdaptor(StudyDelegate.self) var delegate

    var body: some Scene {
        Window("Rasc Voice Capture", id: "study") {
            StudyView(session: delegate.session)
                .background(WindowRegistration { delegate.window = $0 })
                .preferredColorScheme(delegate.session.appearance.scheme)
        }
        .defaultSize(width: 720, height: 448)
        .commands {
            CommandMenu("Voice Capture") {
                Button("Start or Finish Recording") { delegate.session.shortcutAction() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Cancel Capture") { delegate.session.cancel() }
                    .disabled(!delegate.session.canCancel)
                Button("Open Last Thought") { delegate.session.openReceipt() }
                    .disabled(delegate.session.receipt == nil)
                Button("Undo Last Capture") { delegate.session.undo() }
                    .disabled(delegate.session.receipt == nil)
            }
        }
    }
}

@main @MainActor
enum VoiceStudyMain {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first {
        case "--workflow": Task { await LocalBenchmark.workflow(Array(arguments.dropFirst())) }
        case "--validate-cache": Task.detached { await LocalBenchmark.verifyCachePolicy() }
        case "--lifecycle": Task.detached { await LocalBenchmark.lifecycle(Array(arguments.dropFirst())) }
        case "--mic-probe": Task.detached { await NativeMic.run(Array(arguments.dropFirst())) }
        case "--profile": Task.detached { await LocalBenchmark.profile(Array(arguments.dropFirst())) }
        case "--benchmark": Task.detached { await LocalBenchmark.run(Array(arguments.dropFirst())) }
        case "--prepare" where arguments.count == 2:
            Task.detached {
                do {
                    try await StudyRecognizer.installApple(language: arguments[1])
                    print("Prepared \(arguments[1])")
                    exit(0)
                } catch {
                    print("Preparation failed: \(error.localizedDescription)")
                    exit(1)
                }
            }
        case "--visual":
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            Task { await NativeEvidence.run() }
            app.run()
            return
        case "--validate": Task { await StudyValidation.run() }
        default: StudyScene.main(); return
        }
        dispatchMain()
    }
}
