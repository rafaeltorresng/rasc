# Third-Party Notices

## ThinkingOrbsKit

Rasc vendors a local copy of **ThinkingOrbsKit** from the Libraries.dev monorepo for dotted thought-orb loading indicators.

| Field | Value |
|---|---|
| Upstream repository | https://github.com/Jakubantalik/Libraries.dev |
| Upstream Swift source path | `packages/thinking-orbs/ports/ios/ThinkingOrbsKit` |
| Upstream commit | `d673577a8cec2f36fa563e2d3c6595968af285b6` |
| Upstream license path | `packages/thinking-orbs/LICENSE` |
| Vendored location | `Vendor/ThinkingOrbsKit/` |
| License | MIT |
| Copyright | Copyright (c) 2026 Jakub Antalik |

The upstream MIT license text is reproduced in:

- `Vendor/ThinkingOrbsKit/LICENSE` (vendored copy of `packages/thinking-orbs/LICENSE`)
- `Rasc/Resources/ThirdPartyNotices.txt` (included in the distributed app bundle)

### macOS compatibility

The upstream package declares support for iOS 15+ and macOS 12+. Rasc targets macOS 14.0. No engine geometry changes were required for macOS compatibility at vendoring time.

### Integration

Rasc consumes ThinkingOrbsKit through a local Swift package reference (`Vendor/ThinkingOrbsKit`) and wraps it in `RascOrb` (`Rasc/UI/RascOrb.swift`) so product code does not depend on third-party state vocabulary directly.

Local presentation extension (4 October 2026): `ThinkingOrb` accepts an optional
SwiftUI `Gradient`. Rasc supplies its violet/orange tint; depth is preserved
through per-element opacity. Default monochrome rendering, engine geometry,
state mapping, speeds and reduced-motion behavior are unchanged. MIT notices
remain intact.
