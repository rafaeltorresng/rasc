# Rasc 0.1.1 — Home identity refinement

Version: 0.1.1 · build 7 · Apple silicon · macOS 14+

- Home now uses dedicated 1×/Retina 2× symbol exports at 24 pt.
- The symbol shape and colors are preserved; onboarding retains the existing large logo.
- Capture, Refine, Keep, Home and Search behavior is unchanged.

This release is ad-hoc signed and **not notarized**. Follow
[the unsigned install guide](INSTALL-UNSIGNED.md) for the first launch.
Refine remains optional and needs macOS 26+ with Apple Intelligence enabled.

## Release verification

DMG SHA-256:
`812323655859a5389cbd872075e81bc51509084ac14966c6a293911b5b383973`.
Release build, bundle checks and 281 domain tests passed. Native Xcode testing
was blocked by LaunchServices failing to launch RascTests. The `v0.1.1` tag identifies the source revision used for this artifact. The v0.1.0 release is retained unchanged.
