# Containers Repo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a centralized container build repo that publishes signed, attested, SBOM-tagged OCI images to GHCR via reusable GitHub Actions workflows, with the Claude Code CLI as the first container.

**Architecture:** Flat `containers/<name>/` layout; one set of reusable `workflow_call` workflows drive all builds; a `push.yaml` caller detects changed containers on merge to main and dispatches to build+release; a nightly schedule polls upstream versions and opens PRs automatically.

**Tech Stack:** GitHub Actions, Docker Buildx, GHCR, cosign (keyless/Sigstore), `docker/build-push-action` (native SBOM+provenance), `actions/attest-build-provenance`, hadolint, actionlint, shellcheck, node:lts-alpine

---

## File Map

| File | Responsibility |
|------|---------------|
| `containers/claude-code/Dockerfile` | Multi-stage Claude Code CLI image |
| `containers/claude-code/ci/values.yaml` | Build metadata, upstream version source |
| `containers/claude-code/CHANGELOG.md` | Per-container Keep a Changelog log |
| `scripts/check-upstream.sh` | Fetch latest upstream version for a container |
| `scripts/update-version.sh` | Bump version in values.yaml |
| `.github/workflows/build.yaml` | Reusable: buildx, push to GHCR, sign, SBOM, attest |
| `.github/workflows/release.yaml` | Reusable: parse commits, update CHANGELOG, GitHub Release |
| `.github/workflows/pr.yaml` | Trigger on PR: hadolint lint, change detection |
| `.github/workflows/push.yaml` | Trigger on push to main: detect changes, call build+release |
| `.github/workflows/schedule.yaml` | Nightly: check upstream versions, open PRs |
| `.github/workflows/scaffold.yaml` | workflow_dispatch: scaffold new container from inputs |
| `CONTRIBUTING.md` | Contributor guide, how to add containers |
| `README.md` | Repo overview, usage, verification commands |

---

## Task 1: Repo Bootstrap

**Files:**
- Create: `README.md`
- Create: `CONTRIBUTING.md`
- Create: `.gitignore`

- [ ] **Step 1: Create .gitignore**

```
# .gitignore
.DS_Store
*.swp
*.swo
.env
```

- [ ] **Step 2: Create README.md**

````markdown
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
# Via GitHub Actions workflow dispatch (CLI)
gh workflow run scaffold.yaml \
  -f name=my-tool \
  -f upstream_source=npm \
  -f upstream_package="@scope/my-tool" \
  -f initial_version="1.0.0" \
  -f description="My tool container"
```
````

- [ ] **Step 3: Create CONTRIBUTING.md**

````markdown
# Contributing

## Adding a New Container

### Option A: Workflow Dispatch (recommended)

```bash
gh workflow run scaffold.yaml \
  -f name=<container-name> \
  -f upstream_source=npm|github \
  -f upstream_package="<package-or-owner/repo>" \
  -f initial_version="<version>" \
  -f description="<description>"
```

### Option B: Manual

1. Create `containers/<name>/Dockerfile`
2. Create `containers/<name>/ci/values.yaml` (copy from `containers/claude-code/ci/values.yaml` and edit)
3. Create `containers/<name>/CHANGELOG.md` (see scaffold below)
4. Open a PR — lint and build run automatically

### values.yaml fields

| Field | Description |
|-------|-------------|
| `container.name` | Container directory name |
| `container.image` | Full GHCR image path |
| `upstream.source` | `npm` or `github` |
| `upstream.package` | npm package name or `owner/repo` |
| `upstream.version` | Current tracked version (auto-updated by nightly schedule) |
| `build.platforms` | Target platforms (default: linux/amd64, linux/arm64) |
| `build.args` | Docker build-args passed at build time |
| `labels` | OCI image labels |

## Commit Convention

This repo uses [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` — new feature or new container
- `fix:` — bug fix or container fix
- `chore:` — maintenance
- `ci:` — workflow changes
- `docs:` — documentation

Scope to a container with `feat(claude-code):` for per-container changelog entries.

## Version Bumps

Container versions track upstream. The nightly schedule auto-opens PRs when a new upstream version is detected. To manually bump:

```bash
./scripts/update-version.sh <container-name> <new-version>
```
````

- [ ] **Step 4: Commit**

