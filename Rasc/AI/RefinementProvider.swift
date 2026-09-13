protocol RefinementProvider: Sendable {
    var identifier: String { get }

    func refine(_ request: RefinementRequest) async throws -> RefinementResult
}
