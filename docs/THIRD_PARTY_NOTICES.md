# Third-Party Notices

## ThinkingOrbsKit

Rasc vendors a local copy of **ThinkingOrbsKit** from the Libraries.dev monorepo as a retained dependency. The Orb is no longer displayed in the interface.

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
SwiftUI `Gradient`. The historical wrapper supplies its violet/orange tint; depth is preserved
through per-element opacity. Default monochrome rendering, engine geometry,
state mapping, speeds and reduced-motion behavior are unchanged. MIT notices
remain intact.

## GRDB and KeyboardShortcuts

Resolved Swift packages are GRDB **7.11.1** (commit `b83108d10f42680d78f23fe4d4d80fc88dab3212`) and KeyboardShortcuts **3.0.1** (commit `49c3fc04ea827f816df67843bfcc57286b47ff06`). Their MIT license texts are reproduced verbatim in `Rasc/Resources/ThirdPartyNotices.txt`, included in the app bundle.

- GRDB: https://github.com/groue/GRDB.swift — upstream `LICENSE`; copyright Gwendal Roué.
- KeyboardShortcuts: https://github.com/sindresorhus/KeyboardShortcuts — upstream `license`; copyright Sindre Sorhus.

When updating a dependency, review its license and update the bundled notice along with `Package.resolved`. SQLite's upstream source identifies its code as public domain; see GRDB's SQLite distribution license.

## Voice Capture

Rasc uses the [FluidAudio maintainer fork](https://github.com/altic-dev/FluidAudio/tree/386f7195670b77f2954c7ee143ec63fcb50b6c3b) (Apache 2.0) for local inference. The Xcode lockfile pins the Swift dependency graph. Runtime and applicable dependency notices appear in the bundled `ThirdPartyNotices.txt`.

The optional `VoiceModel` folder contains the unchanged INT8 [Fluid Speech Pro Core ML components](https://huggingface.co/FluidVoice-Labs/fluid-speech-pro-coreml/tree/3b9d38a93d606f84011e5a0a669b7ea146375a22) by FluidVoice Labs, derived from [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3). Both are licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Rasc pins the converted assets by revision, size and SHA-256.