```bash
git add README.md CONTRIBUTING.md .gitignore
git commit -m "chore: bootstrap repo with README and CONTRIBUTING"
```

---

## Task 2: Claude Code Dockerfile

**Files:**
- Create: `containers/claude-code/Dockerfile`

- [ ] **Step 1: Verify hadolint is available (or install)**

```bash
which hadolint || brew install hadolint
hadolint --version
```

Expected: `Haskell Dockerfile Linter v2.x.x`

- [ ] **Step 2: Create the Dockerfile**

```dockerfile
# syntax=docker/dockerfile:1

ARG NODE_VERSION=lts
ARG CLAUDE_CODE_VERSION=latest

# --- builder: install claude-code with native build deps ---
FROM node:${NODE_VERSION}-alpine AS builder

RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git

RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
    --prefix /usr/local \
    --ignore-scripts=false

# --- runtime: minimal image without build toolchain ---
FROM node:${NODE_VERSION}-alpine AS runtime

# Create non-root user
RUN addgroup -S claude && adduser -S claude -G claude

# Copy only the installed CLI artifacts from builder
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=builder /usr/local/bin/claude /usr/local/bin/claude

# Runtime dependencies only
RUN apk add --no-cache \
    git \
    curl \
    ca-certificates \
    bash

# Mount point for ~/.claude (credentials, memory, project context)
VOLUME ["/home/claude/.claude"]

USER claude
WORKDIR /home/claude

# Verify binary is functional
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD claude --version || exit 1

ENTRYPOINT ["claude"]
```

- [ ] **Step 3: Lint with hadolint**

```bash
hadolint containers/claude-code/Dockerfile
```

Expected: no output (zero findings). If findings appear, address them — common fixes:
- `DL3018`: add `--no-cache` to `apk add` (already included)
- `DL3016`: pin npm package versions (already done via `CLAUDE_CODE_VERSION` ARG)

- [ ] **Step 4: Build locally to verify**

```bash
docker build \
  --build-arg CLAUDE_CODE_VERSION=latest \
  --build-arg NODE_VERSION=lts \
  -t claude-code:local \
  containers/claude-code/
```

Expected: successful multi-stage build, final image from `runtime` stage.

- [ ] **Step 5: Smoke test the image**

```bash
docker run --rm claude-code:local --version
```

Expected: output like `claude-code/1.x.x linux-x64 node-v22.x.x`

- [ ] **Step 6: Commit**

```bash
git add containers/claude-code/Dockerfile
git commit -m "feat(claude-code): add multi-stage Alpine Dockerfile"
```

---

## Task 3: Claude Code Container Metadata

**Files:**
- Create: `containers/claude-code/ci/values.yaml`
- Create: `containers/claude-code/CHANGELOG.md`

- [ ] **Step 1: Get current claude-code npm version**

```bash
npm view @anthropic-ai/claude-code version
```

Note the version returned (e.g. `1.0.42`) — use it in the next step.

- [ ] **Step 2: Create values.yaml**

Replace `<CURRENT_VERSION>` with the version from Step 1.

```yaml
container:
  name: claude-code
  image: ghcr.io/j0sh3rs/claude-code

upstream:
  source: npm
  package: "@anthropic-ai/claude-code"
  version: "<CURRENT_VERSION>"

build:
  platforms:
    - linux/amd64
    - linux/arm64
  args:
    NODE_VERSION: lts

labels:
  org.opencontainers.image.title: "claude-code"
  org.opencontainers.image.description: "Containerized Claude Code CLI"
  org.opencontainers.image.source: "https://github.com/j0sh3rs/containers"
  org.opencontainers.image.licenses: "MIT"
```

- [ ] **Step 3: Create CHANGELOG.md**

```markdown
# Changelog

All notable changes to the claude-code container are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]
```

- [ ] **Step 4: Commit**

```bash
git add containers/claude-code/ci/values.yaml containers/claude-code/CHANGELOG.md
git commit -m "feat(claude-code): add container metadata and empty changelog"
```

---

## Task 4: Upstream Version Scripts

**Files:**
- Create: `scripts/check-upstream.sh`
- Create: `scripts/update-version.sh`

- [ ] **Step 1: Verify shellcheck is available**

```bash
which shellcheck || brew install shellcheck
shellcheck --version
```

Expected: `ShellCheck, version 0.x.x`

- [ ] **Step 2: Create scripts/check-upstream.sh**

