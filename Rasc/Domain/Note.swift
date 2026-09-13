import Foundation
import GRDB

struct Note: Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "notes"

    let id: UUID
    var content: String
    let createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum Columns: String, ColumnExpression {
        case id
        case content
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case content
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    var displayTitle: String {
        Self.truncate(meaningfulLines.first ?? content.trimmingCharacters(in: .whitespacesAndNewlines), to: 80)
    }

    var displaySnippet: String? {
        let detail = meaningfulLines.dropFirst().joined(separator: " ")
        guard !detail.isEmpty else { return nil }
        return Self.truncate(detail, to: 120)
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
