import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Rasc

/// Renders the real Home views through an offscreen NSWindow + NSHostingView so the
/// list/cards layouts, search-match highlighting and header chrome can be eye-verified
/// in PNGs. Unlike ImageRenderer this uses the real AppKit pipeline, so ScrollView,
/// containerBackground and NSTextField all draw. The window is never ordered front.
@MainActor
@Suite(.serialized)
struct HomeSnapshotTests {
    private func makeSeededSession(query: String? = nil) async throws -> HomeSession {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: "HomeSnapshotTests.\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        let repository = try NoteRepository(databaseURL: databaseURL)

        let milk = try await repository.createScratch(content: "gratitude journal\natm coffee grateful sunrise quiet morning pages")
        _ = try await repository.createScratch(content: "gratify the craft\nbuild the thing slowly and completely before showing it")
        _ = try await repository.createScratch(content: "packing list\npassport\ncharger\nrain jacket")
        _ = try await repository.createScratch(content: "disintegrate this long middle word that should not match a token-start prefix query cleanly at all")
        _ = try await repository.createScratch(content: "ideas for the weekend\nbike route along the river\nlong breakfast")
        _ = try await repository.keep(id: milk.id)

        let session = await MainActor.run {
            HomeSession(repository: repository)
        }
        if let query {
            await MainActor.run {
                session.searchQuery = query
            }
        }
        await session.reloadImmediately()
        return session
    }

    private func renderPNG<V: View>(
        _ view: V, width: CGFloat, height: CGFloat, scheme: ColorScheme, name: String,
        palette: RascSurfacePalette = .standard, textSize: NoteTextSize = .standard
    ) throws {
        let contentRect = NSRect(x: -20000, y: -20000, width: width, height: height)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = scheme == .dark ? .black : .windowBackgroundColor
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let host = NSHostingView(
            rootView: ZStack {
                palette.canvas(for: scheme)
                view
            }
            .environment(\.colorScheme, scheme)
            .environment(\.rascPalette, palette)
            .environment(\.noteTextSize, textSize)
            .frame(width: width, height: height)
        )
        host.frame = NSRect(origin: .zero, size: contentRect.size)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            Issue.record("Could not allocate a bitmap for \(name)")
            return
        }
        host.cacheDisplay(in: host.bounds, to: rep)