```bash
#!/usr/bin/env bash
# Usage: ./scripts/check-upstream.sh <container-name>
# Prints the latest upstream version to stdout.
# Exits non-zero on error.

set -euo pipefail

CONTAINER="${1:?Usage: check-upstream.sh <container-name>}"
VALUES="containers/${CONTAINER}/ci/values.yaml"

if [[ ! -f "$VALUES" ]]; then
  echo "ERROR: ${VALUES} not found" >&2
  exit 1
fi

# Parse YAML fields (simple grep — no yq dependency)
SOURCE=$(grep '^  source:' "$VALUES" | awk '{print $2}')
PACKAGE=$(grep '^  package:' "$VALUES" | awk '{print $2}' | tr -d '"')

case "$SOURCE" in
  npm)
    npm view "$PACKAGE" version 2>/dev/null
    ;;
  github)
    # PACKAGE format: owner/repo
    curl -fsSL "https://api.github.com/repos/${PACKAGE}/releases/latest" \
      | grep '"tag_name"' \
      | head -1 \
      | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' \
      | sed 's/^v//'
    ;;
  *)
    echo "ERROR: Unknown upstream source '${SOURCE}'" >&2
    exit 1
    ;;
esac
```

- [ ] **Step 3: Create scripts/update-version.sh**

```bash
#!/usr/bin/env bash
# Usage: ./scripts/update-version.sh <container-name> <new-version>
# Updates the version field in containers/<name>/ci/values.yaml.

set -euo pipefail

CONTAINER="${1:?Usage: update-version.sh <container-name> <new-version>}"
NEW_VERSION="${2:?Usage: update-version.sh <container-name> <new-version>}"
VALUES="containers/${CONTAINER}/ci/values.yaml"

if [[ ! -f "$VALUES" ]]; then
  echo "ERROR: ${VALUES} not found" >&2
  exit 1
fi

CURRENT=$(grep '^  version:' "$VALUES" | awk '{print $2}' | tr -d '"')

if [[ "$CURRENT" == "$NEW_VERSION" ]]; then
  echo "Already at version ${NEW_VERSION}, nothing to do."
  exit 0
fi

# In-place sed that works on both macOS and Linux
if sed --version 2>/dev/null | grep -q GNU; then
  sed -i "s/^  version: \".*\"/  version: \"${NEW_VERSION}\"/" "$VALUES"
else
  sed -i '' "s/^  version: \".*\"/  version: \"${NEW_VERSION}\"/" "$VALUES"
fi

echo "Updated ${CONTAINER}: ${CURRENT} → ${NEW_VERSION}"
```

- [ ] **Step 4: Make scripts executable**

```bash
chmod +x scripts/check-upstream.sh scripts/update-version.sh
```

- [ ] **Step 5: Lint with shellcheck**

```bash
shellcheck scripts/check-upstream.sh scripts/update-version.sh
```

Expected: no output (zero findings).

- [ ] **Step 6: Test check-upstream.sh**

```bash
./scripts/check-upstream.sh claude-code
```

Expected: a semver string like `1.0.42`.

- [ ] **Step 7: Test update-version.sh (dry run with revert)**

```bash
./scripts/update-version.sh claude-code 99.99.99
grep 'version:' containers/claude-code/ci/values.yaml

# revert
./scripts/update-version.sh claude-code "$(npm view @anthropic-ai/claude-code version)"
grep 'version:' containers/claude-code/ci/values.yaml
```

Expected: version changes to `99.99.99` then back to current.

- [ ] **Step 8: Commit**

```bash
git add scripts/check-upstream.sh scripts/update-version.sh
git commit -m "feat: add upstream version check and update scripts"
```

---

## Task 5: PR Workflow

**Files:**
- Create: `.github/workflows/pr.yaml`

- [ ] **Step 1: Verify actionlint is available**

```bash
which actionlint || brew install actionlint
actionlint --version
```

Expected: `actionlint 1.x.x`

- [ ] **Step 2: Create .github/workflows/pr.yaml**

