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
}
