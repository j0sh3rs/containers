# Changelog

All notable changes to the claude-code container are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- fix(claude-code): pin the `claude` user to uid 1024, gid 100 (`users`)
  instead of an arbitrary `adduser -S` uid. The image now matches the pod
  securityContext (runAsUser 1024, runAsGroup 100) and the nfs-client mount
  ownership (admin:users = 1024:100), eliminating uid drift that left
  ~/.claude/.claude.json owned by a uid the process could not read — the root
  cause of remote-control's "Unable to determine your organization" failure.

## [2.1.178-r1] - 2026-06-16

### Fixed
- fix(claude-code): Mount fixes and EACCES problems

### Changed
- chore(claude-code): update to 2.1.178
- chore(claude-code): changelog claude-code-2.1.177-r1

## [2.1.177-r1] - 2026-06-15

## [2.1.177-r1] - 2026-06-15

### Changed
- chore(claude-code): update to 2.1.177

## [2.1.170-r1] - 2026-06-10

### Added
- feat(claude-code): add container metadata and empty changelog
- feat(claude-code): add multi-stage Alpine Dockerfile
