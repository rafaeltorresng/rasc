import AppKit
import Foundation

enum BetaFeedback {
    /// Set this address before distributing the private beta.
    static let recipientEmail = "rafaeltorresng@gmail.com"

    static let subject = "Rasc beta feedback"

    static func open() {
        guard let url = mailtoURL() else { return }
        NSWorkspace.shared.open(url)
    }

    static func mailtoURL(
        recipientEmail: String = BetaFeedback.recipientEmail,
        appVersion: String? = AppVersion.marketingVersion,
        buildNumber: String? = AppVersion.buildNumber,
        macOSVersion: String? = AppVersion.macOSVersion,
        architecture: String? = AppVersion.architecture
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        if !recipientEmail.isEmpty {
            components.path = recipientEmail
        }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "subject", value: subject),
        ]

        var bodyLines = [
            "",
            "---",
            "Please describe what happened above this line.",
            "",
        ]

        if let appVersion, let buildNumber {
            bodyLines.append("Rasc version: \(appVersion) (\(buildNumber))")
        } else if let appVersion {
            bodyLines.append("Rasc version: \(appVersion)")
        }

        if let macOSVersion {
            bodyLines.append("macOS version: \(macOSVersion)")
        }

        if let architecture {
            bodyLines.append("Mac architecture: \(architecture)")
        }

        queryItems.append(URLQueryItem(name: "body", value: bodyLines.joined(separator: "\n")))
        components.queryItems = queryItems
        return components.url
    }
}

enum AppVersion {
    static var marketingVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    static var buildNumber: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    static var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    static var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}
