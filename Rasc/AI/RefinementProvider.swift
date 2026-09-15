protocol RefinementProvider: Sendable {
    var metadata: RefinementMetadata { get }

    func availability(for request: RefinementRequest) async -> RefinementAvailability
    func refine(_ request: RefinementRequest) async throws -> RefinementResult
}
