# Home logo verification — 0.1.1 / build 7

The identity symbol keeps the original silhouette and colors. Home uses the
compact 24pt logo with 24px/48px representations in both appearances. The native
SwiftUI component was rendered in light/dark at both display scales; PNG proofs
and the alpha/scale audit are alongside this file.

Release build, DMG verification and RC bundle verification passed. The package
is arm64, ad-hoc signed, sandboxed and not notarized. Domain verification passed
281 tests across 22 suites. Full Xcode testing could not launch RascTests because
LaunchServices rejected the runner; no full native-suite pass is claimed.

The installed bundle at /Applications/Rasc.app is 0.1.1/build 7, checked after
replacement and code-signature verification. The previous installed app is
retained under build/retained-installations/Rasc-0.1.0-build6.app. User data was
not copied, reset or imported into capture assets.

An isolated copy of this Release was used to refresh the website Home capture.
Its only notes are the synthetic fixtures from the original capture session.
The new native PNG contains the larger logo and no inspection-tool overlays.
Scratchpad/Refine UI is unchanged, so their existing native captures are retained.

The v0.1.1 publication uses the verified artifact described above. Public v0.1.0
is retained unchanged. CI results and the release source revision are linked
from the GitHub release page.
