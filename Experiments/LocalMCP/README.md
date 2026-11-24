# Local MCP feasibility prototype

This standalone Swift package contains synthetic fixtures for the
[local MCP feasibility report](../../docs/LOCAL-MCP-FEASIBILITY.md). The Rasc
Xcode project, CI, updater, and release scripts do not build or embed this
package. It does not read Rasc's database or use local client settings.

## Reproduce the paired smoke test

On macOS with Xcode 26.2 and Python 3 installed, run:

```sh
bash Experiments/LocalMCP/run-paired-smoke.sh
```

The script builds the pinned Swift MCP SDK and the stdio helper, then
ad-hoc signs and runs a fixture host and nested helper in temporary app bundles.
It verifies search, scoped retrieval, rejection of a wrong key, revocation
while the connection stays open, and exit on stdin closure. It repeats the check
after replacing the signed fixture bundle at the same path. Each run generates
a fresh, temporary test key. Stop any previous instance of this prototype first
because it uses a fixed Mach service name.

The test environment passes the synthetic key through process environments.
The host accepts only the fixed fixture ID, and SIGUSR1 revokes its grant.
Production key custody, installation, and authorization continuity are still
unresolved.

## Other controls

- `Sources/RascMCPProbe` includes a `--fixture` mode for testing SDK negotiation
  without the host. Its `--mach` mode relays to the named fixture port.
- `Controls/MachProbe.swift` is the deliberately unauthenticated fixture used
  to compare Mach registration and sandbox lookup. It returns synthetic data.
- `Controls/XPCProbe.swift` exercises an anonymous endpoint, code requirements,
  and revocation in-process. `Controls/XPCNamedProbe.swift` is the separate named
  endpoint comparison.
- `MCPBundle/manifest.json` is the binary bundle manifest used for packaging
  validation. Put the fixture executable at `MCPBundle/server/RascMCPProbe` to
  run the official MCP Bundle packaging tool against it.
