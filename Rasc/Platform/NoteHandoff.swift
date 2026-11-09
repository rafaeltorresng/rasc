import AppKit
import ImageIO
import UniformTypeIdentifiers

enum NoteHandoff {
    enum TransferError: Error { case unavailable }
    static let documentPasteboardType = NSPasteboard.PasteboardType("com.rafaeltorres.rasc.document.v1")
    struct SharePayload: Sendable {
        let data: Data
        let typeIdentifier: String
    }

    /// Rich notes advertise RTFD only: a destination unable to accept the whole
    /// note must not silently receive a text-only copy.
    @MainActor
    static func copy(_ document: NoteDocument, to pasteboard: NSPasteboard = .general) async throws {
        if !document.hasImages {
            pasteboard.clearContents()
            guard pasteboard.setString(document.text, forType: .string) else { throw TransferError.unavailable }
            return
        }
        let previousChangeCount = pasteboard.changeCount
        let rich = try await richData(document)
        let internalData = try await Task.detached(priority: .userInitiated) {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            return try encoder.encode(document)
        }.value
        guard pasteboard.changeCount == previousChangeCount else { throw TransferError.unavailable }
        pasteboard.clearContents()
        guard pasteboard.setData(rich, forType: .rtfd),
              pasteboard.setData(internalData, forType: documentPasteboardType) else { throw TransferError.unavailable }
        let images = document.parts.compactMap { part -> (Data, String)? in
            if case let .image(data, type) = part { return (data, type) }
            return nil
        }
        if images.count == 1, document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard pasteboard.setData(images[0].0, forType: NSPasteboard.PasteboardType(images[0].1)) else { throw TransferError.unavailable }
        }
    }

    @MainActor
    static func presentSharePicker(for document: NoteDocument, relativeTo view: NSView) async throws {
        let items: [Any]
        if document.hasImages {
            let payload = try await sharePayload(document)
            items = [NSItemProvider(item: payload.data as NSData, typeIdentifier: payload.typeIdentifier)]
        } else {
            items = [document.text]
        }
        NSSharingServicePicker(items: items).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    static func sharePayload(_ document: NoteDocument) async throws -> SharePayload {
        let images = document.parts.compactMap { part -> (Data, String)? in
            if case let .image(data, type) = part { return (data, type) }
            return nil
        }
        if images.count == 1, document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return SharePayload(data: images[0].0, typeIdentifier: images[0].1)
        }
        return SharePayload(data: try await richData(document), typeIdentifier: UTType.rtfd.identifier)
    }

    private static func richData(_ document: NoteDocument) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let result = NSMutableAttributedString()
            for part in document.parts {
                switch part {
                case .text(let text):
                    result.append(NSAttributedString(string: text))
                case let .image(data, type):
                    let wrapper = FileWrapper(regularFileWithContents: data)
                    wrapper.preferredFilename = "Image-\(UUID().uuidString).\(UTType(type)?.preferredFilenameExtension ?? "image")"
                    result.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper)))
                }
            }
            return try result.data(from: NSRange(location: 0, length: result.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        }.value
    }

}

/// Reads original image bytes away from the main actor. The bounded read prevents
/// an unexpectedly large clipboard file from exhausting the process before it can
/// report an import error.
enum NoteImageImport {
    static let maximumBytes = 128 * 1024 * 1024

    enum Source: Sendable {
        case data(Data)
        case file(URL)
        case pasteboard(name: String, type: String, changeCount: Int)
        case documentPasteboard(name: String, type: String, changeCount: Int)
    }

    enum ImportError: Error {
        case notLocalFile
        case tooLarge
        case tooMuchContent
        case invalidImage
        case clipboardChanged
        case thoughtChanged
    }

    static func loadDocument(name: String, type: String, changeCount: Int) async throws -> NoteDocument {
        try await Task.detached(priority: .userInitiated) {
            let board = NSPasteboard(name: NSPasteboard.Name(name))
            guard board.changeCount == changeCount,
                  let data = board.data(forType: NSPasteboard.PasteboardType(type)),
                  board.changeCount == changeCount else { throw ImportError.clipboardChanged }
            guard data.count <= 260 * 1024 * 1024 else { throw ImportError.tooMuchContent }
            if type == NoteHandoff.documentPasteboardType.rawValue {
                let document = try PropertyListDecoder().decode(NoteDocument.self, from: data)
                try document.validate()
                return document.placingImagesOnSeparateLines()
            }
            guard type == NSPasteboard.PasteboardType.rtfd.rawValue else { throw ImportError.invalidImage }
            let content = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
            var parts: [NoteDocument.Part] = []
            var invalid = false
            content.enumerateAttribute(.attachment, in: NSRange(location: 0, length: content.length)) { value, range, _ in
                if let attachment = value as? NSTextAttachment {
                    guard let bytes = attachment.contents ?? attachment.fileWrapper?.regularFileContents,
                          bytes.count <= maximumBytes,
                          let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                          let imageType = CGImageSourceGetType(source) as String?,
                          CGImageSourceGetCount(source) > 0,
                          CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 64] as CFDictionary) != nil else {
                        invalid = true
                        return
                    }
                    parts.append(.image(data: bytes, typeIdentifier: imageType))
                } else if value == nil {
                    parts.append(.text((content.string as NSString).substring(with: range)))
                } else {
                    invalid = true
                }
            }
            guard !invalid else { throw ImportError.invalidImage }
            return NoteDocument(parts: parts).placingImagesOnSeparateLines()
        }.value
    }

    static func load(_ source: Source) async throws -> NoteDocument.Part {
        let task = Task.detached(priority: .userInitiated) {
            let data: Data
            switch source {
            case .data(let bytes):
                guard bytes.count <= maximumBytes else { throw ImportError.tooLarge }
                data = bytes
            case let .pasteboard(name, type, changeCount):
                let pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
                guard pasteboard.changeCount == changeCount,
                      let bytes = pasteboard.data(forType: NSPasteboard.PasteboardType(type)),
                      pasteboard.changeCount == changeCount else { throw ImportError.clipboardChanged }
                guard bytes.count <= maximumBytes else { throw ImportError.tooLarge }
                data = bytes
            case .documentPasteboard:
                throw ImportError.invalidImage
            case .file(let url):
                guard url.isFileURL else { throw ImportError.notLocalFile }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                guard try handle.seekToEnd() <= UInt64(maximumBytes) else { throw ImportError.tooLarge }
                try handle.seek(toOffset: 0)
                var bytes = Data()
                while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                    try Task.checkCancellation()
                    guard chunk.count <= maximumBytes - bytes.count else { throw ImportError.tooLarge }
                    bytes.append(chunk)
                }
                data = bytes
            }
            try Task.checkCancellation()
            guard let image = CGImageSourceCreateWithData(data as CFData, nil),
                  let type = CGImageSourceGetType(image) as String?,
                  CGImageSourceGetCount(image) > 0,
                  CGImageSourceCreateThumbnailAtIndex(image, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 64,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary) != nil else {
                throw ImportError.invalidImage
            }
            return NoteDocument.Part.image(data: data, typeIdentifier: type)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