        let dir = FileManager.default.temporaryDirectory.appending(path: "rasc-snapshots", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            Issue.record("Could not encode \(name) as PNG")
            return
        }
        try data.write(to: dir.appending(path: "\(name).png"))
        window.close()
    }

    private func homeView(session: HomeSession, scheme: ColorScheme) -> some View {
        HomeView(
            session: session,
            onOpenNote: { _ in },
            onNewScratch: {},
            onNoteDiscarded: { _ in },
            onNoteUnkept: { _ in },
            onExportThought: { _ in }
        )
        .environment(\.colorScheme, scheme)
    }

    @Test
    func quickSearchAndPaletteMarksRender() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: "SearchSnapshotTests.\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        let suiteName = "SearchSnapshotTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let repository = try NoteRepository(databaseURL: databaseURL)
        _ = try await repository.createScratch(content: "gratitude journal\natm coffee grateful sunrise quiet morning pages")
        _ = try await repository.createScratch(content: "gratify the craft\nbuild the thing slowly")
        _ = try await repository.createScratch(content: "packing list\npassport\ncharger")
        let session = ScratchpadSession(repository: repository, userDefaults: userDefaults)

        try await session.openSearch()
        await MainActor.run {
            session.searchQuery = "grat"
            session.scheduleSearch()
        }
        let deadline = Date().addingTimeInterval(2)
        while session.searchResults.count != 2, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(session.searchResults.count == 2)
        try renderPNG(
            HistorySearchView(session: session),
            width: 560,
            height: 250,
            scheme: .light,
            name: "quick-search-grat-light"
        )

        try renderPNG(
            HistorySearchView(session: session), width: 560, height: 250, scheme: .dark,
            name: "quick-search-custom-large-dark", palette: RascSurfacePalette(preset: .custom, custom: Self.customColors),
            textSize: .large
        )

        await MainActor.run {
            session.openCommandPalette()
            session.commandPaletteQuery = "re"
        }
        try renderPNG(
            CommandPaletteView(session: session, onExecute: { _ in }),
            width: 560,
            height: 240,
            scheme: .light,
            name: "command-palette-re-light"
        )
    }

    @Test
    func refinePreviewChangesRender() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: "RefinePreviewSnapshotTests.\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        let suiteName = "RefinePreviewSnapshotTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let repository = try NoteRepository(databaseURL: databaseURL)
        let provider = FixedRefinementProvider(
            originalToRefined: [
                "draft the memo on friday please": "draft the memo on monday"
            ]
        )
        let session = ScratchpadSession(
            repository: repository,
            refinementProvider: provider,
            userDefaults: userDefaults
        )
        session.text = "draft the memo on friday please"
        session.startRefinement()
        let deadline = Date().addingTimeInterval(2)
        while session.surface != .refinementPreview, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(session.surface == .refinementPreview)
        // Pin the Changes tab: the test renders the diff view regardless of the
        // default preview mode.
        session.previewMode = .changes

        for (scheme, name) in [(ColorScheme.light, "refine-preview-changes-light"),
                               (ColorScheme.dark, "refine-preview-changes-dark")] {
            let view = ScratchpadView(
                session: session,
                onEscape: {},
                onPaletteCommand: { _ in },
                onOpenHome: {},
                onKeep: {},
                onUnkeep: {}
            )
            .environment(\.colorScheme, scheme)
            try renderPNG(view, width: 720, height: 480, scheme: scheme, name: name)
        }
    }

    @Test
    func refinePreviewSuggestedRender() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: "RefinePreviewSuggestedTests.\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        let suiteName = "RefinePreviewSuggestedTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let repository = try NoteRepository(databaseURL: databaseURL)
        let provider = FixedRefinementProvider(
            originalToRefined: [
                "draft the memo on friday please": "draft the memo on monday"
            ]
        )
        let session = ScratchpadSession(
            repository: repository,
            refinementProvider: provider,
            userDefaults: userDefaults
        )
        session.text = "draft the memo on friday please"
        session.startRefinement()
        let deadline = Date().addingTimeInterval(2)
        while session.surface != .refinementPreview, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(session.surface == .refinementPreview)
        // The app opens on Suggested (the documented flow); pin it so the render
        // can't drift with the default.
        session.previewMode = .suggested

        let view = ScratchpadView(
            session: session,
            onEscape: {},
            onPaletteCommand: { _ in },
            onOpenHome: {},
            onKeep: {},
            onUnkeep: {}
        )
        try renderPNG(view, width: 720, height: 480, scheme: .light, name: "refine-preview-suggested-light")
        let palette = RascSurfacePalette(preset: .custom, custom: Self.customColors)
        try renderPNG(view, width: 560, height: 320, scheme: .dark,
                      name: "refine-preview-custom-large-dark", palette: palette, textSize: .large)
    }

    @Test
    func settingsThemeSectionRender() throws {
        let suiteName = "SettingsThemeSnapshots.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ThemeStore(store: ThemeSettingsStore(userDefaults: defaults))
        try renderPNG(
            SettingsView(themeStore: store), width: 500, height: 860, scheme: .light,
            name: "settings-theme-light"
        )
        store.selectPreset(.slate)
        try renderPNG(
            SettingsView(themeStore: store), width: 500, height: 860, scheme: .dark,
            name: "settings-theme-slate-dark", palette: store.palette
        )
        store.selectPreset(.custom)
        store.applyCustomPalette(Self.customColors)
        let minimumHeight = SettingsWindowPresentation.fittedMinimumHeight(
            visibleHeight: NSScreen.main?.visibleFrame.height ?? 680
        )
        for (scheme, name) in [(ColorScheme.light, "light"), (.dark, "dark")] {
            try renderPNG(
                SettingsView(themeStore: store), width: 460, height: minimumHeight, scheme: scheme,
                name: "settings-custom-\(name)", palette: store.palette
            )
        }
    }

    private static var customColors: CustomTheme {
        CustomTheme(
            light: CustomThemeColors(
                background: NSColor(srgbRed: 0.89, green: 0.94, blue: 0.89, alpha: 1),
                noteText: NSColor(srgbRed: 0.13, green: 0.24, blue: 0.17, alpha: 1)
            ),
            dark: CustomThemeColors(
                background: NSColor(srgbRed: 0.13, green: 0.16, blue: 0.25, alpha: 1),
                noteText: NSColor(srgbRed: 0.83, green: 0.90, blue: 1, alpha: 1)
            )
        )
    }

    @Test
    func scratchpadImageOutlineRenders() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appending(path: "ScratchpadImageSnapshotTests.\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        let suiteName = "ScratchpadImageSnapshotTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let repository = try NoteRepository(databaseURL: databaseURL)
        let session = ScratchpadSession(repository: repository, userDefaults: userDefaults)

        let text = "image note\n"
        await MainActor.run {
            session.text = text
        }
        try await session.flush()
        let pngData = try makeSolidPNG(width: 220, height: 140, red: 0.72, green: 0.24, blue: 0.16)
        _ = try await session.insertImage(
            .image(data: pngData, typeIdentifier: "public.png"),
            selection: NSRange(location: (text as NSString).length, length: 0)
        )
        try await session.flush()

        let view = ScratchpadView(
            session: session,
            onEscape: {},
            onPaletteCommand: { _ in },
            onOpenHome: {},
            onKeep: {},
            onUnkeep: {}
        )
        try renderPNG(view, width: 720, height: 420, scheme: .light, name: "scratchpad-image-light")
        try renderPNG(view, width: 720, height: 420, scheme: .dark, name: "scratchpad-image-dark")
        try renderPNG(view, width: 560, height: 320, scheme: .light, name: "scratchpad-custom-large-light",
                      palette: RascSurfacePalette(preset: .custom, custom: Self.customColors), textSize: .large)
    }

    private func makeSolidPNG(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) throws -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ) else {
            throw NSError(domain: "ScratchpadImageOutlineRenders", code: 1)
        }
        rep.size = NSSize(width: width, height: height)
        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: rep) else {
            throw NSError(domain: "ScratchpadImageOutlineRenders", code: 2)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ScratchpadImageOutlineRenders", code: 3)
        }
        return data
    }

    @Test
    func listCardsAndSearchVariantsRender() async throws {
        HomeViewModeStore(userDefaults: .standard).save(.list)
        let listSession = try await makeSeededSession()
        try renderPNG(homeView(session: listSession, scheme: .light), width: 1000, height: 560, scheme: .light, name: "home-list-light")
        try renderPNG(homeView(session: listSession, scheme: .dark), width: 1000, height: 560, scheme: .dark, name: "home-list-dark")

        HomeViewModeStore(userDefaults: .standard).save(.cards)
        let cardsSession = try await makeSeededSession()
        try renderPNG(homeView(session: cardsSession, scheme: .light), width: 1000, height: 660, scheme: .light, name: "home-cards-light")
        try renderPNG(homeView(session: cardsSession, scheme: .dark), width: 1000, height: 660, scheme: .dark, name: "home-cards-dark")

        let searchSession = try await makeSeededSession(query: "grat")
        try renderPNG(homeView(session: searchSession, scheme: .light), width: 1000, height: 420, scheme: .light, name: "home-cards-light-search")

        let palette = RascSurfacePalette(preset: .custom, custom: Self.customColors)
        try renderPNG(homeView(session: searchSession, scheme: .dark), width: 760, height: 520, scheme: .dark,
                      name: "home-cards-custom-large-dark", palette: palette, textSize: .large)
        HomeViewModeStore(userDefaults: .standard).save(.list)
        try renderPNG(homeView(session: listSession, scheme: .light), width: 760, height: 520, scheme: .light,
                      name: "home-list-custom-large-light", palette: palette, textSize: .large)
    }
}

private struct FixedRefinementProvider: RefinementProvider {
    let metadata = RefinementMetadata(
        provider: "snapshot",
        modelIdentifier: "snapshot",
        promptVersion: "snapshot"
    )
    let originalToRefined: [String: String]

    func availability(for _: RefinementRequest) async -> RefinementAvailability {
        .available
    }

    func refine(_ request: RefinementRequest) async throws -> RefinementResult {
        RefinementResult(
            decision: .changed,
            kind: .messyText,
            text: originalToRefined[request.snapshot.text] ?? request.snapshot.text
        )
    }
}
