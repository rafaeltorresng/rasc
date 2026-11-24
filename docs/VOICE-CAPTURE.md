# Voice Capture

Voice Capture is an opt-in feature for Apple silicon Macs running macOS 26 or
later. Rasc itself still targets macOS 14. Voice Capture uses Fluid Speech Pro
in verbatim mode. Review lets you correct recognition errors before Keep.
Refine remains available as an explicit action on the kept thought.

## Try the local build

1. Open **Rasc Voice Preview.app**. This build has its own app identity,
   preferences, note database and microphone permission. It includes the
   pinned speech model.
2. In Settings → Voice Capture, enable the feature and choose a free global
   shortcut. You can also start from the menu bar. Wait for **Listening**
   before speaking. The first recording is when macOS asks for microphone access.
3. Press the shortcut again to finish. Edit the transcript if needed and
   click **Keep** or press ⌘Return. The confirmation offers **Open** and
   **Undo**. Try keeping one capture while another Scratchpad thought is open.
4. Escape closes the review and retains it for the next Voice Capture action.
   Use **Discard** to remove the pending transcript. To retry microphone access
   after a denial, open System Settings from the status panel.

To build another isolated signed preview:

```sh
python3 Scripts/stage-voice-model.py /tmp/rasc-voice-model
Scripts/build-voice-preview.sh /tmp/rasc-voice-model
```

Staging downloads only pinned model files. To use a verified cached copy,
pass `--from path/to/model` to the staging script. The preview is ad-hoc
signed and contains no updater. A regular build without the packaged model
can import that same directory through **Choose Model Folder…**.

## Engineering and validation

- The global shortcut uses KeyboardShortcuts key-up events. Enabling
  Voice Capture leaves the default Scratchpad and Home chords unchanged. The
  capsule is non-activating. Review is a separate, editable native panel.
- Preparing is explicit on opt-in and can overlap recording after the
  first genuine microphone buffer. The fixed 120 ms end buffer preserves
  speech near Finish. Silence never triggers Finish. The socket-free inference
  path loads one cleanly versioned Core ML pack with CPU + Neural Engine.
  After use, the actor releases the pack after 180 seconds of inactivity,
  on sleep, under memory pressure, or when the feature is disabled.
- SQLite stages one recoverable transcript, then inserts the ordinary kept
  thought and removes that stage in a single transaction. Keep is idempotent
  on the capture UUID. Undo verifies the saved snapshot before soft-deleting it.
  Home and an open Quick Search refresh after the commit. Voice Capture
  leaves the current scratch untouched. Open uses the usual note navigation.
- The shared Rasc scheme passed 550 tests, including 12 Voice Capture
  tests and 120 consecutive cancellation cycles with synthetic input. The
  new tests exercise denied and first-use permissions, silence, microphone
  interruption, stale transcription, audio boundaries, restart recovery,
  transaction rollback, duplicate Finish and Keep, FTS, guarded Undo, and
  non-key panel presentation. AppKit rendered Listening, Review and Kept in
  light and dark appearances. The signed app's live accessibility tree exposed
  the default-off toggle, model preparation status and shortcut recorder.
- On an M3 Pro with 18 GB and macOS 26.5.1, a signed probe built from the
  integrated recognition and audio sources loaded the model in 18.09 s
  on its first run at that path and 201 ms after restarting at the same path.
  On two short EN/PT fixtures, inference took 38–63 ms. This excludes the
  microphone, the finish buffer, review and SQLite. Probe process footprint
  was 25 MB immediately after load, peaked at 59 MB across those observations,
  and dropped to 31 MB after release. The model occupies 652,304,885 bytes.
  A separate run retained the Release sandbox entitlements, received EPERM
  when connecting to a listening local socket, then transcribed both fixtures.
  This is an egress-denied inference test, with microphone and full-app
  latency measured separately in the earlier study. Path and configuration
  affect Core ML's device-specific cache. [Apple Core ML lifecycle](https://developer.apple.com/videos/play/wwdc2023/10049/)
- The pinned batch path does not use FluidAudio’s streaming or vocabulary
  rescoring calls. The review UI receives the exact returned string. Refine
  and recognition diagnostics never receive capture text from this feature.

## Release gates

- **Microphone consent across Sparkle updates.** Two strict-verified
  integrated app builds shared the same bundle identifier, but their ad-hoc
  designated requirements failed cross-verification. The prior genuine local
  Sparkle trial also reproduced a microphone grant reverting to undetermined.
  Rasc checks authorization anew each explicit start and explains how to
  reauthorize. A release that promises permission continuity needs a genuine
  Sparkle test between two builds signed with a stable publisher identity.
  This Mac had no valid Developer ID Application identity. Signing policy and
  production update configuration are unchanged. [Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
- **Model delivery and release packaging.** Choose between an included model
  and a separately distributed verified pack, then verify the signed release
  artifact and Sparkle upgrade size. The local preview includes the pack and
  has no model setup download. Imported assets have a stable path across app
  replacement. A fresh install, relocation, macOS cache eviction or model
  revision can still incur Core ML specialization.
- **Integrated native checks.** Real microphone permission and acoustic
  boundaries require a recording on the signed preview. Full VoiceOver and
  Full Keyboard Access interaction, physical key chords, Bluetooth route
  changes, separate displays, fullscreen Spaces, Stage Manager, and sleep
  on an actual capture still need device-level checks. The software fixtures
  cover states and outcomes but do not reproduce those physical conditions.
- **Fidelity and resource targets.** The study measured occasional errors
  that change meaning in PT/EN and mixed speech. Keep review before default
  persistence. Repeat cold capture, physical readiness and energy checks
  on memory-constrained Apple silicon before publishing. Automatic Keep
  requires separate evidence and a product decision.
