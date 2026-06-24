# Changelog

All notable changes to the omega-mcp container are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.5.4-r3] - 2026-06-24

### Fixed
- fix(omega): Drop shim now that upstream is fixed

### Removed
- feat(omega-mcp): remove the local `omega-pro-shim`. Upstream fixed the missing
  `omega.plugins` entry point in the 1.5.4 Pro customer wheel on 2026-06-24
  (omega-memory#63); the vendor wheel now ships its own `omega_pro` entry point,
  so the bridge is no longer needed. Dropped the shim build from the wheelhouse
  stage and the `omega-pro-shim` install from `omega-init.sh`.

### Fixed
- fix(omega-mcp): heal stale PVCs onto the fixed Pro wheel. The vendor
  republished the fix IN PLACE as `omega_memory_pro-1.5.4` (same version), so
  `omega activate` would not redownload it on a PVC holding the old buggy build.
  `omega-init.sh` now detects a Pro install lacking the `omega_pro` entry point
  and uninstalls it before activation, forcing a one-time redownload of the
  fixed wheel.
- fix(omega-mcp): verify the upstream `omega_pro` entry point in init step 6, in
  addition to `has_capability("pro_tools")`, so a surviving stale wheel fails
  the initContainer loudly instead of serving with Pro tools dark.
- fix(omega-mcp): rebuild the PVC venv when it lacks the `omega` CLI. A venv that
  was python-version-matched but incomplete (e.g. from an older image layout)
  passed the reuse gate, no-op'd through the offline install ("Checked 1
  package"), then died at `omega activate` with `omega: command not found`. The
  reuse gate now also requires `bin/omega` and rebuilds clean if it is absent.
- fix(omega-mcp): make wheelhouse version authoritative on reused PVCs. The
  unpinned `omega-memory[full]` install reported "satisfied" against any older
  version already in the venv, so a newer image never actually upgraded the
  running venv. Added `--upgrade` so the image's pinned OSS closure wins.
- fix(omega-mcp): assert `bin/omega` exists immediately after install and fail
  loud there, rather than 30 lines later at `omega activate`.

## [1.5.4-r2] - 2026-06-23

### Added
- feat(ci): Add renovate and update Readme
- feat(omega): Bump to UV + Python 3.14, omega-full

### Fixed
- fix(ci): self-incrementing image revisions and idempotent changelog
- fix(omega-mcp): alias uv image as stage to fix COPY --from var expansion
- fix(omega-mcp): rebuild PVC venv on python interpreter mismatch

### Changed
- chore(omega-mcp): changelog omega-mcp-1.5.4-r1
- chore(omega-mcp): changelog omega-mcp-1.5.4-r1
- chore(omega-mcp): changelog omega-mcp-1.5.4-r1

<!--
The next push that touches containers/omega-mcp/ will auto-generate a
[1.5.4-r2] section here from conventional-commit subjects since the
omega-mcp-1.5.4-r1 tag. Pending since r1:
  - feat(ci): Add renovate and update Readme
  - feat(omega): Bump to UV + Python 3.14, omega-full
  - fix(omega-mcp): alias uv image as stage to fix COPY --from var expansion
  - fix(omega-mcp): rebuild PVC venv on python interpreter mismatch
-->

## [1.5.4-r1] - 2026-06-23

### Added
- feat(containers): Add new omega memory container
- feat(omega-mcp): initial OMEGA memory MCP server image served over
  Streamable HTTP for cluster-internal use behind mcpjungle.
- feat(omega-mcp): uv-based build on a glibc base (`ghcr.io/astral-sh/uv:
  0.11.23-python3.14-trixie-slim`). Alpine was evaluated and rejected:
  onnxruntime 1.27.0 and sqlite-vec 0.1.9 publish manylinux wheels only (zero
  musllinux), so a musl base would force a multi-hour onnxruntime source build.
  uv installs the same PyPI artifacts as pip — it cannot supply musl wheels —
  so glibc stays. The venv is created with `uv venv --seed` (pip is required by
  `omega activate`) and deps install via `uv pip install`.
- feat(omega-mcp): public image carries zero licensed code. Ships an offline
  wheelhouse of OSS `omega-memory[full]` plus a pre-built wheel of the MIT
  `omega-pro-shim`. The licensed `omega_memory_pro` wheel is fetched at runtime
  by `omega activate`, inside the cluster, gated by the operator's license key.
- feat(omega-mcp): install `omega-memory[full]` (server + encrypt extras) so the
  Profile module's AES-256-GCM/keyring store is available alongside coordination,
  router, knowledge, entity, and oracle.
- feat(omega-mcp): bundle `omega-pro-shim`, which registers the `omega.plugins`
  entry point missing from the upstream Pro wheel so a valid license actually
  unlocks the Pro tools. Tracks omega-memory#63.
- feat(omega-mcp): ship the shim as a PRE-BUILT wheel (built in the wheelhouse
  stage). A runtime source install wrote egg-info into the root-owned source dir
  and failed EACCES under uid 1024 — the wheel install side-steps that.
- feat(omega-mcp): `omega-init.sh` builds the venv on the PVC, installs the full
  OSS set + shim offline, activates Pro, downloads the bge ONNX model onto the
  PVC, writes `config.json` with entity scoping enabled, and verifies
  sqlite-vec, onnxruntime, the ONNX model, and `has_capability("pro_tools")`
  before success.
- feat(omega-mcp): pin `HOME=/data` in both scripts. OMEGA hardcodes its model
  and cache paths to `Path.home()`, so HOME — not `OMEGA_ONNX_MODEL_DIR` — is the
  only lever that keeps the embedding model on the PVC and prevents a ~130MB
  re-download on every pod restart.
- feat(omega-mcp): `omega-serve.sh` runs `omega serve --daemon` (HTTP) as PID 1
  via tini, with the idle-shutdown timer disabled for a long-lived Deployment.
