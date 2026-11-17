# Rasc

Native macOS scratchpad for unfinished thoughts. The core loop is **capture → refine if needed → back to work**. Optimize for speed, trust, simplicity, and low cognitive overhead.

Start with [current product](docs/CURRENT-PRODUCT.md), [design system](docs/DESIGN-SYSTEM.md), [brand](docs/BRAND.md), [data and privacy](docs/DATA-AND-PRIVACY.md), [native validation](docs/NATIVE-UI-VALIDATION.md), and the [release runbook](docs/RELEASE.md). Historical [product thesis](docs/Product.md), [architecture](docs/ARCHITECTURE.MD), [Refine design](docs/REFINE-V2.md) and [reliability evidence](docs/REFINE-RELIABILITY.md) are indexed in [docs](docs/README.md).

## Product invariants

* Capture must feel instant and remain useful without AI.
* Notes are local-first and must never depend on a backend to open, edit, search, or persist.
* Never silently send note content off-device. External AI requires explicit user opt-in.
* Refine is explicit, stateless, conservative, and reversible. Preserve meaning, uncertainty, names, numbers, dates, and technical identifiers.
* Never destroy the original note before the user accepts a refinement.
* Do not add folders, tags, agents, chat, sync, semantic search, task management, collaboration, or other product scope unless explicitly requested.
* Prefer removing choices over adding configuration.

## Engineering

* Use Swift 6 and modern Swift concurrency. Prefer `async/await`; never block the main thread with I/O or model work.
* Use SwiftUI for presentation and AppKit where native macOS behavior requires it, especially `NSPanel`, focus, Spaces, fullscreen, and menu-bar integration.
* Prefer Apple frameworks. Add third-party dependencies only when they remove meaningful complexity; do not add one without justification. Current dependencies: GRDB, KeyboardShortcuts, Sparkle (vendored), and ThinkingOrbsKit (vendored).
* Keep architecture simple. Do not introduce speculative abstractions, broad refactors, or infrastructure for hypothetical future requirements.
* Follow existing patterns before creating new ones. Make the smallest maintainable change that solves the task.
* GRDB/SQLite is the source of truth for notes. Migrations must preserve user data; never reset or delete the database as error recovery.
* Store secrets in Keychain. Never put credentials or note content in logs, UserDefaults, analytics, or source control.
* Refine uses Apple Foundation Models on-device when available. There is no current cloud fallback; any external AI requires explicit user opt-in. Capture, Keep, and retrieval must not depend on Refine.
* Keep each Refine isolated from previous notes; never share conversational model context across notes.

## UI

* Keep Rasc native, keyboard-first, low-chrome, and content-first.
* Follow the design system: keep the writing surface solid, use neutral focus and selection, and reserve copper for Keep and Kept. Materials such as Liquid Glass on macOS 26 are progressive enhancement; preserve readability and fall back on older macOS.
* Do not add UI, settings, or interactions merely because they are easy to implement.
* Respect standard macOS behavior unless a documented product requirement intentionally differs.

## Workflow

* Inspect the relevant code and docs before changing architecture or behavior.
* Keep changes scoped to the requested task; do not opportunistically add features or rewrite unrelated code.
* Do not change product invariants, persistence strategy, privacy boundaries, or dependencies without explicit justification.
* Do not commit, push, or modify unrelated files unless requested.

## Validation

* Build and run the relevant tests with the shared Rasc scheme; commands are in [README](README.md). Report failures instead of hiding them.
* Add or update tests for meaningful domain, persistence, search, or Refine behavior.
* Treat data loss, silent off-device transmission, stale Refine results, and broken autosave as release blockers.
* Window behavior involving focus, Spaces, fullscreen, Stage Manager, or multiple monitors requires manual macOS verification; never claim it was verified if it was not.
