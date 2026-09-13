# M1 Capture Core Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Rasc's scratchpad durable with local SQLite persistence, reliable autosave, and exact active-note restoration while preserving all M0 window behavior.

**Architecture:** GRDB owns a single local SQLite `DatabaseQueue` behind an actor repository. A main-actor scratchpad session owns only editor/lifecycle state, keeps empty drafts in memory, serializes debounced saves, and stores the active note UUID in `UserDefaults`, never note content.

**Tech Stack:** Swift 6, SwiftUI, AppKit, GRDB 7.11.1, Swift Testing, XCTest/xcodebuild.

---

### Task 1: Specify persistence and migration behavior

**Files:**
- Modify: `RascTests/NoteRepositoryTests.swift`
- Modify: `Rasc.xcodeproj/project.pbxproj`

1. Add failing tests for note creation/update, soft-deleted empty content, snake_case schema, and migration from the existing camelCase schema without data loss.
2. Run the focused test target and confirm failures are caused by missing M1 behavior.

### Task 2: Implement the M1 database and repository

**Files:**
- Create: `Rasc/Domain/Note.swift`
- Create: `Rasc/Data/AppDatabase.swift`
- Modify: `Rasc/Data/NoteRepository.swift`
- Modify: `Rasc.xcodeproj/project.pbxproj`

1. Move `Note` into the domain layer with explicit snake_case column mapping and `deleted_at`.
2. Register immutable `v1_create_notes` and additive `v2_m1_notes_schema` migrations; migrate existing rows transactionally and never reset a database.
3. Make repository creation/update/fetch enforce meaningful content and exclude soft-deleted notes.
4. Run focused tests until green.

### Task 3: Specify session durability and restoration

**Files:**
- Modify: `RascTests/NoteRepositoryTests.swift`

1. Add failing tests for empty/whitespace drafts, debounced autosave, active-ID relaunch restoration, stale active IDs, and new-note preservation.
2. Confirm each test fails for the expected missing behavior.

### Task 4: Implement session lifecycle persistence

**Files:**
- Create: `Rasc/Data/ActiveNoteStore.swift`
- Modify: `Rasc/Features/Scratchpad/ScratchpadView.swift`
- Modify: `Rasc/Platform/PanelController.swift`
- Modify: `Rasc/App/AppDelegate.swift`
- Modify: `Rasc.xcodeproj/project.pbxproj`

1. Inject an active-note store and restore only its UUID.
2. Keep empty new scratches in memory and clear the active UUID on New.
3. Serialize the 200 ms debounce chain and await canceled/in-flight saves before explicit flushes.
4. Flush on hide, active-note/new-note transitions, and termination; preserve existing focus/Escape/hotkey behavior.
5. Run focused and full tests until green.

### Task 5: Verify the release gate

**Files:**
- No production changes unless verification exposes a defect.

1. Run `xcodebuild build` for the macOS destination.
2. Run all tests with `xcodebuild test` for the macOS destination.
3. Inspect `git diff --check`, the final diff, and package resolution.
4. Report the database path, autosave/restoration design, exact verification evidence, and manual macOS lifecycle checks still required.
