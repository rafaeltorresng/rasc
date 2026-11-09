import Foundation
import GRDB
import ImageIO

struct Note: Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "notes"

    let id: UUID
    var content: String
    let createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var keptAt: Date?
    var hasImages: Bool = false

    enum Columns: String, ColumnExpression {
        case id
        case content
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case keptAt = "kept_at"
        case hasImages = "has_images"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case content
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case keptAt = "kept_at"
        case hasImages = "has_images"
    }

    var isKept: Bool {
        keptAt != nil
    }

    var displayTitle: String {
        let title = Self.truncate(meaningfulLines.first ?? "", to: 80)
        return title.isEmpty ? (hasImages ? "Image" : "Empty thought") : title
    }

    var displaySnippet: String? {
        let detail = meaningfulLines.dropFirst().joined(separator: " ")
        guard !detail.isEmpty else { return nil }
        return Self.truncate(detail, to: 120)
    }

    /// Home browse excerpt: body beyond the title line when enough content exists.
    var displayHomeExcerpt: String? {
        if let snippet = displaySnippet, !snippet.isEmpty {
            return snippet
        }

        let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.count > title.count + 10 else { return nil }

        let remainder = body.dropFirst(title.hasSuffix("…") ? title.count - 1 : title.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard remainder.count >= 8 else { return nil }
        return Self.truncate(remainder, to: 120)
    }

    /// Snippet for retrieval UI; omits text already shown in the title when possible.
    var displayRetrievalSnippet: String? {
        guard let snippet = displaySnippet else { return nil }

        let title = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSnippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSnippet.isEmpty else { return nil }

        if normalizedSnippet.caseInsensitiveCompare(title) == .orderedSame {
            return nil
        }

        if normalizedSnippet.hasPrefix(title) {
            let remainder = normalizedSnippet.dropFirst(title.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return remainder.isEmpty ? nil : Self.truncate(remainder, to: 120)
        }

        return snippet
    }

    /// A plain-text excerpt around a matched word, preserving the original spelling.
    func retrievalSnippet(matching query: String) -> String? {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let matches = terms.compactMap { term in
            content.range(of: term, options: [.caseInsensitive, .diacriticInsensitive])
        }
        guard !matches.isEmpty else { return displayRetrievalSnippet ?? displayHomeExcerpt }
        let visibleTitleLength = displayTitle.hasSuffix("…") ? displayTitle.count - 1 : displayTitle.count
        let match = matches.first { content.distance(from: content.startIndex, to: $0.lowerBound) >= visibleTitleLength }
            ?? matches[0]
        let offset = content.distance(from: content.startIndex, to: match.lowerBound)
        let start = max(0, offset - 32)
        let remaining = content.dropFirst(start)
        let excerpt = String(remaining.prefix(120)).replacingOccurrences(of: "\n", with: " ")
        return (start > 0 ? "…" : "") + excerpt + (remaining.count > 120 ? "…" : "")
    }

    private var meaningfulLines: [String] {
        content
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "…"
    }
}

/// The image-aware format is deliberately limited to ordered text and images.
/// The database stores this alongside a derived text projection, in one transaction.
struct NoteDocument: Codable, Equatable, Sendable {
    static let currentVersion = 1

    enum Part: Codable, Equatable, Sendable {
        case text(String)
        case image(data: Data, typeIdentifier: String)
    }

    let version: Int
    var parts: [Part]

    init(parts: [Part]) {
        version = Self.currentVersion
        var normalized: [Part] = []
        for part in parts {
            if case let .text(text) = part {
                guard !text.isEmpty else { continue }
                if case let .text(previous)? = normalized.last {
                    normalized[normalized.count - 1] = .text(previous + text)
                } else {
                    normalized.append(.text(text))
                }
            } else {
                normalized.append(part)
            }
        }
        self.parts = normalized.isEmpty ? [.text("")] : normalized
    }

    var text: String {
        parts.map { part in
            switch part {
            case .text(let text): text
            case .image: ""
            }
        }.joined()
    }

    var hasImages: Bool {
        parts.contains { if case .image = $0 { true } else { false } }
    }

    func validate() throws {
        guard version == Self.currentVersion else { throw DocumentError.unsupportedVersion }
        for part in parts {
            if case let .image(data, typeIdentifier) = part {
                guard !data.isEmpty,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      CGImageSourceGetCount(source) > 0,
                      let detected = CGImageSourceGetType(source) as String?,
                      detected == typeIdentifier else {
                    throw DocumentError.invalidImage
                }
            }
        }
    }

    enum DocumentError: Error {
        case unsupportedVersion
        case invalidImage
    }
}

extension NoteDocument {
    /// NSTextView represents an attachment as one UTF-16 object replacement character.
    /// This string is only for mapping editor selections; it is never the search projection.
    var editorText: String {
        parts.map { part in
            switch part {
            case .text(let text): text
            case .image: "\u{fffc}"
            }
        }.joined()
    }

    struct Insertion: Equatable {
        let document: NoteDocument
        let caretUTF16Offset: Int
    }

    enum EditError: Error {
        case invalidSelection
    }

    /// Replaces a selection with an image on its own line. The text outside the
    /// selection and all other attachments remain in their original order.
    func insertingImage(data: Data, typeIdentifier: String, replacing range: NSRange) throws -> Insertion {
        let visible = editorText
        guard range.location != NSNotFound,
              range.location >= 0, range.length >= 0,
              range.location <= visible.utf16.count,
              range.length <= visible.utf16.count - range.location,
              isScalarBoundary(range.location, in: visible),
              isScalarBoundary(NSMaxRange(range), in: visible) else {
            throw EditError.invalidSelection
        }
        var before = slice(0..<range.location)
        var after = slice(NSMaxRange(range)..<visible.utf16.count)
        let beforeText = NoteDocument(parts: before).editorText
        let afterText = NoteDocument(parts: after).editorText
        if !beforeText.isEmpty && !beforeText.hasSuffix("\n") {
            before.append(.text("\n"))
        }
        before.append(.image(data: data, typeIdentifier: typeIdentifier))
        let prefixLength = NoteDocument(parts: before).editorText.utf16.count
        let caret: Int
        if afterText.hasPrefix("\n") {
            caret = prefixLength + 1
        } else {
            after.insert(.text("\n"), at: 0)
            caret = prefixLength + 1
        }
        return Insertion(document: NoteDocument(parts: before + after), caretUTF16Offset: caret)
    }

    func insertingDocument(_ fragment: NoteDocument, replacing range: NSRange) throws -> Insertion {
        let visible = editorText
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= visible.utf16.count,
              range.length <= visible.utf16.count - range.location,
              isScalarBoundary(range.location, in: visible),
              isScalarBoundary(NSMaxRange(range), in: visible) else { throw EditError.invalidSelection }
        var before = slice(0..<range.location)
        var inserted = fragment.parts
        let after = slice(NSMaxRange(range)..<visible.utf16.count)
        let prefix = NoteDocument(parts: before).editorText
        if case .image? = inserted.first, !prefix.isEmpty, !prefix.hasSuffix("\n") {
            before.append(.text("\n"))
        }
        var caret = NoteDocument(parts: before + inserted).editorText.utf16.count
        if case .image? = inserted.last {
            if NoteDocument(parts: after).editorText.hasPrefix("\n") {
                caret += 1
            } else {
                inserted.append(.text("\n"))
                caret += 1
            }
        }
        return Insertion(document: NoteDocument(parts: before + inserted + after), caretUTF16Offset: caret)
    }

    func placingImagesOnSeparateLines() -> NoteDocument {
        var result: [Part] = []
        var needsNewline = false
        for part in parts {
            switch part {
            case .text(let text):
                if needsNewline && !text.hasPrefix("\n") { result.append(.text("\n")) }
                result.append(.text(text))
                needsNewline = false
            case .image:
                if needsNewline { result.append(.text("\n")) }
                let prefix = NoteDocument(parts: result).editorText
                if !prefix.isEmpty && !prefix.hasSuffix("\n") { result.append(.text("\n")) }
                result.append(part)
                needsNewline = true
            }
        }
        if needsNewline { result.append(.text("\n")) }
        return NoteDocument(parts: result)
    }

    func selecting(_ range: NSRange) throws -> NoteDocument {
        let visible = editorText
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= visible.utf16.count,
              range.length <= visible.utf16.count - range.location,
              isScalarBoundary(range.location, in: visible),
              isScalarBoundary(NSMaxRange(range), in: visible) else {
            throw EditError.invalidSelection
        }
        return NoteDocument(parts: slice(range.location..<NSMaxRange(range)))
    }

    private func isScalarBoundary(_ offset: Int, in text: String) -> Bool {
        let index = text.utf16.index(text.utf16.startIndex, offsetBy: offset)
        return index.samePosition(in: text.unicodeScalars) != nil
    }

    private func slice(_ selection: Range<Int>) -> [Part] {
        guard !selection.isEmpty else { return [] }
        var result: [Part] = []
        var offset = 0
        for part in parts {
            let length: Int
            switch part {
            case .text(let text): length = text.utf16.count
            case .image: length = 1
            }
            let lower = max(selection.lowerBound, offset)
            let upper = min(selection.upperBound, offset + length)
            if lower < upper {
                switch part {
                case .text(let text):
                    let value = (text as NSString).substring(with: NSRange(location: lower - offset, length: upper - lower))
                    result.append(.text(value))
                case .image:
                    result.append(part)
                }
            }
            offset += length
        }
        return result
    }
}
