# containers

Custom OCI container images published to GitHub Container Registry.

## Images

| Container | Image | Description |
|-----------|-------|-------------|
| claude-code | `ghcr.io/j0sh3rs/claude-code` | Claude Code CLI |
| omega-mcp | `ghcr.io/j0sh3rs/omega-mcp` | OMEGA persistent-memory MCP server (Streamable HTTP) |

## Usage

```bash
# Pull by tag
docker pull ghcr.io/j0sh3rs/claude-code:latest

# Pull by immutable digest (recommended)
docker pull ghcr.io/j0sh3rs/claude-code@sha256:<digest>

# Run with persistent config
docker run -it \
  -v ~/.claude:/home/claude/.claude \
  ghcr.io/j0sh3rs/claude-code
```

### Hardened run

The image already runs as a non-root user (`claude`) with a `tini` init and no
build toolchain. For defense in depth, add runtime flags that cannot be baked
into the image:

```bash
docker run -it \
  --read-only \
  --tmpfs /tmp \
  --security-opt no-new-privileges \
  --cap-drop ALL \
  -v ~/.claude:/home/claude/.claude \
  ghcr.io/j0sh3rs/claude-code
```

- `--read-only` + `--tmpfs /tmp` — immutable root filesystem; the mounted
  `~/.claude` volume stays writable.
- `--security-opt no-new-privileges` — blocks setuid privilege escalation.
- `--cap-drop ALL` — Claude needs no Linux capabilities for normal use.

## Verification

```bash
# Verify image signature
cosign verify ghcr.io/j0sh3rs/claude-code:latest \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp "https://github.com/j0sh3rs/containers"

# Inspect SBOM attestation
cosign verify-attestation --type spdxjson \
  ghcr.io/j0sh3rs/claude-code:latest | jq '.payload | @base64d | fromjson'

# Verify GitHub provenance
gh attestation verify oci://ghcr.io/j0sh3rs/claude-code:latest \
  --repo j0sh3rs/containers
```

## omega-mcp

OMEGA persistent-memory MCP server, built for cluster-internal use behind
[mcpjungle](https://github.com/mcpjungle/mcpjungle). Deployed via Flux in
`j0sh3rs/home-ops` (`kubernetes/apps/ai/omega-mcp`); registered as a
`streamable_http` upstream at `http://omega-mcp:8377/mcp`.

Design notes:

- **uv on a glibc base** (`ghcr.io/astral-sh/uv:*-python3.14-trixie-slim`).
  Alpine is not usable here: `onnxruntime` and `sqlite-vec` publish manylinux
  wheels only (no musllinux), so a musl base would force a source build.
- **Zero licensed code in the image.** It ships an offline wheelhouse of OSS
  `omega-memory[full]` plus a pre-built wheel of the MIT capability shim. The
  licensed `omega_memory_pro` wheel is fetched at runtime by `omega activate`,
  inside the cluster, gated by the operator's license key.
- **Capability shim** registers the `omega.plugins` entry point that the
  upstream Pro wheel forgets, so a valid license actually unlocks the Pro tools
  (upstream bug: [omega-memory#63](https://github.com/omega-memory/omega-memory/issues/63)).
- **PVC-resident venv + model.** `HOME=/data` keeps the venv, SQLite DB,
  license, and the bge-small ONNX embedding model on the PVC so they survive
  restarts and the model is not re-downloaded.

```bash
# Run standalone (memory + model persist in the mounted volume)
docker run -d \
  -e OMEGA_LICENSE_KEY="OMEGA-PRO-..." \
  -v omega-data:/data \
  -p 8377:8377 \
  ghcr.io/j0sh3rs/omega-mcp
```

The same signature / SBOM / provenance verification shown above applies, with
`claude-code` swapped for `omega-mcp` in the image reference.

## Version Management

Two disjoint updaters, by container:

- **claude-code** — `scripts/check-upstream.sh` (npm source) driven by the
  daily `schedule.yaml` workflow.
- **omega-mcp** — **Renovate** (`.github/renovate.json5`). The upstream script
  only supports `npm`/`github` sources, not `pypi`, so Renovate owns the
  `omega-memory` wheel version (annotated in the Dockerfile and matched in
  `ci/values.yaml`), the uv version, and the python base. The two updaters are
  kept from overlapping via Renovate's `ignorePaths`.

## Adding a Container

See [CONTRIBUTING.md](CONTRIBUTING.md) or run:

```bash
gh workflow run scaffold.yaml \
  -f name=my-tool \
  -f upstream_source=npm \
  -f upstream_package="@scope/my-tool" \
  -f initial_version="1.0.0" \
  -f description="My tool container"
```