```yaml
name: PR Checks

on:
  pull_request:
    branches:
      - main

jobs:
  detect-changes:
    name: Detect changed containers
    runs-on: ubuntu-latest
    outputs:
      containers: ${{ steps.changes.outputs.containers }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Detect changed container directories
        id: changes
        run: |
          CHANGED=$(git diff --name-only "origin/${{ github.base_ref }}...HEAD" \
            | grep '^containers/' \
            | cut -d/ -f2 \
            | sort -u \
            | jq -R -s -c 'split("\n") | map(select(length > 0))')
          echo "containers=${CHANGED}" >> "$GITHUB_OUTPUT"
          echo "Changed containers: ${CHANGED}"

  lint:
    name: Lint ${{ matrix.container }} Dockerfile
    needs: detect-changes
    if: needs.detect-changes.outputs.containers != '[]' && needs.detect-changes.outputs.containers != ''
    runs-on: ubuntu-latest
    strategy:
      matrix:
        container: ${{ fromJson(needs.detect-changes.outputs.containers) }}
      fail-fast: false
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Lint Dockerfile with hadolint
        uses: hadolint/hadolint-action@v3.1.0
        with:
          dockerfile: containers/${{ matrix.container }}/Dockerfile
          failure-threshold: warning

  lint-workflows:
    name: Lint GitHub Actions workflows
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Lint workflow files with actionlint
        uses: raven-actions/actionlint@v2

  lint-scripts:
    name: Lint shell scripts
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Lint scripts with shellcheck
        uses: ludeeus/action-shellcheck@2.0.0
        with:
          scandir: ./scripts
```

- [ ] **Step 3: Validate with actionlint**

```bash
actionlint .github/workflows/pr.yaml
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
mkdir -p .github/workflows
git add .github/workflows/pr.yaml
git commit -m "ci: add PR workflow for Dockerfile and script linting"
```

---

## Task 6: Reusable Build Workflow

**Files:**
- Create: `.github/workflows/build.yaml`

This is the core reusable workflow. Called by `push.yaml` on merge to main.

- [ ] **Step 1: Create .github/workflows/build.yaml**

```yaml
name: Build Container

on:
  workflow_call:
    inputs:
      container:
        description: "Container name (directory under containers/)"
        required: true
        type: string
      version:
        description: "Upstream version to tag the image"
        required: true
        type: string
      revision:
        description: "Image revision (increments on rebuild of same version)"
        required: false
        type: string
        default: "1"
    outputs:
      digest:
        description: "Image digest (sha256:...)"
        value: ${{ jobs.build.outputs.digest }}
      image:
        description: "Full image reference with digest"
        value: ${{ jobs.build.outputs.image }}

jobs:
  build:
    name: Build ${{ inputs.container }}
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      id-token: write      # keyless cosign signing via OIDC
      attestations: write  # actions/attest-build-provenance
    outputs:
      digest: ${{ steps.build.outputs.digest }}
      image: ${{ steps.meta.outputs.tags }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Generate image metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository_owner }}/${{ inputs.container }}
          tags: |
            type=raw,value=${{ inputs.version }}
            type=raw,value=${{ inputs.version }}-r${{ inputs.revision }}
            type=raw,value=latest,enable={{is_default_branch}}
            type=sha,prefix=sha-,format=short
          labels: |
            org.opencontainers.image.version=${{ inputs.version }}

      - name: Build and push (multi-arch with native SBOM + provenance)
        id: build
        uses: docker/build-push-action@v6
        with:
          context: containers/${{ inputs.container }}
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          build-args: |
            CLAUDE_CODE_VERSION=${{ inputs.version }}
            NODE_VERSION=lts
          cache-from: type=gha,scope=${{ inputs.container }}
          cache-to: type=gha,mode=max,scope=${{ inputs.container }}
          provenance: mode=max   # SLSA provenance attached to OCI image
          sbom: true             # SPDX SBOM attached to OCI image

      - name: Attest build provenance (GitHub native)
        uses: actions/attest-build-provenance@v2
        with:
          subject-name: ghcr.io/${{ github.repository_owner }}/${{ inputs.container }}
          subject-digest: ${{ steps.build.outputs.digest }}
          push-to-registry: true

      - name: Install cosign
        uses: sigstore/cosign-installer@v3

      - name: Sign image with keyless cosign (Sigstore)
        run: |
          cosign sign --yes \
            "ghcr.io/${{ github.repository_owner }}/${{ inputs.container }}@${{ steps.build.outputs.digest }}"
        env:
          COSIGN_EXPERIMENTAL: "1"
```

- [ ] **Step 2: Validate with actionlint**

