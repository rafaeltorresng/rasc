# Rasc brand and state contract

The **symbol is Rasc's identity**. The approved mark is **Rasc Twin Fish**,
candidate 02 from the 2026-11-17 comparison. The Thinking Orb has been removed
from the interface; the symbol and app icon remain separate from any future
character exploration.

## Symbol and exports

`Rasc/Resources/Brand/rasc-twin-fish-master.png` is the production master. It is
a faithful raster of the approved silhouette, with a transparent background, and
retains the two fish, their uneven scale, the open curve and the gap between
them. It is not a claimed vector asset; no redraw was substituted for fidelity.
The previous `rasc-symbol-master.png` is retained for historical reference only
and is no longer used by the export pipeline.

`Scripts/assets/export-brand.swift` trims transparent padding, recolors the same
silhouette to graphite (`#242423`) on light surfaces and warm paper (`#F7F5F0`)
on dark surfaces, then exports both logo appearances, the 24 pt compact
representations, the menu-bar template and all 10 macOS AppIcon sizes. The app
icon keeps the existing light native plate and uses a composed scale and optical
centering appropriate for the Dock. No new geometry, hidden R, texture or copper
is introduced; copper remains exclusive to Keep and Kept.

From the repository root:

```sh
swift Scripts/assets/export-brand.swift
```

Review the 16/32 px exports and both appearances before accepting an asset change.
The only size-specific optical corrections are a 2x render downsampled for the
16 px 1x Dock tile and 1.5 px of physical headroom in the 24 px 1x Home export;
neither changes the silhouette. The menu-bar icon is a monochrome template using
the same mark, drawn at roughly 24 pt inside the 32 pt template so its visual
weight matches standard macOS status items. Welcome and Home identity use the
symbol; the editor has no persistent character or state indicator.

## Orb (historical)

The Orb is no longer used in the interface. The following describes the retained historical asset.

Rasc wraps the vendored engine in `RascOrb`; product views do not depend directly
on engine vocabulary. The retained `RascOrbPalette` used a violet-led / warm-accent identity:

- Light: periwinkle highlight → `117/100/216` family → `199/74/20` accent.
- Dark: luminous violet (historical palette) → brand violet → bright orange accent for graphite legibility.
- Optional soft violet shadow for presence; omit when Reduce Transparency is on.
- Former editor/writing state: Composing.
- Former Quick Search state: Searching.
- Former Refine state: Shaping (`.refining` in the wrapper).
- Former empty Home state: Connecting, an idle invitation rather than a network claim.
- Former Command Palette state: Note/Solving.

Earlier Breathing guidance is superseded. Reduce Motion stops continuous motion
in the vendored renderer. The gradient, speeds and engine geometry are unchanged
by the native UI quality work.

## Colors and motion

Copper marks Keep and Kept. Neutral graphite communicates focus and selection.
Use shared RascSurfacePalette/metrics/motion.
Keep the editor solid. Materials must respect Reduce Transparency; borders and
focus must remain readable with Increase Contrast. Validate the rendered result,
not merely the presence of a modifier.

## Home identity at native small sizes

Home uses `RascLogoCompact` at 24 pt instead of reducing the large logo to a
smaller rendered size. The compact imageset supplies 24px (1x) and 48px (Retina
2x) representations for both appearances, exported directly from the approved
master alpha by `Scripts/assets/export-brand.swift`. Onboarding continues using
the large representation. The Dock icon uses the same silhouette at a composed
scale and optical position; it is intentionally not the standalone Home crop.

Validation of the Twin Fish rollout, including native Home and onboarding
captures in light and dark, the Dock/Finder icon and small placements, is in
`docs/validation/rasc-twin-fish/`. The older `docs/validation/home-logo/`
evidence is historical and describes the previous symbol, not the current mark.
