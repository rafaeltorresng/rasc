# Local assistant access feasibility

**Decision for the current distribution model: No-Go for production live access.**
A native Swift stdio server is small enough to explore. The remaining release
boundary is a client-launched, constrained helper that can discover and
authenticate the sandboxed Rasc process after installation and replacement.

The November 2026 spike used an Apple silicon Mac running macOS 26.5.1, Xcode 26.2,
and synthetic notes in isolated processes. The prototype never opened the
installed app's database. No MCP code, services, permissions, Settings, or
network entitlements are added to the shipping target.

The [standalone prototype](../Experiments/LocalMCP/README.md) preserves the
Swift package, controls, binary bundle manifest and paired smoke runner. The
runner passed on this Mac in the PR review, before and after replacing the
signed fixture at its original path.

## Observed

| Check | Result |
| --- | --- |
| Swift SDK 0.12.1 and stdio | An arm64 Release helper built for macOS 14. A deterministic JSON-RPC client negotiated 2025-11-25, listed exactly `search_thoughts` and `get_thought`, received the matching fixture, and received an unavailable response for an unshared ID. The helper exited on stdin closure. |
| Claude Code 2.1.126 | `mcp list` reported Connected for the actual stdio helper, using a temporary Claude configuration. Model-driven retrieval hit an expired OAuth session. |
| Codex 0.169.0 | The raw Swift SDK rejected one initialization path. The client sent an object-valued optional experimental capability and the SDK tag decodes those values as strings. A spike-only shim removed that unused capability. Codex app-server then called both tools and returned the synthetic thought. The shim is evidence for an SDK compatibility fix. |
| Claude Desktop | The official MCP Bundle tool validated and packaged the ad-hoc signed native fixture as a binary `.mcpb`. Installation, tool execution, and removal in the desktop client remain unverified. |
| Cursor 3.30.14 | The isolated workspace discovered the project server. The client also loaded its user-wide configuration. The spike stopped short of executing tools in that session. |
| Anonymous XPC | In a signed sandboxed control process, a matching code hash succeeded, an incorrect peer requirement was rejected, and revoking the allowlist blocked a read over an already open connection. The endpoint was handed to the client in the same process. Secure cross-process endpoint discovery was outside that control. |
| Named XPC and Core Foundation Mach port | A normal named `NSXPCListener` attempt did not yield a reachable service for a separate client. A sandboxed app registered a `CFMessagePort`. A hardened ad-hoc helper reached it with an exact Mach lookup entitlement when packaged as its own sandboxed app bundle. A control bundle without the entitlement completed stdio initialization but could not look up the port. The same helpers signed as bare executables failed before replying to stdio initialization. |
| Authenticated cross-process control | Both sandboxed peers exchanged authenticated, encrypted messages over the Mach port with a prearranged, ephemeral test key. Only the allowlisted synthetic thought was returned. A second process using the wrong key received no content. Revoking the grant blocked reads in an already open stdio session. Key possession is the tested identity. Secure user pairing, authenticated discovery of the installed app, and key custody across updates still need proof. |
| Distribution | Verified the public v0.1.14 DMG checksum and inspected its app signature and entitlements. It is ad-hoc with no Team ID and no MCP helper. The probe sealed a nested helper under `Contents/Helpers` in two ad-hoc signed fixture builds. The authentication checks passed before and after manually replacing the fixture at the same launch path. The harness provided a fresh key for each run. Real client installation, retained pairing, and Sparkle update behavior remain open. |

The installed Swift SDK version and the supported draft protocol are separate
questions. Verify initialization and tool calls with each target client when
choosing a pinned SDK. Preserve a bounded, server-side allowlist and an identical
response for unshared and missing note IDs.

- [Swift SDK 0.12.1](https://github.com/modelcontextprotocol/swift-sdk/releases/tag/0.12.1)
- [Swift SDK client capabilities](https://github.com/modelcontextprotocol/swift-sdk/blob/0.12.1/Sources/MCP/Client/Client.swift)
- [Apple XPC listener requirements](https://developer.apple.com/documentation/foundation/nsxpclistener/setconnectioncodesigningrequirement(_:))
- [Apple App Groups and signing](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)
- [MCP Bundle specification](https://github.com/modelcontextprotocol/mcpb/blob/main/MANIFEST.md)

## Options from here

- **Selected exports** already give a user a narrow, inspectable set of
  thoughts for a file-capable assistant, including images. The file recipient
  can retain its copies. The Rasc sandbox and original database stay private.
- **Live stdio with app-owned access** remains the target if demand justifies
  it. Start with the proven sandboxed app-bundle helper, a single Mach lookup
  name, and a reply authenticated to each request. Prove secure user pairing
  and durable, narrowly scoped key storage on the oldest supported and current
  macOS. Keep the Mach service name public and reject any request missing a valid
  grant. Avoid launch arguments, environment variables, or config files for
  production keys.
  Validate a clean installation, a Sparkle update, unauthorized peer
  replacement, and revocation during an in-progress request. Ad-hoc code hashes
  pin exact builds. A legitimate replacement also changes that identity,
  so an update needs a verified handoff rather than a broad identifier match.
- **Developer ID and an App Group projection** are a separate distribution
  decision. A narrowly scoped projection might support offline retrieval.
  It adds a second store and a freshness and deletion contract. The original
  SQLite store belongs to Rasc.
- **An app-open link** can eventually be a citation. The exported UUID is stable
  across edits and exports. An exact UUID in a URL could route to the repository's
  existing non-discarded lookup, then open the Scratchpad locally. Validate the
  scheme, path and UUID, and treat it as an open action with no content in the
  URL or response. Treat any inbound draft flow as a visible handoff for user
  review.

Claude Desktop bundle installation, end-to-end Cursor tool calls, macOS 14 and 15,
clean-machine Gatekeeper behavior, and continuity through a normal Sparkle update
remain release gates. A generic file export continues to work with Rasc quit.
