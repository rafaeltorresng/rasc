import Foundation

@objc protocol VoiceModelDownloadProgressProtocol {
    func didSetInitialBytes(_ bytes: Int64, forPath relativePath: String)
    func didReceiveBytes(_ delta: Int64, forPath relativePath: String)
}

@objc protocol VoiceModelDownloaderProtocol {
    func downloadFile(
        revision: String,
        relativePath: String,
        expectedBytes: Int64,
        reply: @escaping @Sendable (FileHandle?, NSError?) -> Void
    )
    func cancelDownload()
    func clearCache(revision: String, reply: @escaping @Sendable () -> Void)
}

enum VoiceModelDownloaderConstants {
    static let serviceName = "com.rafaeltorres.rasc.VoiceModelDownloader"
    static let errorDomain = "app.rasc.VoiceModelDownloader"
    static let invalidRequestCode = 1
    static let invalidResponseCode = 2
    static let sizeMismatchCode = 3
}
