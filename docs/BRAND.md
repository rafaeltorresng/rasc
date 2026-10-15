# Rasc brand and state contract

The **symbol is Rasc's identity**. The **Thinking Orb conveys product activity**.
Do not use the Orb as a logo or a decorative AI centerpiece.

## Symbol and exports

`Rasc/Resources/Brand/rasc-symbol-master.png` preserves the existing dark raster
source unchanged. It is a raster master, not a claimed vector asset.

`Scripts/assets/export-brand.swift` isolates its two connected symbol forms,
removes detached export residue while retaining edge pixels, normalizes optical
bounds and exports both logo appearances and all 10 macOS AppIcon sizes. The app
icon places the same symbol on a quiet light native plate for Finder legibility.
No new symbol geometry is drawn.

From the repository root:

```sh
swift Scripts/assets/export-brand.swift
```

Review the 16/32 px exports and both appearances before accepting an asset change.
The menu-bar icon stays a monochrome template. Welcome and Home identity use the
symbol; the editor's state indicator remains the Orb.

## Orb

Rasc wraps the vendored engine in `RascOrb`; product views do not depend directly
on engine vocabulary. Preserve the violet-led / warm-accent identity in `RascOrbPalette`:

- Light: periwinkle highlight → `117/100/216` family → `199/74/20` accent.
- Dark: luminous violet (aligned with `RascSurfacePalette`) → brand violet → bright orange accent for graphite legibility.
- Optional soft violet shadow for presence; omit when Reduce Transparency is on.
- Editor/writing: Composing.
- Quick Search: Searching.
- Refine in progress: Shaping (`.refining` in the wrapper).
- Empty Home: the existing Connecting motion, as an idle invitation, not a network claim.
- Command Palette: the existing Note/Solving mapping.

Earlier Breathing guidance is superseded. Reduce Motion stops continuous motion
in the vendored renderer. The gradient, speeds and engine geometry are unchanged
by the native UI quality work.

## Colors and motion

Orange communicates action. Violet communicates focus, selection and state.
`violetText` uses a darker light-mode tone for small text; it does not replace the
Orb gradient or selection token. Use shared RascSurfacePalette/metrics/motion.
Keep the editor solid. Materials must respect Reduce Transparency; borders and
focus must remain readable with Increase Contrast. Validate the rendered result,
not merely the presence of a modifier.

## Home identity at native small sizes

Home uses `RascLogoCompact` at 24 pt instead of reducing the 512px logo to
20 pt. The compact imageset supplies 24px (1x) and 48px (Retina 2x) representations
for both appearances. They are exported directly from the same retained source
alpha by `Scripts/assets/export-brand.swift`; no new silhouette, colors or
Thinking Orb behavior is introduced. The existing large logo and AppIcon exports
are unchanged. Onboarding continues using the large representation.

Debug and Release builds succeeded. The compiled asset catalog contains all four expected
appearance/scale combinations. Native SwiftUI ImageRenderer checks used the real
`RascLogo` component and compiled catalog in light/dark at 1x/2x. PNG comparisons
and asset checks are in `docs/validation/home-logo/`. The 1x perimeter has faint
anti-aliasing coverage (maximum 59/255); no opaque silhouette reaches the edge.
Retina perimeters are fully transparent. The Home, theme selection and search
focus were also checked in the isolated native Release app. VoiceOver and the
full native window suite were not revalidated locally. Release 0.1.1/build 7 is
installed at `/Applications/Rasc.app`; the retained DMG and previous installation
are documented in `docs/validation/home-logo/README.md`.
