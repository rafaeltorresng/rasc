import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class NoteExportController {
    private let repository: NoteRepository
    private var isPresenting = false

    init(repository: NoteRepository) {
        self.repository = repository
    }

    func exportThought(from window: NSWindow, prepare: () async throws -> UUID?) async {
        await present(from: window) {
            guard let id = try await prepareForExport(prepare) else { return }
            let snapshots = try await repository.exportSnapshot(for: .selected([id]))
            let snapshot = snapshots[0]
            let stem = NoteExportFiles.filename(for: snapshot.note)
            if snapshot.note.hasImages {
                try await exportFolder(snapshots, named: stem, from: window)
            } else {
                let panel = NSSavePanel()
                panel.title = "Export Thought"
                panel.prompt = "Export"
                panel.nameFieldStringValue = stem + ".md"
                panel.allowedContentTypes = [NoteExportFiles.markdownType]
                panel.canCreateDirectories = true
                panel.message = "Save this thought as a Markdown text file."
                guard let destination = await chooseDestination(panel, from: window) else { return }
                try await write(from: window, to: destination, message: "Exporting thought…") {
                    let document = try await self.repository.documentForExport(snapshot)
                    try NoteExportFiles.writeText(document, note: snapshot.note, to: destination)
                    return destination
                }
            }
        }
    }

    func exportThoughts(from window: NSWindow, prepare: (NoteExportScope) async throws -> Void) async {
        await present(from: window) {
            let notes = try await repository.fetchAllNonDeleted()
            guard !notes.isEmpty else { throw NoteExportError.empty }
            guard let scope = await pickThoughts(notes, from: window) else { return }
            try await prepareForExport { try await prepare(scope) }
            let snapshots = try await repository.exportSnapshot(for: scope)
            try await exportFolder(snapshots, named: "Rasc Thoughts", from: window)
        }
    }

    /// Batch export of an explicit selection to a single Markdown folder.
    /// Reuses `NoteExportFiles.writeFolder`, preserving images and resolving
    /// filename collisions. Does not show a picker; the caller supplies ids.
    func exportSelectedThoughts(from window: NSWindow, ids: Set<UUID>, named name: String = "Rasc Thoughts", prepare: (NoteExportScope) async throws -> Void) async {
        await present(from: window) {
            guard !ids.isEmpty else { throw NoteExportError.empty }
            let scope = NoteExportScope.selected(ids)
            try await prepareForExport { try await prepare(scope) }
            let snapshots = try await repository.exportSnapshot(for: scope)
            guard !snapshots.isEmpty else { throw NoteExportError.empty }
            try await exportFolder(snapshots, named: name, from: window)
        }
    }

    private func prepareForExport<Value>(_ prepare: () async throws -> Value) async throws -> Value {
        do { return try await prepare() }
        catch let error as NoteExportError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch { throw NoteExportError.saveFailed }
    }

    private func present(from window: NSWindow, operation: () async throws -> Void) async {
        guard !isPresenting, window.isVisible, window.attachedSheet == nil else { return }
        let previousResponder = window.firstResponder as? NSView
        isPresenting = true
        defer {
            isPresenting = false
            if window.isKeyWindow, let previousResponder, previousResponder.window === window {
                window.makeFirstResponder(previousResponder)
            }
        }
        do {
            try await operation()
        } catch is CancellationError {
            return
        } catch {
            guard window.isVisible else { return }
            let alert = NSAlert()
            alert.messageText = "Couldn’t export thoughts"
            switch error {
            case NoteExportError.empty:
                alert.informativeText = "There are no thoughts to export in this selection."
            case NoteExportError.thoughtChanged:
                alert.informativeText = "A thought changed while you were exporting. Choose Export again for the latest version."
            case NoteExportError.saveFailed:
                alert.informativeText = "Rasc couldn’t finish saving a thought. Return to the scratchpad and retry the save before exporting."
            case NoteExportError.destinationConflict:
                alert.informativeText = "Choose another folder for this export."
            case NoteExportError.invalidOutput:
                alert.informativeText = "Rasc couldn’t prepare a complete copy. You can try Copy or Share from the thought."
            default:
                alert.informativeText = "Check that you can write to the destination and that it has enough space, then try again."
            }
            alert.addButton(withTitle: "OK")
            await alert.beginSheetModal(for: window)
        }
    }

    private func exportFolder(_ snapshots: [NoteExportSnapshot], named name: String, from window: NSWindow) async throws {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Location"
        panel.prompt = "Export"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = snapshots.contains { $0.note.hasImages }
            ? "Choose where to save the export folder. Keep the text files and images together."
            : "Choose where to save the folder of Markdown text files."
        guard let directory = await chooseDestination(panel, from: window) else { return }
        try await write(from: window, to: directory, message: snapshots.count == 1 ? "Exporting thought…" : "Exporting thoughts…") {
            try await NoteExportFiles.writeFolder(snapshots, repository: self.repository, in: directory, named: name)
        }
    }

    private func chooseDestination(_ panel: NSSavePanel, from window: NSWindow) async -> URL? {
        guard window.isVisible else { return nil }
        return await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    private func pickThoughts(_ notes: [Note], from window: NSWindow) async -> NoteExportScope? {
        guard window.isVisible else { return nil }
        var choice: NoteExportScope?
        let sheet = NSWindow()
        sheet.styleMask = [.titled]
        sheet.isReleasedWhenClosed = false
        sheet.contentViewController = NSHostingController(rootView: RascAppearanceView {
            NoteExportPicker(notes: notes) { [weak window, weak sheet] scope in
                guard let window, let sheet else { return }
                choice = scope
                window.endSheet(sheet)
            }
        })
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            window.beginSheet(sheet) { _ in continuation.resume() }
        }
        return choice
    }

    private func write(
        from window: NSWindow,
        to scope: URL,
        message: String,
        operation: @escaping @Sendable () async throws -> URL
    ) async throws {
        // AppKit starts access for the URL when the user confirms the panel.
        defer { scope.stopAccessingSecurityScopedResource() }
        guard window.isVisible else { return }
        let task = Task.detached(priority: .userInitiated) {
            return try await operation()
        }

        let progress = NSWindow()
        progress.styleMask = [.titled]
        progress.isReleasedWhenClosed = false
        progress.contentViewController = NSHostingController(rootView: RascAppearanceView {
            VStack(alignment: .leading, spacing: 16) {
                ProgressView(message)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Cancel") { task.cancel() }
                    .keyboardShortcut(.cancelAction)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(20)
            .frame(width: 320)
            .rascWindowSurface()
        })
        // Avoid flashing a progress sheet for small exports.
        let presentation = Task { @MainActor in
            try await Task.sleep(for: .milliseconds(350))
            guard window.isVisible, window.attachedSheet == nil else { return }
            window.beginSheet(progress, completionHandler: nil)
        }
        let result = await withTaskCancellationHandler {
            await task.result
        } onCancel: {
            task.cancel()
        }
        presentation.cancel()
        if window.attachedSheet === progress { window.endSheet(progress) }
        let destination = try result.get()
        guard window.isVisible else { return }

        let alert = NSAlert()
        alert.messageText = "Export Complete"
        alert.informativeText = destination.lastPathComponent
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "Show in Finder")
        if await alert.beginSheetModal(for: window) == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        }
    }
}

