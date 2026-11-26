# Try Voice Capture on this Mac

## Ten-minute pass

1. Open [Rasc Voice Study](<Study/Build/Rasc Voice Study.app>). The study has its own storage. Type a short disposable line into **Scratch** as a sentinel. Open **Study Options**, select **Parakeet Ultra**, and leave **Review before Keep** selected. First permission does not start recording. Allow it, then start again. Use **Prepare Model** if you want to isolate warm performance. Note any long wait for the first unprepared capture instead of discarding that observation.
2. Start, wait for **Listening**, and try the lines below. Pause naturally, including two seconds in one capture. After Finish, inspect **Show Raw** before editing. Log meaningful corrections, and Keep only when the thought says what you intended. Open the saved thought and Undo one test. The scratch sentinel should remain intact.
3. Repeat comparable short and longer examples with **Fluid Speech Pro** and **Apple SpeechTranscriber**. Prepare Apple’s PT-BR or English asset when asked. Use PT-BR for Portuguese-led mixed speech, and record which setting you chose. Compare the meanings and correction effort before looking at timings in Study Options.
4. Assign an unused chord in Study Options and test in another app using only test content. Try toggle, then hold. Try finishing immediately after the last word and deliberately starting early on one separate run. Note the order of the key release and your last word. After review, try **Keep with confirmation** and **Keep with Open and Undo** on disposable lines. Check whether the previous app retains focus when the receipt appears.
5. Cancel during one recording and one prolonged finalization. Do one silent recording and one brief accidental press. Count the saved notes and check the scratch sentinel. Confirm that the macOS mic indicator stops promptly after Finish or Cancel.

### Controlled examples

- “Não apaga isso.”
- “Talvez seja melhor usar o Supabase, mas não quero tomar essa decisão ainda.”
- “Precisamos revisar a race condition no worker antes de fazer o deploy, mas não sei se esse é realmente o problema.”
- “I was thinking that maybe we should simplify the onboarding, but I’m not entirely sure yet.”
- “Version two point zero point seven, error four oh three, timeout one hundred eighty milliseconds. No, make that eighty.”
- Make up one 20–45 second idea on a neutral subject. Begin with an incomplete thought, pause, then change your mind on one detail. Do this independently in Portuguese, English and mixed speech where natural. Give one fictitious name or date.

**Audio stays in memory unless you select Save Evaluation Audio in review.** Use the button only for a clip you intend to contribute to the test. It saves WAV in the local **Evaluation Clips** folder, which you can find via **Show Study Files** in Study Options. Record only yourself and test content. Keep your intended verbatim text separately under the audio clip ID. Save a clip once for paired engine replay rather than speaking the same evaluation sentence separately into each model. Keep consenting speakers and prompts disjoint across development and holdout. Audio and full transcripts from held-out human captures should stay in a private study workspace. Share only selected excerpts or measurements you approve. The file can be deleted from the study folder after evaluation.

## Compare the actual workflows

For short thoughts use a 3–10 word correction or reminder. For longer thoughts use a 20–45 second idea. Prefer three comparable tasks per method and length. Rotate the order between users and keep the target thought comparable. Set up shortcuts and languages before timing the warmed trial. Measure the cold trial separately. Rasc and Dictation trials should use disposable text and a testing profile or isolated checkout.

| Method | Start the clock | Stop the clock | Record |
|---|---|---|---|
| Type in Rasc | Invoke Scratchpad | Correct thought Kept and original app usable again | Seconds, edits, focus moves |
| macOS Dictation in Scratchpad | Invoke Scratchpad | Correct thought Kept and original app usable again | Same fields, chosen OS language and stop action |
| Dedicated Voice Study shortcut | Press assigned chord | Correct thought committed and original app usable again | Same fields, engine, toggle/hold, review/auto, cold/warm, time until Listening, and finish-to-commit |

A suggested log row contains method, language, duration, environment, shortcut mode, expected and recognized critical spans, edits, correct-save-and-return seconds, and which app had focus. Classify errors as missing or changed negation, uncertainty, entity, number/date, identifier, correction, start/end boundary, unsupported addition, unintended translation, or readability. Preserve raw output. Compare the percentage of usable thoughts with zero edits. One participant’s preference is directional evidence only.

## Native follow-up checklist

- Built-in input and Bluetooth headset separately. Check first-ready, wrong device, AirPods connecting mid-thought and disconnection. Test another app already using the input. Some route changes may end a capture for review. Verify that useful partial audio can still be recovered.
- Focus before and after toggle/hold, review, automatic receipt, Open and Undo. Test fullscreen, Spaces switches, Stage Manager, external display, main vs pointer display and keyboard-only use.
- VoiceOver labels/announcements, Full Keyboard Access, Reduce Motion, dark/light/themes and multi-key rollover. Inspect repeat presses, modifier release order, shortcut conflict and the next activation after a missing key-up.
- Test mic denial and later authorization, fresh launch and relaunch with the same signed app, 10 minutes idle, sleep while speaking, and wake. Turn off networking after language setup, relaunch, and run all selected engines in PT and English. Observe the macOS mic indicator whenever the study is idle.
- Repeat captures and rapid Cancel then Start, cancellation during model load, finalization and review, 90-second cap, background noise, empty file and unprepared language. Confirm no stale receipt, duplicates, scratch changes, unclear recording state or successful receipt for a cancellation.
- Engineering pass with a disposable database: deliberately reject a write and ensure retry preserves the same ID and text. Confirm old repository migration/durable commit on process restart. Use a sandboxed release build for these trials. Force quit and crash behavior must explicitly account for in-memory audio loss.
