import Foundation
import GRDB

struct Note: Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "notes"

    let id: UUID
    var content: String
    let createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var keptAt: Date?

    enum Columns: String, ColumnExpression {
        case id
        case content
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case keptAt = "kept_at"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case content
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case keptAt = "kept_at"
    }

    var isKept: Bool {
        keptAt != nil
    }

    var displayTitle: String {
        Self.truncate(meaningfulLines.first ?? content.trimmingCharacters(in: .whitespacesAndNewlines), to: 80)
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
