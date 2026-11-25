import CoreML
import CryptoKit
import FluidAudio
import Foundation
import OSLog

enum VoiceModelAssets {
    static let revision = "3b9d38a93d606f84011e5a0a669b7ea146375a22"

    struct File: Decodable {
        let bytes: Int
        let sha256: String
    }

    enum Issue: Error {
        case missing, invalid
    }

    private static func manifest() throws -> [String: File] {
        guard let url = Bundle.main.url(forResource: "VoiceModelManifest", withExtension: "json") else {
            throw Issue.missing
        }
        return try JSONDecoder().decode([String: File].self, from: Data(contentsOf: url))
    }

    static func packagedFolder() -> URL? {
        Bundle.main.url(forResource: "VoiceModel", withExtension: nil)
    }

    static func totalManifestBytes() -> Int64 {
        guard let expected = try? manifest() else { return 652_304_885 }
        return expected.values.reduce(0) { $0 + Int64($1.bytes) }
    }

    static func hasInstalledFolder() -> Bool {
        guard let expected = try? manifest(),
              let installed = try? storage().appending(path: revision) else { return false }
        return isComplete(installed, expected: expected)
    }

    private static func storage() throws -> URL {
        try NoteRepository.defaultDatabaseURL.deletingLastPathComponent().appending(path: "VoiceModels")
    }

    static func availableFolder() throws -> URL {
        let expected = try manifest()
        if let installed = try? storage().appending(path: revision), isComplete(installed, expected: expected) {
            return installed
        }
        if let packaged = packagedFolder(), isComplete(packaged, expected: expected) {
            return packaged
        }
        throw Issue.missing
    }

    private static func isComplete(_ folder: URL, expected: [String: File]) -> Bool {
        expected.allSatisfy { path, file in
            (try? regularFile(in: folder, at: path, size: file.bytes)) != nil
        }
    }

    private static func regularFile(in folder: URL, at path: String, size: Int) throws -> URL {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        let parts = path.split(separator: "/")
        var url = folder
        for part in parts.dropLast() {
            url = url.appending(path: String(part))
            let values = try url.resourceValues(forKeys: keys)
            guard values.isDirectory == true, values.isSymbolicLink == false else { throw Issue.invalid }
        }
        guard let name = parts.last else { throw Issue.invalid }
        url = url.appending(path: String(name))
        let values = try url.resourceValues(forKeys: keys)
        guard values.isRegularFile == true, values.isSymbolicLink == false, values.fileSize == size else {
            throw Issue.invalid
        }
        return url
    }

    // Only copy pinned files. Core ML sees the stable versioned URL after an atomic rename.
    static func install(from source: URL) throws {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        let expected = try manifest()
        let fm = FileManager.default
        let storage = try storage()
        try fm.createDirectory(at: storage, withIntermediateDirectories: true)
        for url in try fm.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil)
            where url.lastPathComponent.hasPrefix(".incoming-") {
            try? fm.removeItem(at: url)
        }
        let staging = storage.appending(path: ".incoming-\(UUID())")
        let installed = storage.appending(path: revision)
        defer { try? fm.removeItem(at: staging) }

