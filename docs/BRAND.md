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
on engine vocabulary. Preserve the approved violet/orange gradient:

- Violet: `117/100/216`, stops 0 and 0.58.
- Orange: `199/74/20`, stop 1.
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
