# Export validation

Native interaction checks used synthetic thoughts on Apple silicon, macOS
26.5.1, and Xcode 26.2. The visually inspected Release build used a separate
bundle ID and a local fixture launcher. Its export code and entitlements match
the release-equivalent candidate. The launcher seeds the fixture, opens Home,
and selects the test appearance.

- [Light picker](selected-light.png)
- [Dark picker](selected-dark.png)
- [Completion and Finder action](export-complete.png)

## Native and file checks

- Saved a text-only thought from the Home list context menu and a mixed thought
  from the Scratchpad command palette. Scratchpad returned focus to the editor.
- Exported two explicitly checked thoughts, all Kept thoughts, and all
  non-discarded thoughts. Read the resulting manifests and checked their
  memberships. Repeating the export added a suffix to the folder name and
  preserved previous copies.
- Checked Home card menu placement, keyboard Return and Escape, selection
  persistence while searching, and the accessibility names of checkboxes,
  buttons, and the selected count.
- Used the system save and folder panels to write outside the app container.
  Verified the locally packaged DMG, deep code signature and export entitlement.
  The main executable retains App Sandbox and no network entitlement.
- Finder Quick Look displayed Markdown source. After relocating the exported
  mixed folder, Pandoc rendered both images in order and their decoded bytes
  matched the fixture. Codex also interpreted a synthetic Markdown note plus
  two separately attached PNG files in their intended order.

## Automated coverage and limits

The export tests cover scope, exact UTF-8, structured text overrides, original
image bytes and order, Markdown fence fallback, safe and deduplicated filenames,
folder conflicts, stale snapshots, cancellation, pending image imports, and a
1,001-thought collection. The scale test finished in about 0.9 seconds for its
text-only fixture on this host, including setup and output. It does not measure
large-image throughput.

The PR review reran the shared Rasc scheme serially on macOS 26.5.1 with
isolated bundle IDs and storage. All 530 tests passed on unchanged `main` at
`6782386`, followed by all 538 on the export tree. Earlier runs of both trees
reproduced four intermittent native window failures covering Home activation,
fullscreen panel levels, Refine arrow keys and Command-W. One earlier export
run also had two intermittent Orb visibility failures. The export tests passed
in the targeted and full runs.
VoiceOver, Full Keyboard Access, older macOS, multiple displays and volume types
other than the local test filesystem remain unverified.
