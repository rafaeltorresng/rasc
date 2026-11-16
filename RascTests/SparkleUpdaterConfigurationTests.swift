import Foundation
import Testing
@testable import Rasc

struct SparkleUpdaterConfigurationTests {
    private let validKey = Data(repeating: 7, count: 32).base64EncodedString()

    @Test
    func acceptsHTTPSFeedAndEd25519Key() throws {
        let configuration = try #require(
            SparkleUpdaterConfiguration.validate(
                feedURLString: "https://rasc.app/appcast.xml",
                publicKey: validKey
            )
        )

        #expect(configuration.feedURL.absoluteString == "https://rasc.app/appcast.xml")
        #expect(configuration.publicKey == validKey)
    }

    @Test
    func rejectsPlaceholderKey() {
        #expect(
            SparkleUpdaterConfiguration.validate(
                feedURLString: "https://rasc.app/appcast.xml",
                publicKey: SparkleUpdaterConfiguration.placeholderPublicKey
            ) == nil
        )
    }

    @Test
    func rejectsInsecureFeed() {
        #expect(
            SparkleUpdaterConfiguration.validate(
                feedURLString: "http://rasc.app/appcast.xml",
                publicKey: validKey
            ) == nil
        )
    }

    @Test
    func rejectsMissingConfiguration() {
        #expect(SparkleUpdaterConfiguration.validate(feedURLString: nil, publicKey: validKey) == nil)
        #expect(
            SparkleUpdaterConfiguration.validate(
                feedURLString: "https://rasc.app/appcast.xml",
                publicKey: nil
            ) == nil
        )
    }

    @Test
    func rejectsMalformedPublicKey() {
        #expect(
            SparkleUpdaterConfiguration.validate(
                feedURLString: "https://rasc.app/appcast.xml",
                publicKey: "not-a-valid-ed25519-key"
            ) == nil
        )

        let shortKey = Data(repeating: 7, count: 31).base64EncodedString()
        #expect(
            SparkleUpdaterConfiguration.validate(
                feedURLString: "https://rasc.app/appcast.xml",
                publicKey: shortKey
            ) == nil
        )
    }

    @Test
    func rejectsMalformedFeedURL() {
        #expect(
            SparkleUpdaterConfiguration.validate(
                feedURLString: "not a url",
                publicKey: validKey
            ) == nil
        )

        #expect(
            SparkleUpdaterConfiguration.validate(
                feedURLString: "https://",
                publicKey: validKey
            ) == nil
        )

        #expect(
            SparkleUpdaterConfiguration.validate(
                feedURLString: "https:appcast.xml",
                publicKey: validKey
            ) == nil
        )
    }
}
