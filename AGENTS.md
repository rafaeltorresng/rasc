# Rasc

Native macOS scratchpad for unfinished thoughts. The core loop is **capture → refine if needed → back to work**. Optimize for speed, trust, simplicity, and low cognitive overhead.

Read `docs/` when deeper product or architectural context is relevant; do not duplicate those documents here.

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
* Prefer Apple frameworks. Add third-party dependencies only when they remove meaningful complexity. Current intended dependencies: GRDB, KeyboardShortcuts, Sparkle.
* Keep architecture simple. Do not introduce speculative abstractions, broad refactors, or infrastructure for hypothetical future requirements.
* Follow existing patterns before creating new ones. Make the smallest maintainable change that solves the task.
* GRDB/SQLite is the source of truth for notes. Migrations must preserve user data; never reset or delete the database as error recovery.
* Store secrets in Keychain. Never put credentials or note content in logs, UserDefaults, analytics, or source control.
* Foundation Models is the preferred local Refine provider when available. Cloud fallback must remain an explicit user choice.
* Keep each Refine isolated from previous notes; never share conversational model context across notes.

## UI

* Keep Rasc native, keyboard-first, low-chrome, and content-first.
* Liquid Glass is progressive enhancement, not decoration; preserve readability and provide appropriate fallback on older macOS versions.
* Do not add UI, settings, or interactions merely because they are easy to implement.
* Respect standard macOS behavior unless a documented product requirement intentionally differs.

## Workflow

* Inspect the relevant code and docs before changing architecture or behavior.
* Keep changes scoped to the requested task; do not opportunistically add features.
* Do not change product invariants, persistence strategy, privacy boundaries, or dependencies without explicit justification.
* Do not commit, push, or modify unrelated files unless requested.

## Validation

* Build and run the relevant tests after changes; report failures instead of hiding them.
* Add or update tests for meaningful domain, persistence, search, or Refine behavior.
* Treat data loss, silent cloud transmission, stale Refine results, and broken autosave as release blockers.
* Window behavior involving Spaces, fullscreen, focus, Stage Manager, or multiple monitors requires manual macOS verification; never claim it was verified if it was not.