        for (path, file) in expected.sorted(by: { $0.key < $1.key }) {
            try Task.checkCancellation()
            let original = try regularFile(in: source, at: path, size: file.bytes)
            let destination = staging.appending(path: path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: original, to: destination)
            _ = try regularFile(in: staging, at: path, size: file.bytes)
            let stream = try FileHandle(forReadingFrom: destination)
            defer { try? stream.close() }
            var hash = SHA256()
            while let block = try stream.read(upToCount: 1 << 20), !block.isEmpty {
                try Task.checkCancellation()
                hash.update(data: block)
            }
            let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
            guard digest == file.sha256 else { throw Issue.invalid }
        }
        try Task.checkCancellation()
        if fm.fileExists(atPath: installed.path) {
            _ = try fm.replaceItemAt(installed, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: installed)
        }
        pruneOtherRevisions(in: storage, keeping: revision)
    }

    static func removeInstalled() throws {
        let fm = FileManager.default
        let storage = try storage()
        if fm.fileExists(atPath: storage.path) {
            try fm.removeItem(at: storage)
        }
        clearDownloaderCache()
    }

    static func installFromDownloader(
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        let expected = try manifest()
        let totalBytes = expected.values.reduce(0) { $0 + Int64($1.bytes) }
        let fm = FileManager.default
        let storage = try storage()
        try fm.createDirectory(at: storage, withIntermediateDirectories: true)

        let capacity = (try? storage.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage)
            ?? (try? storage.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity).map(Int64.init)
        if let capacity, capacity < totalBytes * 2 + 200_000_000 {
            throw VoiceModel.PreparationError.lowDiskSpace
        }

        for url in try fm.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil)
            where url.lastPathComponent.hasPrefix(".incoming-") {
            try? fm.removeItem(at: url)
        }
        let staging = storage.appending(path: ".incoming-\(UUID())")
        let installed = storage.appending(path: revision)
        defer { try? fm.removeItem(at: staging) }

        let receiver = VoiceModelDownloadProgressReceiver(totalBytes: totalBytes, onProgress: progress)
        let box = DownloaderConnectionBox(serviceName: VoiceModelDownloaderConstants.serviceName, receiver: receiver)
        defer { box.connection.invalidate() }

        let entries = expected.sorted { $0.key < $1.key }
        try await withTaskCancellationHandler {
            for (path, file) in entries {
                try Task.checkCancellation()
                let handle: FileHandle = try await withCheckedThrowingContinuation { continuation in
                    let proxy = box.connection.remoteObjectProxyWithErrorHandler { error in
                        continuation.resume(throwing: error)
                    } as? VoiceModelDownloaderProtocol
                    guard let proxy else {
                        continuation.resume(throwing: Issue.missing)
                        return
                    }
                    proxy.downloadFile(revision: revision, relativePath: path, expectedBytes: Int64(file.bytes)) { fileHandle, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let fileHandle {
                            continuation.resume(returning: fileHandle)
                        } else {
                            continuation.resume(throwing: Issue.invalid)
                        }
                    }
                }
                defer { try? handle.close() }
                try Task.checkCancellation()

                let destination = staging.appending(path: path)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                fm.createFile(atPath: destination.path, contents: nil)
                let output = try FileHandle(forWritingTo: destination)
                defer { try? output.close() }

                var hash = SHA256()
                var writtenBytes = 0
                while let block = try handle.read(upToCount: 1 << 20), !block.isEmpty {
                    try Task.checkCancellation()
                    try output.write(contentsOf: block)
                    hash.update(data: block)
                    writtenBytes += block.count
                }
                guard writtenBytes == file.bytes else { throw Issue.invalid }
                let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
                guard digest == file.sha256 else { throw Issue.invalid }
            }

            try Task.checkCancellation()
            if fm.fileExists(atPath: installed.path) {
                _ = try fm.replaceItemAt(installed, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: installed)
            }
            pruneOtherRevisions(in: storage, keeping: revision)
        } onCancel: {
            (box.connection.remoteObjectProxy as? VoiceModelDownloaderProtocol)?.cancelDownload()
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let proxy = box.connection.remoteObjectProxyWithErrorHandler { _ in
                continuation.resume()
            } as? VoiceModelDownloaderProtocol
            guard let proxy else {
                continuation.resume()
                return
            }
            proxy.clearCache(revision: revision) {
                continuation.resume()
            }
        }
    }

    private static func clearDownloaderCache() {
        let box = DownloaderConnectionBox(serviceName: VoiceModelDownloaderConstants.serviceName, receiver: nil)
        let proxy = box.connection.remoteObjectProxyWithErrorHandler { _ in
            box.connection.invalidate()
        } as? VoiceModelDownloaderProtocol
        proxy?.clearCache(revision: revision) {
            box.connection.invalidate()
        }
    }

    private static func pruneOtherRevisions(in storage: URL, keeping current: String) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil) else { return }
        for item in items where item.lastPathComponent != current && !item.lastPathComponent.hasPrefix(".") {
            try? fm.removeItem(at: item)
        }
    }
}

private final class DownloaderConnectionBox: @unchecked Sendable {
    let connection: NSXPCConnection

    init(serviceName: String, receiver: VoiceModelDownloadProgressReceiver?) {
        let connection = NSXPCConnection(serviceName: serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: VoiceModelDownloaderProtocol.self)
        if let receiver {
            connection.exportedInterface = NSXPCInterface(with: VoiceModelDownloadProgressProtocol.self)
            connection.exportedObject = receiver
        }
        connection.resume()
        self.connection = connection
    }
}

private final class VoiceModelDownloadProgressReceiver: NSObject, VoiceModelDownloadProgressProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let totalBytes: Int64
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private var bytesByPath: [String: Int64] = [:]
    private var lastReportedBytes: Int64 = -1

    init(totalBytes: Int64, onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.totalBytes = totalBytes
        self.onProgress = onProgress
    }

    func didSetInitialBytes(_ bytes: Int64, forPath relativePath: String) {
        let report: Int64? = lock.withLock {
            bytesByPath[relativePath] = bytes
            let sum = min(bytesByPath.values.reduce(0, +), totalBytes)
            lastReportedBytes = sum
            return sum
        }
        if let report { onProgress(report, totalBytes) }
    }

    func didReceiveBytes(_ delta: Int64, forPath relativePath: String) {
        let report: Int64? = lock.withLock {
            bytesByPath[relativePath, default: 0] += delta
            let sum = min(bytesByPath.values.reduce(0, +), totalBytes)
            guard sum >= totalBytes || sum - lastReportedBytes >= 262_144 else { return nil }
            lastReportedBytes = sum
            return sum
        }
        if let report { onProgress(report, totalBytes) }
    }
}

