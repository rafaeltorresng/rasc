import Foundation

@main
final class VoiceModelDownloaderMain: NSObject, NSXPCListenerDelegate {
    static func main() {
        let delegate = VoiceModelDownloaderMain()
        let listener = NSXPCListener.service()
        listener.delegate = delegate
        listener.resume()
        RunLoop.current.run()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: VoiceModelDownloaderProtocol.self)
        newConnection.remoteObjectInterface = NSXPCInterface(with: VoiceModelDownloadProgressProtocol.self)
        let service = VoiceModelDownloaderService(connection: newConnection)
        newConnection.exportedObject = service
        newConnection.invalidationHandler = { [weak service] in
            service?.cancelDownload()
        }
        newConnection.resume()
        return true
    }
}

final class VoiceModelDownloaderService: NSObject, VoiceModelDownloaderProtocol, @unchecked Sendable {
    private static let modelRepo = "FluidVoice-Labs/fluid-speech-pro-coreml"
    private let lock = NSLock()
    private weak var connection: NSXPCConnection?
    private var activeTasks: [Int: DownloadState] = [:]
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 1800
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    init(connection: NSXPCConnection) {
        self.connection = connection
        super.init()
    }

    func downloadFile(
        revision: String,
        relativePath: String,
        expectedBytes: Int64,
        reply: @escaping @Sendable (FileHandle?, NSError?) -> Void
    ) {
        guard Self.isValidRevision(revision),
              Self.isValidRelativePath(relativePath),
              expectedBytes > 0,
              let url = Self.remoteURL(revision: revision, relativePath: relativePath) else {
            reply(nil, NSError(
                domain: VoiceModelDownloaderConstants.errorDomain,
                code: VoiceModelDownloaderConstants.invalidRequestCode,
                userInfo: [NSLocalizedDescriptionKey: "Invalid model download request."]
            ))
            return
        }

        do {
            let cacheRoot = try Self.cacheDirectory(revision: revision)
            let finalURL = cacheRoot.appending(path: relativePath)
            let partialURL = URL(fileURLWithPath: finalURL.path + ".partial")
            let fm = FileManager.default
            try fm.createDirectory(at: finalURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            if fm.fileExists(atPath: finalURL.path),
               let attrs = try? fm.attributesOfItem(atPath: finalURL.path),
               let size = attrs[.size] as? Int64,
               size == expectedBytes {
                progressProxy()?.didSetInitialBytes(expectedBytes, forPath: relativePath)
                let handle = try FileHandle(forReadingFrom: finalURL)
                reply(handle, nil)
                return
            }

            var existingBytes: Int64 = 0
            if fm.fileExists(atPath: partialURL.path),
               let attrs = try? fm.attributesOfItem(atPath: partialURL.path),
               let size = attrs[.size] as? Int64 {
                if size == expectedBytes {
                    if fm.fileExists(atPath: finalURL.path) { try? fm.removeItem(at: finalURL) }
                    try fm.moveItem(at: partialURL, to: finalURL)
                    progressProxy()?.didSetInitialBytes(expectedBytes, forPath: relativePath)
                    let handle = try FileHandle(forReadingFrom: finalURL)
                    reply(handle, nil)
                    return
                } else if size > 0 && size < expectedBytes {
                    existingBytes = size
                } else {
                    try? fm.removeItem(at: partialURL)
                }
            }

            if !fm.fileExists(atPath: partialURL.path) {
                fm.createFile(atPath: partialURL.path, contents: nil)
            }

            var request = URLRequest(url: url)
            if existingBytes > 0 {
                request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
            }

            let task = session.dataTask(with: request)
            let state = DownloadState(
                relativePath: relativePath,
                expectedBytes: expectedBytes,
                partialURL: partialURL,
                finalURL: finalURL,
                initialOffset: existingBytes,
                reply: reply
            )
            lock.withLock {
                activeTasks[task.taskIdentifier] = state
            }
            if existingBytes > 0 {
                progressProxy()?.didSetInitialBytes(existingBytes, forPath: relativePath)
            }
            task.resume()
        } catch {
            reply(nil, error as NSError)
        }
    }

    func cancelDownload() {
        let tasks = lock.withLock { Array(activeTasks.keys) }
        session.getTasksWithCompletionHandler { dataTasks, _, _ in
            for task in dataTasks where tasks.contains(task.taskIdentifier) {
                task.cancel()
            }
        }
    }

    func clearCache(revision: String, reply: @escaping @Sendable () -> Void) {
        if Self.isValidRevision(revision), let dir = try? Self.cacheDirectory(revision: revision) {
            try? FileManager.default.removeItem(at: dir)
        }
        reply()
    }

    private func progressProxy() -> VoiceModelDownloadProgressProtocol? {
        connection?.remoteObjectProxy as? VoiceModelDownloadProgressProtocol
    }

    private static func cacheDirectory(revision: String) throws -> URL {
        let base = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appending(path: "VoiceModelDownload", directoryHint: .isDirectory)
            .appending(path: revision, directoryHint: .isDirectory)
    }

    private static func isValidRevision(_ revision: String) -> Bool {
        revision.count == 40 && revision.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    private static func isValidRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func remoteURL(revision: String, relativePath: String) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#")
        guard let encodedPath = relativePath.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return URL(string: "https://huggingface.co/\(modelRepo)/resolve/\(revision)/\(encodedPath)?download=true")
    }
}

extension VoiceModelDownloaderService: URLSessionDataDelegate {
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let state = lock.withLock({ activeTasks[dataTask.taskIdentifier] }) else {
            completionHandler(.cancel)
            return
        }
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        do {
            if http.statusCode == 206 && state.initialOffset > 0 {
                let handle = try FileHandle(forUpdating: state.partialURL)
                try handle.seekToEnd()
                state.writeHandle = handle
                state.receivedBytes = state.initialOffset
                completionHandler(.allow)
            } else if http.statusCode == 200 {
                let handle = try FileHandle(forUpdating: state.partialURL)
                try handle.truncate(atOffset: 0)
                state.writeHandle = handle
                state.receivedBytes = 0
                if state.initialOffset > 0 {
                    progressProxy()?.didSetInitialBytes(0, forPath: state.relativePath)
                }
                completionHandler(.allow)
            } else {
                state.httpError = NSError(
                    domain: VoiceModelDownloaderConstants.errorDomain,
                    code: VoiceModelDownloaderConstants.invalidResponseCode,
                    userInfo: [NSLocalizedDescriptionKey: "Download failed with HTTP \(http.statusCode)."]
                )
                completionHandler(.cancel)
            }
        } catch {
            state.httpError = error as NSError
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let state = lock.withLock({ activeTasks[dataTask.taskIdentifier] }),
              let handle = state.writeHandle else { return }
        do {
            try handle.write(contentsOf: data)
            state.receivedBytes += Int64(data.count)
            progressProxy()?.didReceiveBytes(Int64(data.count), forPath: state.relativePath)
        } catch {
            state.httpError = error as NSError
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let state = lock.withLock({ activeTasks.removeValue(forKey: task.taskIdentifier) }) else { return }
        try? state.writeHandle?.close()
        state.writeHandle = nil

        if let failure = state.httpError ?? (error as NSError?) {
            state.reply(nil, failure)
            return
        }

        do {
            let fm = FileManager.default
            let attrs = try fm.attributesOfItem(atPath: state.partialURL.path)
            let actualBytes = (attrs[.size] as? Int64) ?? -1
            guard actualBytes == state.expectedBytes else {
                try? fm.removeItem(at: state.partialURL)
                state.reply(nil, NSError(
                    domain: VoiceModelDownloaderConstants.errorDomain,
                    code: VoiceModelDownloaderConstants.sizeMismatchCode,
                    userInfo: [NSLocalizedDescriptionKey: "Downloaded file size mismatch."]
                ))
                return
            }
            if fm.fileExists(atPath: state.finalURL.path) {
                try? fm.removeItem(at: state.finalURL)
            }
            try fm.moveItem(at: state.partialURL, to: state.finalURL)
            let readHandle = try FileHandle(forReadingFrom: state.finalURL)
            state.reply(readHandle, nil)
        } catch {
            state.reply(nil, error as NSError)
        }
    }
}

private final class DownloadState: @unchecked Sendable {
    let relativePath: String
    let expectedBytes: Int64
    let partialURL: URL
    let finalURL: URL
    let initialOffset: Int64
    let reply: @Sendable (FileHandle?, NSError?) -> Void
    var writeHandle: FileHandle?
    var receivedBytes: Int64 = 0
    var httpError: NSError?

    init(
        relativePath: String,
        expectedBytes: Int64,
        partialURL: URL,
        finalURL: URL,
        initialOffset: Int64,
        reply: @escaping @Sendable (FileHandle?, NSError?) -> Void
    ) {
        self.relativePath = relativePath
        self.expectedBytes = expectedBytes
        self.partialURL = partialURL
        self.finalURL = finalURL
        self.initialOffset = initialOffset
        self.reply = reply
    }
}
