# Rasc Twin Fish — app validation

Candidate 02, `Rasc twin fish logo`, was adopted as the Rasc mark for
0.1.10/build 16. The approved reference is
`~/Downloads/rasc-logo-comparison/02-twin-full-cropped.png`. The production
master is `Rasc/Resources/Brand/rasc-twin-fish-master.png`, a byte-for-byte copy
of that reference; it is a raster master, not a claimed vector redraw.

## Assets

`swift Scripts/assets/export-brand.swift` trims transparent padding and recolors
the unchanged silhouette. It exports:

- `RascLogo` graphite `#242423` for light surfaces and warm paper `#F7F5F0` for dark.
- `RascLogoCompact` at 24 px / 48 px for both appearances.
- `MenuBarIcon` as a monochrome template of the same mark.
- All 10 AppIcon sizes on the existing light native plate, with a composed scale
  and slightly high optical placement for the Dock.

Only two size-specific optical corrections are applied: the 16 px 1x tile is a
2x render downsampled once, and the 24 px 1x Home export has 1.5 px of physical
headroom. Neither changes the silhouette. No copper is used in brand assets.

## Native checks (macOS 26.5.1, Apple M3 Pro, 2026-11-17)

Screenshots in this folder are from the packaged 0.1.10/build 16 app installed
in `/Applications`, using synthetic notes and a fixed 760×721 pt Home window.

- `home-dark.png`, `home-light.png` — new mark beside the unchanged wordmark.
- `onboarding-dark.png`, `onboarding-light.png` — large identity in Welcome.
- `finder-icon.png` — installed icon in Finder (Rasc is `LSUIElement`, so there
  is no persistent Dock tile; the menu bar is the persistent presence).
- `menubar.png` — cropped menu-bar template at actual size.
- `capture-keep-retrieval.png` — a synthetic note was captured with **New
  Scratch**, kept with **Shift-Command-K**, and found again in Home under Kept.

The shape was compared against the approved reference: two fish, uneven scale,
open curve, and gap are preserved. Colors and appearance mapping were checked
against the design system.

## Upgrade check

The published 0.1.9/build 15 app was installed with synthetic data. Sparkle
offered **0.1.10 is now available—you have 0.1.9**, downloaded
`Rasc16-15.delta`, installed and relaunched as 0.1.10/build 16. Notes (4 at the
start), `appTheme=rascDark`, and the global Scratchpad shortcut (`⌥\`) were
unchanged. The installed app passed `codesign --verify --deep --strict`, carried
a valid Library Load Constraint, and had Sparkle mapped. The local feed override
was removed after the check.

After publication, the live production feed was checked from the installed
0.1.10 app: **Check for Updates…** reported “You're up to date! Rasc 0.1.10 is
currently the newest version available.” (`live-updater-smoke.png`). The deployed
feed was byte-identical to the verified local appcast and the public release
asset resolved with the expected checksum.

Not verified in this pass: VoiceOver, Reduce Motion, clean install from the
public DMG by a second account, and macOS 14–25.
