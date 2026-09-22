#if DEBUG
import Foundation

/// Deprecated alias retained for M12B-007A benchmark wiring. Production resolver v2 lives in `RefineLanguageResolver`.
enum RefineEvalLanguageResolverCandidate {
    static func resolve(request: RefinementRequest) -> ResolvedRefineLanguage {
        RefineLanguageResolver.resolve(request: request)
    }

    static func resolve(
        policy: RefineLanguagePolicy,
        inputText: String,
        surroundingText: String?
    ) -> ResolvedRefineLanguage {
        RefineLanguageResolver.resolve(
            policy: policy,
            inputText: inputText,
            surroundingText: surroundingText
        )
    }
}
#endif