private struct NoteExportPicker: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case kept = "Kept"
        case all = "All"
        case selected = "Selected"
        var id: Self { self }
    }

    let notes: [Note]
    let onFinish: (NoteExportScope?) -> Void
    @State private var mode: Mode
    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var selection: Set<UUID> = []
    @FocusState private var searchFocused: Bool
    @Environment(\.rascPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    // macOS draws white labels for these tinted native controls in both appearances.
    private var selectionTint: Color { RascSurfacePalette.standard.focus(for: .light) }

    init(notes: [Note], onFinish: @escaping (NoteExportScope?) -> Void) {
        self.notes = notes
        self.onFinish = onFinish
        _mode = State(initialValue: notes.contains(where: \.isKept) ? .kept : .all)
    }

    private var scope: NoteExportScope {
        switch mode {
        case .kept: .kept
        case .all: .all
        case .selected: .selected(selection)
        }
    }

    private var filtered: [Note] {
        switch mode {
        case .kept: notes.filter(\.isKept)
        case .all: notes
        case .selected:
            debouncedQuery.isEmpty ? notes : notes.filter {
                $0.displayTitle.localizedStandardContains(debouncedQuery) || $0.content.localizedStandardContains(debouncedQuery)
            }
        }
    }

    private var count: Int {
        switch mode {
        case .kept: notes.count(where: \.isKept)
        case .all: notes.count
        case .selected: selection.count
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Thoughts")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Picker("Thoughts to export", selection: $mode) {
                ForEach(Mode.allCases) { option in Text(option.rawValue).tag(option) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(selectionTint)

            Group {
                if mode == .selected {
                    ThoughtSearchField(text: $query, isFocused: $searchFocused)
                } else {
                    Text(mode == .kept ? "Includes every Kept thought." : "Includes Kept and unfinished thoughts.")
                        .font(.callout)
                        .foregroundStyle(palette.secondaryText(for: colorScheme))
                }
            }
            .frame(height: 38)

            let visible = filtered
            List {
                if visible.isEmpty {
                    Text(mode == .kept ? "No Kept thoughts" : "No matching thoughts")
                        .foregroundStyle(palette.secondaryText(for: colorScheme))
                }
                ForEach(visible, id: \.id) { note in
                    if mode == .selected {
                        Toggle(isOn: Binding(
                            get: { selection.contains(note.id) },
                            set: { checked in
                                if checked { selection.insert(note.id) }
                                else { selection.remove(note.id) }
                            }
                        )) { row(note) }
                        .toggleStyle(.checkbox)
                        .tint(selectionTint)
                    } else {
                        row(note)
                    }
                }
            }
            .listStyle(.bordered)
            .accessibilityLabel(mode == .selected ? "Choose thoughts" : "Thoughts included")
            .frame(height: 220)

            HStack(spacing: 10) {
                Text(count == 1 ? "1 thought" : "\(count) thoughts")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(palette.secondaryText(for: colorScheme))
                    .accessibilityLabel(mode == .selected ? "\(count) selected" : "\(count) included")
                Spacer()
                Button("Cancel") { onFinish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Continue…") { onFinish(scope) }
                    .keyboardShortcut(.defaultAction)
                    .tint(selectionTint)
                    .disabled(count == 0)
            }
        }
        .padding(20)
        .frame(width: 478)
        .rascWindowSurface()
        .task(id: query) {
            if query.isEmpty {
                debouncedQuery = ""
                return
            }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            debouncedQuery = query
        }
    }

    private func row(_ note: Note) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.displayTitle)
                    .lineLimit(1)
                if let excerpt = note.displayHomeExcerpt {
                    Text(excerpt)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText(for: colorScheme))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            Text(note.updatedAt, format: .dateTime.month(.abbreviated).day().year())
                .font(.caption)
                .foregroundStyle(palette.metadataText(for: colorScheme))
        }
        .padding(.vertical, 2)
    }
}
