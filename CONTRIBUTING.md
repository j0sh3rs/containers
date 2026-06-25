# Contributing

## Local Setup

This repo uses [pre-commit](https://pre-commit.com/) to run the same checks CI
runs (hadolint, shellcheck, actionlint) plus secret scanning, file hygiene, and
Conventional Commit enforcement — locally, before you push.

```bash
# With mise (installs pre-commit and the git hooks):
mise install
mise run setup

# Or directly:
pip install pre-commit   # or: brew install pre-commit
pre-commit install --install-hooks --hook-type commit-msg

# Run every hook against all files on demand:
mise run lint            # or: pre-commit run --all-files
```

The hooks live in `.pre-commit-config.yaml`; YAML lint rules in `.yamllint.yaml`.

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
3. Create `containers/<name>/CHANGELOG.md` (Keep a Changelog scaffold)
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

Container versions track upstream and are managed by **Renovate**
(`.github/renovate.json5`) — it auto-opens PRs for both the base images and the
installed packages (npm/PyPI) when a new version is detected. To bump manually,
edit the `version` in `containers/<name>/ci/values.yaml` and the matching
Dockerfile `ARG`, then commit with a scoped message
(`chore(<name>): update to <version>`). A push to `main` that touches
`containers/**` rebuilds and releases automatically.
