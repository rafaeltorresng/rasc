# Voice Capture and Dictate

Voice Capture and Dictate are opt-in features for Apple silicon Macs running macOS 26
or later. Rasc itself still targets macOS 14. Speech recognition uses Fluid Speech Pro
in verbatim mode (plus `VoiceTranscriptSanitizer` whitespace/hallucination cleanup).
Voice Capture opens the transcript in Scratchpad as an unfinished thought (`origin = .scratch`),
while Dictate inserts into the focused external app via `AXSelectedText` or copies to the
clipboard (and optionally keeps a local note with `origin = .dictation`). Refine remains a
separate explicit Scratchpad action.

## Try the local build

1. Open **Rasc Voice Preview.app**. This build has its own app identity,
   preferences, note database and microphone permission. It includes the
   pinned speech model.
2. In Settings → Voice Capture, enable the feature and choose a free global
   shortcut. You can also start from the menu bar. Wait for **Listening**
   before speaking. The first recording is when macOS asks for microphone access.
3. Press the shortcut again to finish. Scratchpad opens with the transcript
   and the caret at the end. Continue writing or use the usual Scratchpad
   commands for Refine, Keep, and Discard. Escape dismisses the Scratchpad
   and preserves the unfinished thought.
4. To check that both thoughts survive, start a typed scratch before recording.
   After the transcript opens, find the typed thought again in Home or Search.
   If an open dialog or concurrent edit delays the switch, the capsule offers
   **Open**. To retry microphone access after a denial, open System Settings
   from the status panel.

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

- Shortcuts support both `KeyboardShortcuts` chords and clean single-modifier taps
  (`Option`, `Command`, `Control`, or `Shift` via `ModifierShortcutMonitor`, checking
  Accessibility trust without keylogging unrelated events). When Scratchpad already has
  focus, its native key handler also consumes the assigned shortcut so it cannot type into
  the note. The capsule is a non-activating `.screenSaver`-level HUD during capture
  and shows a countdown warning during the final 15 s of the temporary **120 s (2-minute)** limit.
- Audio capture allocates memory lazily in 5 s chunks up to the capture limit (`MicBuffer`), selects
  the active channel via `vDSP.maximumMagnitude` on multi-channel/USB interfaces, compacts
  short captures off the CoreAudio callback, resamples non-16 kHz streams through a reusable
  continuous `15 s` chunked `AVAudioConverter` loop inside `autoreleasepool` without
  resetting FIR filter state (`VoiceAudio.mono16k()`), guards audio-engine startup with a
  5.5 s HAL watchdog, and applies a dynamic transcription timeout
  (`max(30, audioSeconds * 0.5 + 15)`).
- Dictate (`VoiceTextInsertion`) wakes Electron accessibility trees (`AXManualAccessibility` /
  `AXEnhancedUserInterface`), refuses Secure Input (`IsSecureEventInputEnabled()` and
  `AXSecureTextField`), and inserts with `textWithSmartLeadingSpace` through `AXSelectedText`,
  falling back to a verified `AXValue` range replacement for editors that do not implement
  `AXSelectedText`. Focused elements are resolved from the app, the system-wide AX element
  and the app's main window; in-app delivery uses the captured SwiftUI field editor rather
  than only a bare first responder. It never posts synthetic keystrokes, never activates another app, and
  preserves the focused app, window, first responder and caret across the cycle. Delivery is
  restricted to the target captured at start; a changed app or editor window produces an
  honest clipboard fallback instead of inserting elsewhere. The HUD distinguishes missing
  Accessibility, no focused field, incompatible target, failed insertion, and focus changes.
  Accessibility trust is re-read when Rasc becomes active, so the **Allow…** action appears
  only while this running build truly lacks permission. **Allow…** first prompts for this
  build's TCC identity; macOS may silently skip that prompt when an older Rasc entry is
  still enabled, so if trust has not changed Rasc opens Accessibility once and shows the
  concrete resolution: remove the old entry, add this exact bundle with **+**, then return.
  The same guidance appears onboarding and in Settings → Voice. An ad-hoc RC is a distinct
  Accessibility client from the distributed app and from every other ad-hoc build.
