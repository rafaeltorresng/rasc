# Twin Fish completion review

The source artwork in repository history was already cropped at the upper-left tail. No uncropped master or editable vector was available. On 2026-11-23, the user approved `rasc-twin-fish-completion-simulation.png` as the complete mark to use. That approved full-mark simulation is now the raster master used by both repositories.

The upper-left tail continuation is inferred from the visible artwork and from the approved simulation. It is not a recovered original contour. The generated image was accepted as a complete-logo simulation; it changes more than the small tail region, so the side-by-side and overlay deliberately show all differences instead of claiming the rest of the artwork is pixel-identical. Native exports recolor its alpha silhouette for the existing app treatments.

## Review images

- `complete-before-after.png`: complete previous master and approved completion, shown side by side.
- `upper-left-magnified.png`: enlarged crop around the upper-left tail.
- `alpha-overlay.png`: registered silhouette comparison; red is old-only, green is new-only, and yellow is shared silhouette.
- `sizes-16-512-light-dark.png`: 16, 24, 32, 64, 128, and 512 px samples on light and dark backgrounds.
- `home-list-light.png` and `home-list-dark.png`: the current Home view rendered through AppKit with synthetic notes, showing the compact mark in both appearances.
- `before-master.png`, `after-master.png`: source images used in the comparison.
- `rasc-twin-fish-completion-simulation.png`: user-approved full-mark simulation.

## Export source

The app master is `rasc/Rasc/Resources/Brand/rasc-twin-fish-master.png`. Its exporter regenerates the macOS logo, compact mark, menu-bar template, and AppIcon assets. The website keeps a byte-identical copy at `rasc-web/brand/source-current/rasc-twin-fish-master.png`; `npm run brand:export` regenerates its favicons and web logo derivatives from that source and the synchronized app icon/menu assets.

## Validation limits

The macOS target builds. Its test run executed 40 tests; 38 passed and 2 window-position/level assertions failed in the current host environment (`PanelControllerTests/configuresPanelForFullscreenOverlayScratchpadBehavior` and `SettingsWindowPresentationTests/positionsSettingsWindowOnPresentationScreen`). The landing page was rendered at desktop and mobile viewport sizes with Playwright. The native app itself was not opened interactively, so Dock and menu-bar appearance were checked through their generated exports rather than a live desktop capture.

The isolated `HomeSnapshotTests` were also run during the follow-up app check: all 6 passed. Their Home captures use synthetic notes and the real AppKit/SwiftUI rendering pipeline; they are not screenshots of the packaged app running interactively.