actor VoiceModel {
    private static let logger = Logger(subsystem: "app.rasc", category: "VoiceModel")
    enum PreparationError: Error {
        case unavailable, lowDiskSpace
    }

    private let retention: Duration?
    private var models: AsrModels?
    private var loading: (id: UUID, task: Task<AsrModels, Error>)?
    private var prediction: (id: UUID, task: Task<String, Error>)?
    private var expiry: Task<Void, Never>?
    private var expiryID: UUID?
    private var releaseAfterPrediction = false

    init(retention: Duration? = nil) {
        self.retention = retention
    }

    func prepare() async throws {
        _ = try await preparedModel()
    }

    private func preparedModel() async throws -> AsrModels {
        try Task.checkCancellation()
        if let models {
            renewLease()
            return models
        }
        while let previous = loading, previous.task.isCancelled {
            _ = await previous.task.result
            if loading?.id == previous.id { loading = nil }
            try Task.checkCancellation()
            if let models {
                renewLease()
                return models
            }
        }
        let job: (id: UUID, task: Task<AsrModels, Error>)
        if let loading {
            job = loading
        } else {
            job = (UUID(), Task { try await Self.loadModels() })
            loading = job
        }
        do {
            let loaded = try await job.task.value
            guard !job.task.isCancelled else { throw CancellationError() }
            if loading?.id == job.id {
                loading = nil
                models = loaded
                renewLease()
            }
            try Task.checkCancellation()
            guard let models else { throw CancellationError() }
            return models
        } catch {
            if loading?.id == job.id { loading = nil }
            throw error
        }
    }

    private static func loadModels() async throws -> AsrModels {
        guard let url = try? VoiceModelAssets.availableFolder() else { throw PreparationError.unavailable }
        let start = ContinuousClock.now
        for attempt in 1...2 {
            do {
                let models = try await AsrModels.loadLocalOnly(from: url, version: .fluidParakeetPro)
                logger.debug("Core ML model load: \(milliseconds(since: start), privacy: .public) ms")
                return models
            } catch {
                try Task.checkCancellation()
                let failure = error as NSError
                logger.error("Local model load attempt \(attempt, privacy: .public) failed: \(failure.domain, privacy: .public) (\(failure.code, privacy: .public))")
                if let capacity = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity,
                   capacity < 1_000_000_000 {
                    throw PreparationError.lowDiskSpace
                }
                guard attempt == 1, failure.domain == MLModelErrorDomain else { throw PreparationError.unavailable }
                try await Task.sleep(for: .milliseconds(200))
            }
        }
        throw PreparationError.unavailable
    }

    func transcribe(_ audio: VoiceAudio, modelReady: @escaping @Sendable () async -> Void) async throws -> String {
        // A canceled Core ML prediction may still be executing. Drain it before another starts.
        while let previous = prediction {
            _ = await previous.task.result
            finishPrediction(previous.id)
            try Task.checkCancellation()
        }
        try Task.checkCancellation()
        let id = UUID()
        let task = Task {
            let models = try await preparedModel()
            try Task.checkCancellation()
            await modelReady()
            var samples = try audio.mono16k()
            if samples.count < 16_000 {
                samples.append(contentsOf: repeatElement(0, count: 16_000 - samples.count))
            }
            try Task.checkCancellation()
            let manager = AsrManager()
            let start = ContinuousClock.now
            do {
                try await manager.initialize(models: models)
                let result = try await manager.transcribe(samples, source: .microphone)
                try Task.checkCancellation()
                await manager.cleanup()
                Self.logger.debug("Local transcription: \(Self.milliseconds(since: start), privacy: .public) ms")
                return result.text
            } catch {
                await manager.cleanup()
                throw error
            }
        }
        prediction = (id, task)
        defer { finishPrediction(id) }
        return try await withTaskCancellationHandler {
            let text = try await task.value
            try Task.checkCancellation()
            return text
        } onCancel: {
            task.cancel()
        }
    }

    private func finishPrediction(_ id: UUID) {
        guard prediction?.id == id else { return }
        prediction = nil
        if releaseAfterPrediction {
            releaseAfterPrediction = false
            release()
        } else if models != nil {
            renewLease()
        }
    }

    private func renewLease() {
        expiry?.cancel()
        guard let retention else {
            expiry = nil
            expiryID = nil
            return
        }
        let id = UUID()
        expiryID = id
        expiry = Task { [weak self, retention] in
            do { try await Task.sleep(for: retention) } catch { return }
            await self?.expire(id)
        }
    }

    private func expire(_ id: UUID) {
        guard expiryID == id, prediction == nil else { return }
        release()
    }

    func release() {
        loading?.task.cancel()
        models = nil
        expiry?.cancel()
        expiry = nil
        expiryID = nil
    }

    func releaseForMemoryPressure() {
        if prediction != nil { releaseAfterPrediction = true }
        else { release() }
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        Int((start.duration(to: .now) / .milliseconds(1)).rounded())
    }
}
