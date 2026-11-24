import Darwin
import Foundation
import UniformTypeIdentifiers

enum NoteExportFiles {
    static let markdownType = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText

    struct Manifest: Codable {
        var version = 1
        let notes: [Entry]

        struct Entry: Codable {
            let id: UUID
            let file: String
            let createdAt: Date
            let updatedAt: Date
            let keptAt: Date?
            /// For mixed notes, ranges refer to the UTF-8 bytes of the Markdown file.
            let parts: [Part]?
        }

        struct Part: Codable {
            var offset: Int?
            var length: Int?
            var image: String?
            var type: String?
        }
    }

    static func filename(for note: Note) -> String {
        let safe = note.displayTitle.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) || "/\\:<>\"|?*".unicodeScalars.contains(scalar)
                ? " " : String(scalar)
        }.joined()
        let trimmed = safe.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        var name = ""
        var length = 0
        for character in trimmed {
            let bytes = String(character).utf8.count
            guard length + bytes <= 100 else { break }
            name.append(character)
            length += bytes
        }
        if name.lowercased().hasSuffix(".md") { name.removeLast(3) }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if name.isEmpty { return "Thought" }
        // These names can change agent behavior or be special files on other systems.
        let reserved = ["agents", "claude", "gemini", "con", "prn", "aux", "nul"]
        let stem = name.lowercased().split(separator: ".").first.map(String.init) ?? ""
        if reserved.contains(stem) || stem.wholeMatch(of: /(?:com|lpt)[1-9]/) != nil {
            return "Thought – " + name
        }
        return name
    }

    static func writeText(_ document: NoteDocument, note: Note, to destination: URL) throws {
        guard !document.hasImages else { throw NoteExportError.invalidOutput }
        try Task.checkCancellation()
        // The save panel confirms an explicit replacement. Foundation publishes the
        // complete file atomically, so a failed write does not truncate an earlier copy.
        try Data(document.text.utf8).write(to: destination, options: .atomic)
        applyDates(note, to: destination)
    }

    static func writeFolder(
        _ snapshots: [NoteExportSnapshot],
        repository: NoteRepository,
        in directory: URL,
        named name: String
    ) async throws -> URL {
        let manager = FileManager.default
        let staging = directory.appending(path: ".rasc-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try Task.checkCancellation()
        try manager.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var published = false
        defer {
            if !published { try? manager.removeItem(at: staging) }
        }

        var usedNames = Set<String>()
        var manifest: [Manifest.Entry] = []
        for snapshot in snapshots {
            try Task.checkCancellation()
            let document = try await repository.documentForExport(snapshot)
            let note = snapshot.note
            let stem = filename(for: note)
            var candidate = stem
            var index = 2
            while !usedNames.insert(candidate.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))).inserted {
                candidate = "\(stem) \(index)"
                index += 1
            }
            let file = candidate + ".md"
            let markdown = staging.appending(path: file)
            let parts = try write(document, id: note.id, to: markdown, in: staging)
            applyDates(note, to: markdown)
            manifest.append(.init(
                id: note.id, file: file, createdAt: note.createdAt,
                updatedAt: note.updatedAt, keptAt: note.keptAt, parts: parts
            ))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        let metadata = try encoder.encode(Manifest(notes: manifest))
        try metadata.write(to: staging.appending(path: "manifest.json"))
        try Task.checkCancellation()

        // Stage on the same volume, then publish without overwriting another folder
        // even if another process creates it between the filename check and the move.
        for number in 1...1_000 {
            let suffix = number == 1 ? "" : " \(number)"
            let destination = directory.appending(path: name + suffix, directoryHint: .isDirectory)
            try Task.checkCancellation()
            let result: Int32 = staging.withUnsafeFileSystemRepresentation { source in
                destination.withUnsafeFileSystemRepresentation { target in
                    guard let source, let target else {
                        errno = EINVAL
                        return -1
                    }
                    return renamex_np(source, target, UInt32(RENAME_EXCL))
                }
            }
            if result == 0 {
                published = true
                return destination
            }
            let code = errno
            if code != EEXIST { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
        }
        throw NoteExportError.destinationConflict
    }

    private static func write(_ document: NoteDocument, id: UUID, to markdown: URL, in folder: URL) throws -> [Manifest.Part]? {
        guard document.hasImages else {
            try Data(document.text.utf8).write(to: markdown)
            return nil
        }

        let assetPath = "assets/\(id.uuidString.lowercased())"
        let assetFolder = folder.appending(path: assetPath, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: assetFolder, withIntermediateDirectories: true)
        var images: [String] = []
        for part in document.parts {
            guard case let .image(bytes, type) = part else { continue }
            try Task.checkCancellation()
            let suggested = UTType(type)?.preferredFilenameExtension ?? ""
            let validExtension = !suggested.isEmpty && suggested.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
            }
            let file = String(format: "image-%03d", images.count + 1) + "." + (validExtension ? suggested : "image")
            try bytes.write(to: assetFolder.appending(path: file))
            images.append("\(assetPath)/\(file)")
        }

        var rendered = render(document, images: images, literal: false)
        // A fragment may have opened a code fence or an HTML block across an image.
        // Fall back to fenced literal text only when Markdown hides a generated link.
        if !hasOrderedImages(rendered.data, expected: images) {
            rendered = render(document, images: images, literal: true)
            guard hasOrderedImages(rendered.data, expected: images) else { throw NoteExportError.invalidOutput }
        }
        try Task.checkCancellation()
        try rendered.data.write(to: markdown)
        return rendered.parts
    }

    private static func render(_ document: NoteDocument, images: [String], literal: Bool) -> (data: Data, parts: [Manifest.Part]) {
        var data = Data()
        var parts: [Manifest.Part] = []
        var nextImage = 0
        for part in document.parts {
            switch part {
            case let .text(text):
                let fence = literal ? literalFence(for: text) : ""
                if literal { data.append(contentsOf: (fence + "text\n").utf8) }
                parts.append(.init(offset: data.count, length: text.utf8.count))
                data.append(contentsOf: text.utf8)
                if literal { data.append(contentsOf: ("\n" + fence + "\n\n").utf8) }
            case let .image(_, type):
                let asset = images[nextImage]
                nextImage += 1
                parts.append(.init(image: asset, type: type))
                data.append(contentsOf: "\n\n![Image \(nextImage)](\(asset))\n\n".utf8)
            }
        }
        return (data, parts)
    }

    private static func literalFence(for text: String) -> String {
        var run = 0
        var width = 3
        for byte in text.utf8 {
            run = byte == 96 ? run + 1 : 0
            width = max(width, run + 1)
        }
        return String(repeating: "`", count: width)
    }

    private static func hasOrderedImages(_ data: Data, expected: [String]) -> Bool {
        guard let rendered = try? AttributedString(markdown: data) else { return false }
        let expectedPaths = Set(expected)
        let images = rendered.runs.compactMap(\.imageURL).map(\.relativeString)
        return images.filter(expectedPaths.contains) == expected
    }

    private static func applyDates(_ note: Note, to url: URL) {
        // Some filesystems do not allow creation dates. The manifest still preserves
        // them exactly for folders, and the file remains a valid export.
        try? FileManager.default.setAttributes(
            [.creationDate: note.createdAt, .modificationDate: note.updatedAt], ofItemAtPath: url.path
        )
    }
}