```bash
actionlint .github/workflows/build.yaml
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build.yaml
git commit -m "ci: add reusable build workflow with SBOM, attestation, cosign signing"
```

---

## Task 7: Reusable Release Workflow

**Files:**
- Create: `.github/workflows/release.yaml`

- [ ] **Step 1: Create .github/workflows/release.yaml**

```yaml
name: Release Container

on:
  workflow_call:
    inputs:
      container:
        description: "Container name"
        required: true
        type: string
      version:
        description: "Upstream version"
        required: true
        type: string
      revision:
        description: "Image revision"
        required: false
        type: string
        default: "1"
      digest:
        description: "Image digest from build workflow"
        required: true
        type: string

jobs:
  release:
    name: Release ${{ inputs.container }}-${{ inputs.version }}-r${{ inputs.revision }}
    runs-on: ubuntu-latest
    permissions:
      contents: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Determine last release tag
        id: last-tag
        run: |
          LAST=$(git tag --list "${{ inputs.container }}-*" \
            --sort=-version:refname | head -1 || true)
          echo "tag=${LAST}" >> "$GITHUB_OUTPUT"
          echo "Last tag: ${LAST:-none}"

      - name: Collect conventional commits since last tag
        id: commits
        run: |
          if [[ -z "${{ steps.last-tag.outputs.tag }}" ]]; then
            RANGE="HEAD"
          else
            RANGE="${{ steps.last-tag.outputs.tag }}..HEAD"
          fi

          FEATS=$(git log "$RANGE" --pretty=format:"%s" \
            -- "containers/${{ inputs.container }}/" \
            | grep -E '^feat(\([^)]+\))?!?:' | sed 's/^/- /' || true)

          FIXES=$(git log "$RANGE" --pretty=format:"%s" \
            -- "containers/${{ inputs.container }}/" \
            | grep -E '^fix(\([^)]+\))?!?:' | sed 's/^/- /' || true)

          CHANGES=$(git log "$RANGE" --pretty=format:"%s" \
            -- "containers/${{ inputs.container }}/" \
            | grep -E '^(chore|perf|refactor)(\([^)]+\))?!?:' | sed 's/^/- /' || true)

          echo "$FEATS" > /tmp/feats.txt
          echo "$FIXES" > /tmp/fixes.txt
          echo "$CHANGES" > /tmp/changes.txt

      - name: Update CHANGELOG.md
        run: |
          DATE=$(date +%Y-%m-%d)
          CHANGELOG="containers/${{ inputs.container }}/CHANGELOG.md"

          NEW_SECTION="## [${{ inputs.version }}-r${{ inputs.revision }}] - ${DATE}"

          if [[ -s /tmp/feats.txt ]]; then
            NEW_SECTION="${NEW_SECTION}\n\n### Added\n$(cat /tmp/feats.txt)"
          fi
          if [[ -s /tmp/fixes.txt ]]; then
            NEW_SECTION="${NEW_SECTION}\n\n### Fixed\n$(cat /tmp/fixes.txt)"
          fi
          if [[ -s /tmp/changes.txt ]]; then
            NEW_SECTION="${NEW_SECTION}\n\n### Changed\n$(cat /tmp/changes.txt)"
          fi

          awk -v section="$NEW_SECTION" \
            '/^## \[Unreleased\]/{print; print ""; printf "%s\n", section; next}1' \
            "$CHANGELOG" > /tmp/changelog.tmp
          mv /tmp/changelog.tmp "$CHANGELOG"

      - name: Commit updated changelog
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add "containers/${{ inputs.container }}/CHANGELOG.md"
          git commit -m "chore(${{ inputs.container }}): update changelog for ${{ inputs.version }}-r${{ inputs.revision }}" \
            || echo "No changelog changes to commit"
          git push

      - name: Build release notes
        id: notes
        run: |
          IMAGE="ghcr.io/${{ github.repository_owner }}/${{ inputs.container }}"
          DIGEST="${{ inputs.digest }}"

          {
            echo "## ${{ inputs.container }} ${{ inputs.version }}-r${{ inputs.revision }}"
            echo ""
            echo "### Container"
            echo ""
            echo '```bash'
            echo "# Pull by tag"
            echo "docker pull ${IMAGE}:${{ inputs.version }}-r${{ inputs.revision }}"
            echo ""
            echo "# Pull by immutable digest (recommended)"
            echo "docker pull ${IMAGE}@${DIGEST}"
            echo '```'
            echo ""
            echo "### Verification"
            echo ""
            echo '```bash'
            echo "cosign verify ${IMAGE}:${{ inputs.version }}-r${{ inputs.revision }} \\"
            echo "  --certificate-oidc-issuer https://token.actions.githubusercontent.com \\"
            echo "  --certificate-identity-regexp 'https://github.com/${{ github.repository }}'"
            echo '```'
            echo ""
            if [[ -s /tmp/feats.txt ]]; then
              echo "### Added"
              cat /tmp/feats.txt
              echo ""
            fi
            if [[ -s /tmp/fixes.txt ]]; then
              echo "### Fixed"
              cat /tmp/fixes.txt
              echo ""
            fi
          } > /tmp/release-notes.md

          echo "notes_file=/tmp/release-notes.md" >> "$GITHUB_OUTPUT"

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ inputs.container }}-${{ inputs.version }}-r${{ inputs.revision }}
          name: "${{ inputs.container }} ${{ inputs.version }}-r${{ inputs.revision }}"
          body_path: /tmp/release-notes.md
          make_latest: false
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 2: Validate with actionlint**

