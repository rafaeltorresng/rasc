import AVFoundation
import Foundation

/// Disposable capture input. The application only creates this with study-owned fixtures.
actor StudyFixture {
    enum Failure: Error { case input, recognition }
    enum Recognition {
        case actual
        case result(String)
        case fail
        case suspended
    }
    nonisolated let usesRealEngine: Bool
    private var owner: UUID?
    private var buffer: MicBuffer?
    private var onRouteChange: (@Sendable () -> Void)?
    private var pending: [CheckedContinuation<String, any Error>] = []
    private var inputFails = false
    private var authorization = AVAuthorizationStatus.authorized
    private var permissionResponse = false
    private var recognition: Recognition
    private var starts = 0
    private var stops = 0
    private(set) var submittedCount = 0

    init(recognition: Recognition = .result("Don’t deploy yet.")) {
        self.recognition = recognition
        if case .actual = recognition { usesRealEngine = true } else { usesRealEngine = false }
    }

    func setRecognition(_ recognition: Recognition) { self.recognition = recognition }
    func setAuthorization(_ value: AVAuthorizationStatus, response: Bool = false) {
        authorization = value
        permissionResponse = response
    }

    func authorizationStatus() -> AVAuthorizationStatus { authorization }

    func requestAuthorization() -> Bool {
        authorization = permissionResponse ? .authorized : .denied
        return permissionResponse
    }

    func setInputFailure(_ enabled: Bool) { inputFails = enabled }

    func start(id: UUID, onRouteChange: @escaping @Sendable () -> Void) throws -> MicBuffer {
        guard !inputFails, owner == nil else { throw Failure.input }
        let buffer = MicBuffer(rate: 16000)
        self.buffer = buffer
        self.onRouteChange = onRouteChange
        owner = id
        starts += 1
        return buffer
    }

    func send(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { buffer?.append($0) }
    }

    func disconnect() { onRouteChange?() }

    func stop(id: UUID) {
        guard owner == id else { return }
        self.buffer = nil
        onRouteChange = nil
        owner = nil
        stops += 1
    }

    func activity() -> (starts: Int, stops: Int, active: Bool, pending: Int) {
        (starts, stops, owner != nil, pending.count)
    }

    func recognize(_ samples: [Float]) async throws -> String {
        submittedCount = samples.count
        switch recognition {
        case .actual:
            throw Failure.recognition
        case .result(let text):
            return text
        case .fail:
            throw Failure.recognition
        case .suspended:
            // Deliberately ignore task cancellation. Exercise late non-cooperative engines.
            return try await withCheckedThrowingContinuation { pending.append($0) }
        }
    }

    func deliverLate(_ text: String) {
        if !pending.isEmpty { pending.removeFirst().resume(returning: text) }
    }
}
