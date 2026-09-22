# App reliability (M13A)

App-wide reliability audit for Rasc before RC. Scope: full product lifecycle, not Refine eval corpora alone.

**Audit date:** 2026-09-22  
**Release gate:** see `Evals/AppReliability/M13A/report.md`

## Personalization baseline (post M12C closeout)

| Feature | Status |
|---|---|
| M12C-001 Refine Language | Accepted, production |
| M12C-002 Global Refine Preference | **Rejected, reverted** — see `Evals/Refine/experiments/M12C-002-global-refine-preference/REJECTED.md` |
| M12C-003 one-off instructions | Not started |

Production Refine prompt: `refine-v2-language-preference`.

## Critical user journeys

### A. Launch → scratchpad → type → autosave → hide → reopen

| Step | Implementation |
|---|---|
| Launch | `RascApp` → `AppDelegate.applicationDidFinishLaunching` → `AppBootstrap.start()` |
| Global shortcut | `KeyboardShortcuts.Name.toggleScratchpad` → `PanelController.toggle()` |
| Editor focus | `ScratchpadSession.requestEditorFocus()` / `focusRequest` |
| Autosave | `ScratchpadSession.scheduleAutosave()` — 200ms debounce → `persist()` |
| Hide | `PanelController.hide()` → `session.flush()` → `panel.orderOut` |
| Reopen | `PanelController.show()` → `session.restore()` via `ActiveNoteStore` |

### B. New note → switch → return

| Step | Implementation |
|---|---|
| New scratch | `ScratchpadSession.startNewScratch()` — flushes current, clears `noteID` |
| Switch note | `ScratchpadSession.openNote(id:)` — flush before load |
| Active note | `ActiveNoteStore` in UserDefaults (`activeNoteID`) |

### C. Refine → accept → undo

| Step | Implementation |
|---|---|
| Invoke | ⌘J → `ScratchpadSession.startRefinement()` |
| Preflight | `RefinementPreflightPolicy` + provider availability |
| Preview | `FoundationModelsRefinementProvider` + literal/language validators |
| Accept | `ScratchpadSession.acceptRefinement()` → `NoteRepository.acceptRefinement` |
| Undo | `UndoManager` registration on accept |

### D. Refine noChange / failure

Original note preserved until explicit accept. Cancel/escape/stale paths call `cancelRefinement()` without mutating stored note.

### E. Search (⌘P palette / scratchpad search)

`CommandPaletteView` / `HistorySearchView` → `ScratchpadSession.scheduleSearch()` → `NoteRepository.search()` (FTS5).

### F. Home → open note → edit

`AppBootstrap.openHome()` → `HomeSession` → `PanelController.openNote(id:)`.

### G. App restart

`ActiveNoteStore` + GRDB persistence. Window frames via `WindowFrameStore`.

### H. Settings

`SettingsView` — shortcut (`KeyboardShortcuts`), Launch at Login (`LoginItemController`), Refine Language (`RefineLanguageSettingsStore`). **No Refine preferences** (M12C-002 rejected).

### I. Foundation Models unavailable

`RefinementProvider.availability` → `RefinementMessage.unavailable`. Capture/search/history continue.

### J. Onboarding / migration

`OnboardingCoordinator` + `OnboardingEligibility`. Existing-user migration in `GlobalShortcutMigration`, onboarding store, GRDB v1→v4.

## Automated invariants (must hold)

1. **No note loss** — flush before hide/switch/quit; terminate-later on quit failure
2. **No wrong-note mutation** — `noteID` + revision guards on refine accept
3. **No stale refine overwrite** — `contentRevision` + `requestID` checks
4. **No content-driven panel resize** — `NSHostingSizingOptions.minSize`
5. **No autosave loss on lifecycle boundaries** — explicit flush wins over debounce
6. **No broken FTS** — FTS5 sync on write path; migration v3 backfill tested
7. **No settings state loss** — language/shortcut/frames in UserDefaults

## Test matrix (v1)

See `Evals/AppReliability/M13A/issue-register.md` for findings.

| Area | Automated | Manual (RC) |
|---|---|---|
| Lifecycle / quit flush | `AppReliabilityLifecycleTests` | Force quit, sleep/wake |
| Autosave / switch | `ScratchpadSessionTests` | Quick hide after burst typing |
| Refine stale/cancel | `RefinementSessionTests` | FM unavailable UX |
| Migrations v1→v4 | `NoteRepositoryTests` | Upgrade from old beta DB |
| FTS | `NoteRepositoryTests` | Large collection feel |
| Scale 10/100/1000 | `AppReliabilityScaleTests` | Home with many notes |
| Window frames | `WindowFrameStoreTests`, `PanelControllerTests` | Multi-monitor, Spaces |
| Settings language | `RefineLanguagePreferenceTests` | Unsupported locale fallback |
| Privacy | `BetaFeedbackTests`, bundle scan test | Feedback mail content |
| Release bundle | lifecycle bundle test + `Scripts/release/verify-private-beta.sh` | Signed DMG audit |

## GRDB migrations

| ID | Purpose |
|---|---|
| `v1_create_notes` | Initial notes table (immutable M0) |
| `v2_m1_notes_schema` | Soft delete, snake_case columns |
| `v3_m2_create_notes_fts` | FTS5 virtual table + sync |
| `v4_m3a_create_refinement_revisions` | Refine revision audit trail |

All covered by `NoteRepositoryTests` migration tests.

## Release / privacy notes

- **LSUIElement** menu-bar app; no Dock icon
- **App Sandbox** enabled in Release entitlements
- **Hardened Runtime** enabled
- Eval corpora **not** bundled (verified in tests)
- Notes local-only; feedback mail includes version/OS/architecture only
- DEBUG eval CLI (`--run-refine-evals`) not reachable in Release builds

## Related docs

- `docs/RC-MANUAL-TEST.md` — 15–20 minute maintainer checklist
- `Evals/AppReliability/M13A/report.md` — audit decision and metrics
