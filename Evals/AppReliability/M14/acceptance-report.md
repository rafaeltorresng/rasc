# M14 — Maintainer acceptance report

**Date:** 2026-09-22  
**Gate decision:** **A — MAINTAINER ACCEPTED**

## Frozen RC (do not rebuild)

| Field | Value |
|---|---|
| Version | 0.1.0-beta.2 |
| Build | 3 |
| Git commit | `b109a877094fb447ac23debf50a4ab118ac5979a` |
| SHA256 | `5d468eb5358d49084e5b4c19835fab07d73c5d79c182aac5374d255dd71c7d5e` |
| Artifact | `build/rc/Rasc-0.1.0-beta.2.dmg` |
| Freeze record | `build/rc/FROZEN-RC.json` |

M14 verified exactly the M13B packaged artifact. No rebuild. No artifact edits.

## Pre-acceptance verification (unchanged from M13B)

| Check | Result |
|---|---|
| SHA256 integrity | PASS |
| `verify-private-beta.sh` | PASS |
| `verify-rc-bundle.sh` | PASS |
| `smoke-rc-install.sh` | PASS |
| Full test suite (frozen commit) | PASS |
| Crash/log sanity on launch | PASS |

## Manual checklist

Executed per `docs/RC-MANUAL-TEST.md` against packaged RC.  
**Result: PASS** — see `checklist-results.md`.

## Known issues

M13A P2/P3 carried forward. None reproduced as blockers. See `issue-register.md`.

## Short maintainer soak

**Start:** 2026-09-22 (upon acceptance)  
**Duration:** ongoing daily use of frozen `0.1.0-beta.2`

Track only:

- crash, note loss, wrong note opened/mutated
- autosave failure, broken shortcut, focus failure
- destructive Refine, unusable window state
- database/search inconsistency

Do **not** collect feature requests or reopen Refine tuning.

**M14 acceptance session:** no soak defects logged.

## Artifact retention policy

Documented in `docs/RELEASE.md` § Artifact retention. Retain DMG + SHA256 + manifest for each release from beta.2 onward.

## Canonical private beta

**0.1.0-beta.2 (build 3)** is the maintainer-accepted canonical private beta.

- Signing: ad-hoc (Developer ID / notarization unavailable)
- Distribution: private-beta Gatekeeper flow (`docs/PRIVATE-BETA.md`)

## Recommended next product milestone

**M15 — Trusted private beta distribution:** hand the frozen RC to a small trusted cohort using retained artifacts, mailto feedback, and upgrade-from-beta.2 policy. Do not start public launch or new Refine work until distribution feedback is triaged.

Do not implement automatically.
