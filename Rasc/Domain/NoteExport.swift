import Foundation

enum NoteExportScope: Equatable, Sendable {
    case selected(Set<UUID>)
    case kept
    case all
}

struct NoteExportSnapshot: Sendable {
    let note: Note
    let documentRevision: Int64?
}

enum NoteExportError: Error, Equatable {
    case empty
    case thoughtChanged
    case saveFailed
    case destinationConflict
    case invalidOutput
}
