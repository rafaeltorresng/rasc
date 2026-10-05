# Rasc

**A scratchpad for unfinished thoughts.**

Rasc is a native Mac app for the place before the note. Invoke it over your work,
capture a thought, optionally Refine it, then Keep it and carry on.
No account, folders, prompts, or organization required.

<p><img src="Rasc/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="96" alt="Rasc app icon"></p>

## Using Rasc

| Action | Default shortcut |
| --- | --- |
| Invoke or hide the scratchpad | `⌥\` |
| New Scratch | `⌘N` |
| Refine the thought or a selected passage | `⌘J` |
| Keep and return to work | `⇧⌘K` |
| Search thoughts | `⌘P` |
| Open Home | `⌘⌥\` |
| Hide and continue the same thought later | `Esc` |

Capture, autosave, Keep, Home and Search work independently of Refine.
Refine offers a conservative edit. Compare Suggested and Original before accepting;
Keep original dismisses the proposal without changing your text.
Discard has Undo while Rasc remains running; it does not introduce a Trash system.

## Requirements and installation

- **App:** macOS 14 or later. Current direct-distribution builds target Apple silicon.
- **Refine:** macOS 26 or later, an Apple Intelligence-capable Mac, Apple Intelligence
  enabled, and its on-device model ready. Rasc remains useful when Refine is unavailable.
- **Development:** Xcode 26.2 or later, Swift 6, and the macOS 26 SDK.

This source revision is **0.1.0-beta.4, build 5**. It is a local candidate, not a
published release. There is no published GitHub Release for this revision yet.
The older beta.3 DMG does not contain these changes. Build from source below, or
use a separately supplied versioned DMG whose checksum and release notes you can verify.

For public distribution, Developer ID signing, notarization and packaged-app
verification remain release gates. An ad hoc development build is not notarized.
See [release workflow](docs/RELEASE.md).

## Build and test

Open `Rasc.xcodeproj`, select the shared **Rasc** scheme and run. Swift packages
are pinned in `Package.resolved`; ThinkingOrbsKit is vendored locally.

```sh
xcodebuild -project Rasc.xcodeproj -scheme Rasc -configuration Debug \
  -derivedDataPath .derivedData/Rasc CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
xcodebuild -project Rasc.xcodeproj -scheme Rasc -configuration Debug \
  -derivedDataPath .derivedData/Rasc -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test
```

If LaunchServices prevents the native test runner from starting, run the real
non-window suites separately after resolving/building the packages:

```sh
python3 Scripts/test-domain.py
```

This fallback excludes five native window suites. It does not verify keyboard
focus, VoiceOver, fullscreen, Spaces, Stage Manager, or multiple monitors.
Use the [current manual checklist](docs/NATIVE-UI-VALIDATION.md) for those.

## Privacy and boundaries

Thoughts live in a local SQLite database under Rasc's Application Support directory
(in the app sandbox for packaged builds). No backend, account, telemetry, sync,
cloud inference, or semantic search is required. Refine uses Apple's local
Foundation Models provider, with a fresh request for each operation.
The Release app has sandbox entitlement only and no outgoing network entitlement.

Refine can still make mistakes. It preserves the original until you accept and
checks revisions, language and protected literals. Review the proposal before
accepting; automated checks do not prove that every meaning is unchanged.

Copy and Share are explicit handoffs. Feedback opens a draft email with app/system
version details; it does not attach your thoughts or send automatically.

## Contributing

Start with [CONTRIBUTING](CONTRIBUTING.md) and the [documentation index](docs/README.md).
Rasc deliberately stays a scratchpad: folders, tags, chat, sync, agents and project
management are outside its current scope. Bug fixes, native craft, accessibility,
reliability and conservative Refine improvements are welcome.

[Source](https://github.com/rafaeltorresng/rasc) ·
[Security reporting](SECURITY.md) · [Community conduct](CODE_OF_CONDUCT.md)

## License

[MIT](LICENSE). Dependency licenses and provenance are listed in
[third-party notices](docs/THIRD_PARTY_NOTICES.md) and included in the app bundle.