```bash
actionlint .github/workflows/release.yaml
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yaml
git commit -m "ci: add reusable release workflow with changelog and GitHub Release"
```

---

## Task 8: Push-to-Main Caller Workflow

**Files:**
- Create: `.github/workflows/push.yaml`

Detects which containers changed on push to main, reads their version from `values.yaml`, calls `build.yaml` then `release.yaml` per container.

- [ ] **Step 1: Create .github/workflows/push.yaml**

```yaml
name: Build and Release on Push

on:
  push:
    branches:
      - main
    paths:
      - "containers/**"

jobs:
  detect-changes:
    name: Detect changed containers
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.changes.outputs.matrix }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 2

      - name: Detect changed containers and read versions
        id: changes
        run: |
          CHANGED=$(git diff --name-only HEAD~1 HEAD \
            | grep '^containers/' \
            | cut -d/ -f2 \
            | sort -u)

          MATRIX="[]"
          for CONTAINER in $CHANGED; do
            VALUES="containers/${CONTAINER}/ci/values.yaml"
            if [[ ! -f "$VALUES" ]]; then
              echo "Skipping ${CONTAINER}: no values.yaml"
              continue
            fi
            VERSION=$(grep '^  version:' "$VALUES" | awk '{print $2}' | tr -d '"')

            # Compute revision: count existing tags for this version + 1
            EXISTING=$(git tag --list "${CONTAINER}-${VERSION}-r*" | wc -l | tr -d ' ')
            REVISION=$((EXISTING + 1))

            ENTRY=$(jq -n \
              --arg c "$CONTAINER" \
              --arg v "$VERSION" \
              --arg r "$REVISION" \
              '{container: $c, version: $v, revision: $r}')
            MATRIX=$(echo "$MATRIX" | jq --argjson e "$ENTRY" '. + [$e]')
          done

          echo "matrix=${MATRIX}" >> "$GITHUB_OUTPUT"
          echo "Build matrix: ${MATRIX}"

  build:
    name: Build ${{ matrix.container }}
    needs: detect-changes
    if: needs.detect-changes.outputs.matrix != '[]'
    strategy:
      matrix:
        include: ${{ fromJson(needs.detect-changes.outputs.matrix) }}
      fail-fast: false
    uses: ./.github/workflows/build.yaml
    with:
      container: ${{ matrix.container }}
      version: ${{ matrix.version }}
      revision: ${{ matrix.revision }}
    permissions:
      contents: read
      packages: write
      id-token: write
      attestations: write

  release:
    name: Release ${{ matrix.container }}
    needs: [detect-changes, build]
    if: needs.detect-changes.outputs.matrix != '[]'
    strategy:
      matrix:
        include: ${{ fromJson(needs.detect-changes.outputs.matrix) }}
      fail-fast: false
    uses: ./.github/workflows/release.yaml
    with:
      container: ${{ matrix.container }}
      version: ${{ matrix.version }}
      revision: ${{ matrix.revision }}
      digest: ${{ needs.build.outputs.digest }}
    permissions:
      contents: write
```

