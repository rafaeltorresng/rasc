# Scratchpad Orb removal — native comparison

Dark-mode, synthetic/empty state, same placeholder text. The before frame is the
pre-change baseline from the Refine reliability work; the after frame is the
installed 0.1.9/build 15 app after the in-app Sparkle upgrade on macOS 26.5.1
(Apple M3 Pro), captured with `screencapture -l` on 2026-11-17.

- `before-empty-dark.png` — Thinking Orb at top-left, persistent New/Refine/Keep,
  instruction line, violet border, first line lower.
- `after-empty-dark.png` — no Orb, only Home at top-right, no instruction line,
  neutral graphite surface, first line closer to the top.

Verified live during the 0.1.9 candidate pass: Escape hides Scratchpad and
restores the same unfinished thought; Home and Settings open with correct focus;
the in-app upgrade from 0.1.8 preserved notes, theme, and shortcuts. Light mode,
narrow window, VoiceOver, Reduce Motion, and macOS 14–25 were not verified in
this pass.
