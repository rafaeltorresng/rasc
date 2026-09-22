import Foundation

enum RefineLanguagePolicy: Equatable, Sendable {
    case matchNote
    case fixed(Locale)

    static let productionDefault: RefineLanguagePolicy = .matchNote

    init(corpusPolicy: RefineCorpusLanguagePolicy) {
        switch corpusPolicy.mode {
        case .matchNote:
            self = .matchNote
        case .fixedLocale:
            let identifier = corpusPolicy.locale ?? corpusPolicy.preferredLocale ?? "en-US"
            self = .fixed(Locale(identifier: identifier))
        }
    }
}
