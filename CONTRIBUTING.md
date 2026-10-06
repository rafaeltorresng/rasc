# Contributing to Rasc

Rasc is a native scratchpad for unfinished thoughts. Preserve the small core loop:
Invoke → Capture → optional Refine → Keep → return to work.

Discuss scope-changing proposals before implementing them. Do not introduce
folders, tags, chat, agents, sync, backend dependencies or silent cloud inference.
Prefer Apple frameworks and existing patterns over additional dependencies.

## Development

Use Xcode 26.2+, the shared Rasc scheme, and Swift 6. Follow the build/test commands
in [README](README.md), engineering invariants in [AGENTS](AGENTS.md), and the
[current implementation guide](docs/CURRENT-PRODUCT.md).

For a pull request, describe the concrete problem, resulting behavior and relevant
validation. Include before/after screenshots for visual changes, using synthetic
thoughts. Report the macOS version, appearance and window size; disclose anything
not verified. Persistence, search, lifecycle and Refine changes need meaningful
regression tests. Changes involving focus or windows need native verification.

Keep SwiftUI presentation separate from sessions and persistence. Keep the existing
brand symbol distinct from the Thinking Orb. [Brand exports](docs/BRAND.md) must
remain reproducible from the existing master.

## User data and errors

SQLite/GRDB is the source of truth. Never reset the database as error recovery.
Preserve the original until a refinement is explicitly accepted. Never record
thought text, credentials or clipboard contents in diagnostics or fixtures.

Use synthetic fixtures in tests and screenshots. Historical evaluation material is
not evidence of current model performance; see [evaluation provenance](Evals/README.md).
Report sensitive problems privately through [SECURITY](SECURITY.md).

## Review

Keep changes focused and explain platform tradeoffs. Be respectful and follow the
[community conduct](CODE_OF_CONDUCT.md). No CLA is required; contributions use the
repository's MIT license.
