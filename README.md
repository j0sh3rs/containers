# containers

Custom OCI container images published to GitHub Container Registry.

## Images

| Container | Image | Description |
|-----------|-------|-------------|
| claude-code | `ghcr.io/j0sh3rs/claude-code` | Claude Code CLI |

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
