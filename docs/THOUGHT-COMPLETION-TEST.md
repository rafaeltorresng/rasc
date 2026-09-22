# Thought completion — manual acceptance (~10 min)

**Build:** 0.1.0-beta.3 (4) or later dev build  
**Prerequisite:** Clean launch or known test database

Use this script after automated tests pass. Each step should feel like one coherent lifecycle.

---

## 1. Capture → Keep → fresh scratch

1. Invoke Rasc with the global shortcut.
2. Type a messy thought (e.g. `maybe refactor onboarding copy tomorrow`).
3. Wait ~1s for autosave.
4. Click **Keep** (or `⇧⌘K`).
5. **Expect:** brief **Kept** feedback, panel hides within ~0.5s.
6. Invoke Rasc again.
7. **Expect:** empty fresh scratch, not the kept note.

---

## 2. Home shows kept thought

1. Open Home (house icon or palette **Open Home**).
2. **Expect:** **Kept** section contains the thought from step 1.
3. **Expect:** unfinished/recent sections still present for other notes.

---

## 3. Reopen → Unkeep → edit → Keep again

1. Open the kept note from Home.
2. **Expect:** full content visible; **Unkeep** shown (not Keep).
3. Click **Unkeep**.
4. **Expect:** **Unkept** feedback; note is unfinished again; content unchanged.
5. Edit one word.
6. Keep again.
7. **Expect:** same completion moment as step 1.

---

## 4. Copy Note (no state change)

1. Start a new thought: `copy me to clipboard`.
2. Open palette (`⌘K`) → **Copy Note**.
3. Paste in TextEdit.
4. **Expect:** exact note text.
5. Return to Rasc — note still unfinished (not kept, not deleted).

---

## 5. Share… (no state change)

1. New thought: `share me via macOS`.
2. Palette → **Share…** (or menu **Note → Share…**).
3. **Expect:** native share sheet with plain text.
4. Cancel or share — note state unchanged in Rasc.

---

## 6. Discard Note

1. New thought: `discard this scratch`.
2. Palette → **Discard Note** (or menu).
3. **Expect:** note removed from Home/Search; fresh empty scratch if panel stays open.
4. **Expect:** other notes unaffected.

---

## 7. Refine + Keep

1. New thought with messy text.
2. Refine (`⌘J`), accept preview.
3. Keep immediately.
4. **Expect:** kept content matches accepted refinement.
5. Reopen from Home — refined text preserved.

---

## 8. Search

1. `⌘P`, search for text from a kept note.
2. **Expect:** result found with **Kept** label.
3. Search for an unfinished note.
4. **Expect:** found without Kept label.

---

## 9. Restart persistence

1. Quit Rasc completely.
2. Relaunch.
3. Open Home.
4. **Expect:** kept notes still kept; unfinished notes still unfinished.

---

## Pass criteria

- Keep feels like **this thought is done**, not a label.
- Next normal invocation after Keep is always fresh.
- Unkeep is reversible without content loss.
- Copy/Share never mutate state.
- Discard soft-deletes only the intended note.
- No folders, tags, or archive UI appeared.

**Result:** PASS / FAIL  
**Notes:**