- Standard Rasc distributions do not bundle the 622 MiB speech model. When you
  enable Voice Capture and choose **Download Speech Model**, an embedded
  sandboxed XPC helper (`com.rafaeltorres.rasc.VoiceModelDownloader.xpc`,
  with only `app-sandbox` and `network.client` entitlements) downloads the
  pinned files with HTTP `Range` resume support into its own cache and hands
  read-only file handles back to Rasc. The main app keeps its network-isolated
  sandbox, verifies every byte size and SHA-256 hash against
  `VoiceModelManifest.json`, atomically installs into
  `Application Support/Rasc/VoiceModels/<revision>/`, prunes older revisions,
  and clears the helper cache. You can also remove the installed model from
  Settings to reclaim storage, or import a local folder with **Choose Model Folder…**.
- Rasc starts preparing speech on opt-in and after launch when Voice Capture
  is already enabled. A recording can share the same in-progress load. The
  microphone opens only when recording starts. The fixed 120 ms end buffer preserves
  speech near Finish. Silence never triggers Finish. The socket-free inference
  path loads one cleanly versioned Core ML pack with CPU + Neural Engine.
  Rasc keeps the pack prepared while Voice Capture is enabled and system
  resources permit, and releases it on sleep, under memory pressure, when
  removed, or when the feature is disabled. Once system wake or normal memory
  pressure returns, Rasc proactively re-prepares the model in the background.
  A load needed by an active capture is protected until that capture finishes. Core ML can still specialize the model again on
  a cache miss. If a load fails with low available disk space, the capsule
  offers a disk-space message and **Retry** for the same recording.
- SQLite saves the transcript as an ordinary unfinished thought. The existing
  Scratchpad opening path flushes the previous thought and guards against
  concurrent edits before switching. If the switch must wait, the transcript
  is already searchable in Home. Recovery from a failed save retries the text.
  Older preview transcripts migrate from their pending review into normal notes.
- On an M3 Pro with 18 GB and macOS 26.5.1, a signed probe built from the
  integrated recognition and audio sources loaded the model in 18.09 s
  on its first run at that path and 201 ms after restarting at the same path.
  On two short EN/PT fixtures, inference took 38–63 ms. This excludes the
  microphone, the finish buffer, Scratchpad presentation and SQLite. Probe process footprint
  was 25 MB immediately after load, peaked at 59 MB across those observations,
  and dropped to 31 MB after release. The model occupies 652,304,885 bytes.
  A separate run retained the Release sandbox entitlements, received EPERM
  when connecting to a listening local socket, then transcribed both fixtures.
  This is an egress-denied inference test, with microphone and full-app
  latency measured separately in the earlier study. Path and configuration
  affect Core ML's device-specific cache. [Apple Core ML lifecycle](https://developer.apple.com/videos/play/wwdc2023/10049/)
- Audio up to 15 s uses one Fluid Speech Pro window. Longer audio decodes in contiguous
  windows chosen near pauses, in recording order. A bounded retry can recover a gap
  that contains audio energy. The retry adjusts gain only for wide level differences
  and is accepted only when it accounts for more audio and retains most earlier token IDs.
  The 120 s cap bounds capture while a five-minute gain-stress omission remains open.
  [Long-form follow-up](../Experiments/VoiceCapture/Round5/REPORT.md#reliability-follow-up-after-5c4e5ad)
- The pinned batch path uses no streaming decoder or vocabulary rescoring.
  `VoiceTranscriptSanitizer.clean` normalizes spacing and strips
  isolated ASR filler/hallucination artifacts; Scratchpad and Dictate remain
  verbatim. Refine is invoked separately by the user. Recognition diagnostics
  record timing only. For current metrics see:
  - Round 4 FLEURS (`5.354%` pooled WER, `69.90 ms` p50 warm): `Experiments/VoiceCapture/Round4/RESULTS.md`.
  - Historical engine comparisons, software timing endpoints and the final reliability follow-up have separate provenance. [Voice evidence](evidence/voice-competitive-web-data.json)

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
  that change meaning in PT/EN and mixed speech. The transcript opens as
  editable, unfinished text. Repeat cold capture, physical readiness and
  energy checks on memory-constrained Apple silicon before publishing.
