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

Container versions track upstream. The nightly schedule auto-opens PRs when a new upstream version is detected. To manually bump:

```bash
./scripts/update-version.sh <container-name> <new-version>
```
