# Changelog

All notable changes to the omega-mcp container are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.5.4-r1] - 2026-06-23

### Added
- feat(containers): Add new omega memory container

### Added
- feat(omega-mcp): initial OMEGA memory MCP server image served over
  Streamable HTTP for cluster-internal use behind mcpjungle.
- feat(omega-mcp): debian-slim (glibc) base — onnxruntime has no musl wheels,
  so the Alpine pattern used by claude-code cannot be reused.
- feat(omega-mcp): public image carries zero licensed code. Ships an offline
  wheelhouse of OSS `omega-memory[server]` plus the MIT `omega-pro-shim`
  source. The licensed `omega_memory_pro` wheel is fetched at runtime by
  `omega activate`, inside the cluster, gated by the operator's license key.
- feat(omega-mcp): bundle `omega-pro-shim`, which registers the `omega.plugins`
  entry point missing from the upstream Pro wheel so a valid license actually
  unlocks the Pro tools. Tracks omega-memory#63.
- feat(omega-mcp): `omega-init.sh` builds the venv on the PVC, installs OSS
  offline, activates Pro, installs the shim, writes `config.json` with entity
  scoping enabled, and verifies `has_capability("pro_tools")` before success.
- feat(omega-mcp): `omega-serve.sh` runs `omega serve --daemon` (HTTP) as PID 1
  via tini, with the idle-shutdown timer disabled for a long-lived Deployment.