- [ ] **Step 2: Validate with actionlint**

```bash
actionlint .github/workflows/push.yaml
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/push.yaml
git commit -m "ci: add push-to-main build and release caller workflow"
```

---

## Task 9: Nightly Schedule Workflow

**Files:**
- Create: `.github/workflows/schedule.yaml`

- [ ] **Step 1: Create .github/workflows/schedule.yaml**

```yaml
name: Check Upstream Versions

on:
  schedule:
    - cron: "0 6 * * *"  # 06:00 UTC daily
  workflow_dispatch:      # allow manual trigger

jobs:
  check-versions:
    name: Check ${{ matrix.container }} upstream
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    strategy:
      matrix:
        container:
          - claude-code
      fail-fast: false
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Check upstream version
        id: upstream
        run: |
          LATEST=$(./scripts/check-upstream.sh "${{ matrix.container }}")
          CURRENT=$(grep '^  version:' "containers/${{ matrix.container }}/ci/values.yaml" \
            | awk '{print $2}' | tr -d '"')

          echo "latest=${LATEST}" >> "$GITHUB_OUTPUT"
          echo "current=${CURRENT}" >> "$GITHUB_OUTPUT"

          if [[ "$LATEST" != "$CURRENT" ]]; then
            echo "update=true" >> "$GITHUB_OUTPUT"
            echo "Update available: ${CURRENT} → ${LATEST}"
          else
            echo "update=false" >> "$GITHUB_OUTPUT"
            echo "Already at latest: ${CURRENT}"
          fi

      - name: Update version and open PR
        if: steps.upstream.outputs.update == 'true'
        run: |
          BRANCH="update/${{ matrix.container }}-${{ steps.upstream.outputs.latest }}"

          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

          git checkout -b "$BRANCH"
          ./scripts/update-version.sh "${{ matrix.container }}" "${{ steps.upstream.outputs.latest }}"

          git add "containers/${{ matrix.container }}/ci/values.yaml"
          git commit -m "chore(${{ matrix.container }}): update to ${{ steps.upstream.outputs.latest }}"
          git push origin "$BRANCH"

          gh pr create \
            --title "chore(${{ matrix.container }}): update to ${{ steps.upstream.outputs.latest }}" \
            --body "Automated version bump: ${{ steps.upstream.outputs.current }} → ${{ steps.upstream.outputs.latest }}" \
            --base main \
            --head "$BRANCH" \
            --label "automated,version-bump" || echo "PR may already exist"
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 2: Validate with actionlint**

```bash
actionlint .github/workflows/schedule.yaml
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/schedule.yaml
git commit -m "ci: add nightly upstream version check and PR workflow"
```

---

## Task 10: Scaffold Workflow

**Files:**
- Create: `.github/workflows/scaffold.yaml`

- [ ] **Step 1: Create .github/workflows/scaffold.yaml**

```yaml
name: Scaffold New Container

on:
  workflow_dispatch:
    inputs:
      name:
        description: "Container name (lowercase, hyphens ok — e.g. my-tool)"
        required: true
        type: string
      upstream_source:
        description: "Upstream version source"
        required: true
        type: choice
        options:
          - npm
          - github
      upstream_package:
        description: "npm package (e.g. @scope/pkg) or GitHub repo (e.g. owner/repo)"
        required: true
        type: string
      initial_version:
        description: "Initial version to track (e.g. 1.0.0)"
        required: true
        type: string
      description:
        description: "One-line image description"
        required: true
        type: string

