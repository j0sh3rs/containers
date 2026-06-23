# Changelog

All notable changes to the omega-mcp container are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.5.4-r1] - 2026-06-23

### Added
- feat(omega): Bump to UV + Python 3.14, omega-full

## [1.5.4-r1] - 2026-06-23

### Added
- feat(containers): Add new omega memory container

### Added
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
