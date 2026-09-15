import Foundation
import GRDB

struct RefinementRevision: Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "refinement_revisions"

    let id: UUID
    let noteID: UUID
    let beforeContent: String
    let afterContent: String
    let provider: String
    let modelIdentifier: String
    let promptVersion: String
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case noteID = "note_id"
        case beforeContent = "before_content"
        case afterContent = "after_content"
        case provider
        case modelIdentifier = "model_identifier"
        case promptVersion = "prompt_version"
        case createdAt = "created_at"
    }
}