jobs:
  scaffold:
    name: Scaffold ${{ github.event.inputs.name }}
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Validate container name
        run: |
          NAME="${{ github.event.inputs.name }}"
          if [[ ! "$NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
            echo "ERROR: Container name must be lowercase alphanumeric with hyphens" >&2
            exit 1
          fi
          if [[ -d "containers/${NAME}" ]]; then
            echo "ERROR: containers/${NAME} already exists" >&2
            exit 1
          fi

      - name: Create container scaffold
        run: |
          NAME="${{ github.event.inputs.name }}"
          SOURCE="${{ github.event.inputs.upstream_source }}"
          PACKAGE="${{ github.event.inputs.upstream_package }}"
          VERSION="${{ github.event.inputs.initial_version }}"
          DESCRIPTION="${{ github.event.inputs.description }}"

          mkdir -p "containers/${NAME}/ci"

          cat > "containers/${NAME}/Dockerfile" <<'DOCKERFILE'
# syntax=docker/dockerfile:1
# TODO: replace this scaffold Dockerfile with the actual build

FROM ubuntu:24.04 AS runtime

RUN useradd -m -s /bin/bash appuser

USER appuser
WORKDIR /home/appuser

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD echo "ok"

ENTRYPOINT ["/bin/bash"]
DOCKERFILE

          cat > "containers/${NAME}/ci/values.yaml" <<YAML
container:
  name: ${NAME}
  image: ghcr.io/j0sh3rs/${NAME}

upstream:
  source: ${SOURCE}
  package: "${PACKAGE}"
  version: "${VERSION}"

build:
  platforms:
    - linux/amd64
    - linux/arm64
  args: {}

labels:
  org.opencontainers.image.title: "${NAME}"
  org.opencontainers.image.description: "${DESCRIPTION}"
  org.opencontainers.image.source: "https://github.com/j0sh3rs/containers"
  org.opencontainers.image.licenses: "MIT"
YAML

          cat > "containers/${NAME}/CHANGELOG.md" <<'CHANGELOG'
# Changelog

All notable changes to this container are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]
CHANGELOG

      - name: Open PR with scaffold
        run: |
          NAME="${{ github.event.inputs.name }}"
          BRANCH="scaffold/${NAME}"

          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

          git checkout -b "$BRANCH"
          git add "containers/${NAME}/"
          git commit -m "feat(${NAME}): scaffold new container"
          git push origin "$BRANCH"

          gh pr create \
            --title "feat(${NAME}): scaffold new container" \
            --body "Scaffolded by workflow dispatch. Update the Dockerfile before merging." \
            --base main \
            --head "$BRANCH"
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 2: Validate with actionlint**

```bash
actionlint .github/workflows/scaffold.yaml
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/scaffold.yaml
git commit -m "ci: add scaffold workflow for new containers"
```

---

## Task 11: Final Validation Pass

**Files:** All files created above.

- [ ] **Step 1: Run actionlint across all workflows**

```bash
actionlint .github/workflows/*.yaml
```

Expected: no output. Fix any issues before proceeding.

- [ ] **Step 2: Run shellcheck across all scripts**

```bash
shellcheck scripts/*.sh
```

Expected: no output.

- [ ] **Step 3: Run hadolint on claude-code Dockerfile**

```bash
hadolint containers/claude-code/Dockerfile
```

Expected: no output (or INFO-level style notes only).

- [ ] **Step 4: Verify directory structure matches spec**

```bash
find . -not -path './.git/*' -not -path './.claude/*' | sort
```

Expected output includes:
```
./containers/claude-code/Dockerfile
./containers/claude-code/CHANGELOG.md
./containers/claude-code/ci/values.yaml
./scripts/check-upstream.sh
./scripts/update-version.sh
./.github/workflows/build.yaml
./.github/workflows/pr.yaml
./.github/workflows/push.yaml
./.github/workflows/release.yaml
./.github/workflows/scaffold.yaml
./.github/workflows/schedule.yaml
./CONTRIBUTING.md
./README.md
```

- [ ] **Step 5: Final local build test**

```bash
docker build \
  --build-arg CLAUDE_CODE_VERSION=$(./scripts/check-upstream.sh claude-code) \
  --build-arg NODE_VERSION=lts \
  -t claude-code:final-test \
  containers/claude-code/
docker run --rm claude-code:final-test --version
```

Expected: successful build and version output.

- [ ] **Step 6: Push to remote**

```bash
git push -u origin main
```

- [ ] **Step 7: Verify first CI run in GitHub**

```bash
gh run list --limit 5
```

Watch the first workflow run complete green.

---

## Post-Implementation: First Real GHCR Build

After push, trigger the first real build:

```bash
git commit --allow-empty -m "ci: trigger initial claude-code build"
git push
```

Then verify:

```bash
# Pull by digest
docker pull ghcr.io/j0sh3rs/claude-code:latest

# Verify signature
cosign verify ghcr.io/j0sh3rs/claude-code:latest \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp "https://github.com/j0sh3rs/containers"

# Verify GitHub provenance attestation
gh attestation verify oci://ghcr.io/j0sh3rs/claude-code:latest \
  --repo j0sh3rs/containers
```
