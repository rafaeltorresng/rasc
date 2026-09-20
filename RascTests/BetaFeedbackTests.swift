import Foundation
import Testing
@testable import Rasc

struct BetaFeedbackTests {
    @Test
    func mailtoURLIncludesSubjectAndDiagnosticsWithoutPersonalContent() throws {
        let url = try #require(
            BetaFeedback.mailtoURL(
                recipientEmail: "beta@example.com",
                appVersion: "0.1.0-beta.1",
                buildNumber: "2",
                macOSVersion: "15.0.0",
                architecture: "arm64"
            )
        )

        #expect(url.scheme == "mailto")
        #expect(url.path == "beta@example.com")

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(query["subject"] == "Rasc beta feedback")

        let body = try #require(query["body"])
        #expect(body.contains("Rasc version: 0.1.0-beta.1 (2)"))
        #expect(body.contains("macOS version: 15.0.0"))
        #expect(body.contains("Mac architecture: arm64"))
        #expect(!body.localizedCaseInsensitiveContains("note"))
        #expect(!body.localizedCaseInsensitiveContains("sqlite"))
        #expect(!body.localizedCaseInsensitiveContains("uuid"))
    }

    @Test
    func mailtoURLWorksWithoutRecipientWhenNotConfigured() throws {
        let url = try #require(
            BetaFeedback.mailtoURL(
                recipientEmail: "",
                appVersion: "0.1.0-beta.1",
                buildNumber: "2",
                macOSVersion: "15.0.0",
                architecture: "arm64"
            )
        )

        #expect(url.scheme == "mailto")
        #expect(url.path.isEmpty)

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let subject = components.queryItems?.first(where: { $0.name == "subject" })?.value
        #expect(subject == "Rasc beta feedback")
    }
}
