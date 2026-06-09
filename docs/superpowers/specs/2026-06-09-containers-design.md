# Containers Repo Design

**Date:** 2026-06-09  
**Status:** Approved

## Goal

Centralized repo for building and publishing custom OCI containers to GitHub Container Registry (GHCR). One composable, reusable workflow layer drives any number of containers. First target: a Claude Code CLI container.

---

## Repo Structure

```
containers/
  claude-code/
    Dockerfile
    CHANGELOG.md
    ci/
      values.yaml

.github/
  workflows/
    build.yaml        # reusable: build, push, sign, attest, SBOM
    release.yaml      # reusable: semver bump, changelog, GitHub Release
    pr.yaml           # trigger: lint Dockerfiles, detect changed containers
    schedule.yaml     # trigger: poll upstream versions nightly

scripts/
  check-upstream.sh   # fetch latest upstream version for a container
  update-version.sh   # bump version in values.yaml, stage changelog entry

docs/
  superpowers/specs/
  CONTRIBUTING.md
```

No monorepo tooling required. Pure shell + GitHub Actions matrix.

---

## Container Organization

Flat layout: `containers/<name>/`. Each container is self-contained with its own `Dockerfile`, `CHANGELOG.md`, and `ci/values.yaml`. No category grouping.

---

## Per-Container Metadata

`containers/<name>/ci/values.yaml` defines all build-time and publish-time parameters:

```yaml
container:
  name: claude-code
  image: ghcr.io/<owner>/claude-code

upstream:
  source: npm                          # npm | github
  package: "@anthropic-ai/claude-code"
  version: "1.0.42"                    # auto-updated by schedule workflow

build:
  platforms:
    - linux/amd64
    - linux/arm64
  args:
    NODE_VERSION: lts

labels:
  org.opencontainers.image.title: "claude-code"
  org.opencontainers.image.description: "Containerized Claude Code CLI"
  org.opencontainers.image.source: "https://github.com/<owner>/containers"
  org.opencontainers.image.licenses: "MIT"
```

---

## CI/CD Pipeline

### Nightly version polling (`schedule.yaml`)

```
cron: nightly
  for each container:
    check-upstream.sh → compare upstream version to values.yaml version
    if newer:
      update-version.sh → bumps values.yaml, stages CHANGELOG entry
      opens PR via gh CLI
```

### PR / merge pipeline

```
PR opened:
  pr.yaml:
    - hadolint lint on changed Dockerfiles
    - detect which containers changed (git diff vs base)

PR merged to main:
  build.yaml (reusable, called per changed container):
    - docker buildx build (linux/amd64 + linux/arm64)
    - push to GHCR
    - cosign sign (keyless, GitHub OIDC / Sigstore)
    - syft SBOM generation → cosign attest (spdxjson)
    - slsa-provenance attestation (actions/attest-build-provenance)

  release.yaml (post-build):
    - parse conventional commits scoped to containers/<name>/ since last tag
    - update containers/<name>/CHANGELOG.md (Keep a Changelog format)
    - create GitHub Release tagged <name>-<version>-r<revision>
    - attach SBOM as release artifact
```

### Tags published per build

| Tag | Purpose |
|-----|---------|
| `1.0.42` | Upstream version |
| `1.0.42-r1` | Upstream version + image revision |
| `latest` | Current latest |
| `sha-abc1234` | Git commit SHA |
| `sha256:<digest>` | Immutable digest reference |

---

## Signing, Attestation, SBOM

- **Signing:** Keyless cosign via Sigstore. GitHub OIDC as identity. No long-lived keys.
- **SBOM:** syft generates SPDX JSON, attached to image via `cosign attest --type spdxjson`.
- **Provenance:** `actions/attest-build-provenance` generates SLSA provenance, attached to image.
- **SBOM artifact:** Also uploaded to the GitHub Release.

**Consumer verification:**
```bash
# Pull by immutable digest
docker pull ghcr.io/<owner>/claude-code@sha256:<digest>

# Verify signature and provenance
cosign verify ghcr.io/<owner>/claude-code:1.0.42

# Inspect SBOM
cosign verify-attestation --type spdxjson ghcr.io/<owner>/claude-code:1.0.42 | jq
```

---

## Claude Code Dockerfile

Multi-stage build on `node:lts-alpine`.

```dockerfile
# syntax=docker/dockerfile:1

ARG CLAUDE_CODE_VERSION=latest
ARG NODE_VERSION=lts

# --- builder ---
FROM node:${NODE_VERSION}-alpine AS builder

RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git

RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
    --prefix /usr/local \
    --ignore-scripts=false

# --- runtime ---
FROM node:${NODE_VERSION}-alpine AS runtime

RUN addgroup -S claude && adduser -S claude -G claude

COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=builder /usr/local/bin/claude /usr/local/bin/claude

RUN apk add --no-cache \
    git \
    curl \
    ca-certificates \
    bash

VOLUME ["/home/claude/.claude"]

USER claude
WORKDIR /home/claude

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD claude --version || exit 1

ENTRYPOINT ["claude"]
```

**Best practices applied:**
- Multi-stage build — build tools absent from runtime image
- Non-root user (`claude:claude`)
- Pinned `ARG` versions, overridable at build time
- `VOLUME` for `~/.claude` — credentials, memory, projects persist across restarts
- Explicit `ca-certificates` for TLS
- `HEALTHCHECK` on the binary
- No local context bleed (`COPY . .` absent)

### Initial setup

First run mounts `~/.claude` from the host:

```bash
docker run -it \
  -v ~/.claude:/home/claude/.claude \
  ghcr.io/<owner>/claude-code
```

Claude Code's OAuth/API key setup writes to the mounted volume on first run. Subsequent runs reuse it.

---

## Versioning

- Container image versions track upstream tool versions (e.g. `@anthropic-ai/claude-code@1.0.42` → image tag `1.0.42`)
- Image revisions appended as `-r<n>` for rebuilds of the same upstream version (e.g. base image security update → `1.0.42-r2`)
- Each container is versioned independently
- Changelogs per-container in Keep a Changelog format at `containers/<name>/CHANGELOG.md`
- GitHub Releases tagged `<name>-<version>-r<revision>` (e.g. `claude-code-1.0.42-r1`)

---

## Adding a New Container

1. Create `containers/<name>/Dockerfile`
2. Create `containers/<name>/ci/values.yaml` with upstream source, platforms, labels
3. Create `containers/<name>/CHANGELOG.md` (empty Keep a Changelog scaffold)
4. PR triggers lint + build automatically
5. Schedule workflow picks up upstream polling on next nightly run

No workflow changes required for new containers.

---

## Platforms

All containers target:
- `linux/amd64`
- `linux/arm64`

Built via `docker buildx` with QEMU emulation on GitHub Actions standard runners.

---

## Reference

- Inspired by: [home-operations/containers](https://github.com/home-operations/containers/tree/main/.github)
- cosign: [sigstore/cosign](https://github.com/sigstore/cosign)
- syft: [anchore/syft](https://github.com/anchore/syft)
- SLSA provenance: [actions/attest-build-provenance](https://github.com/actions/attest-build-provenance)
