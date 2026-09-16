import Foundation
import OSLog

/// Privacy-safe runtime diagnostics. Never logs note content.
enum AppDiagnostics {
    private static let lifecycle = Logger(subsystem: "com.rasc.app", category: "lifecycle")
    private static let window = Logger(subsystem: "com.rasc.app", category: "window")
    private static let search = Logger(subsystem: "com.rasc.app", category: "search")

    static func bootstrapStarted() {
        lifecycle.debug("bootstrap_started")
    }

    static func bootstrapReady(durationMs: Int) {
        lifecycle.debug("bootstrap_ready duration_ms=\(durationMs, privacy: .public)")
    }

    static func bootstrapFailed() {
        lifecycle.error("bootstrap_failed")
    }

    static func panelPresentStarted(surface: String) {
        window.debug("panel_present_started surface=\(surface, privacy: .public)")
    }

    static func panelPresentCompleted(surface: String, durationMs: Int) {
        window.debug(
            "panel_present_completed surface=\(surface, privacy: .public) duration_ms=\(durationMs, privacy: .public)"
        )
    }

    static func panelRestoreFailed() {
        window.error("panel_restore_failed")
    }

    static func panelRepositioned(reason: String) {
        window.debug("panel_repositioned reason=\(reason, privacy: .public)")
    }

    static func searchCompleted(queryLength: Int, resultCount: Int, durationMs: Int) {
        search.debug(
            "search_completed query_length=\(queryLength, privacy: .public) result_count=\(resultCount, privacy: .public) duration_ms=\(durationMs, privacy: .public)"
        )
    }
}
