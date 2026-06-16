# syntax=docker/dockerfile:1

# Pin to a major LTS line, not the floating `lts` tag, for reproducible
# builds and to avoid surprise major-version bumps.
ARG NODE_VERSION=24
ARG CLAUDE_CODE_VERSION=latest

# --- builder: fetch the native Claude Code build ---
# The official installer (install.sh) downloads a prebuilt, statically-ish
# linked binary into ~/.local. Using the native build (instead of `npm -g`)
# is what keeps `claude /doctor` green: it sets installMethod=native in
# ~/.claude.json and avoids the "leftover npm global installation" warning.
# This stage is discarded; only the resolved install tree is copied forward.
FROM node:${NODE_VERSION}-alpine AS builder

ARG CLAUDE_CODE_VERSION

# curl + bash to run the installer; libgcc/libstdc++ are the musl runtime
# libs the native binary links against.
# hadolint ignore=DL3018
RUN apk add --no-cache curl bash libgcc libstdc++ ca-certificates

# Install under HOME=/home/claude so the install tree (~/.local) and the
# install-state marker (~/.claude.json) land at the SAME path the Kubernetes
# deployment sets via HOME=/home/claude. Install as an unprivileged user so
# the files are not root-owned. The uid is irrelevant (the runtime stage and
# k8s pods override it); we re-own everything world-readable in the runtime
# stage anyway.
RUN addgroup -S claude && \
    adduser -S claude -G claude -h /home/claude
USER claude
WORKDIR /home/claude
ENV HOME=/home/claude
# pipefail so a failed curl aborts the build instead of piping empty input to bash.
SHELL ["/bin/ash", "-o", "pipefail", "-c"]
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_CODE_VERSION}"

# --- runtime: minimal image without build/installer tooling ---
FROM node:${NODE_VERSION}-alpine AS runtime

# Runtime dependencies only. tini provides PID 1 init for proper signal
# forwarding and zombie reaping (Claude spawns bash/tool subprocesses).
# git is used by Claude for repo operations; ca-certificates for TLS;
# libgcc/libstdc++ are the musl runtime libs the native binary needs.
# hadolint ignore=DL3018
RUN apk add --no-cache \
    git \
    ca-certificates \
    bash \
    libgcc \
    libstdc++ \
    tini

# Recreate the `claude` user with home /home/claude to match the deployment
# (HOME=/home/claude, PVC mounted at /home/claude/.claude).
#
# IMPORTANT: this image is run under several different runtime uids that are
# set by the pod, NOT by this USER line — the OAuth daemon runs as uid 1024
# (the nfs-client PVC squashes all writes to 1024), and the headless runner
# Job runs as uid 1001. A single baked uid cannot match both, so the baked
# install state is made WORLD-READABLE below instead of owned by one uid.
RUN addgroup -S claude && \
    adduser -S claude -G claude -h /home/claude && \
    mkdir -p /home/claude/.claude && \
    chown -R claude:claude /home/claude

# Copy the native install tree (binary + versions + state) and the install
# marker from the builder. Both live OUTSIDE the /home/claude/.claude volume,
# so installMethod=native survives the k8s PVC mount that shadows ~/.claude.
COPY --from=builder /home/claude/.local /home/claude/.local
COPY --from=builder /home/claude/.claude.json /home/claude/.claude.json

# Make the baked install state world-readable (and dirs world-executable) so
# ANY runtime uid (1024 daemon, 1001 runner, or the build-time claude user)
# can read the native binary and the 0600-by-default ~/.claude.json marker.
# This is non-secret install metadata; the OAuth credential is never baked —
# it is written to the claude-home PVC at runtime by `claude auth login`.
RUN chmod -R o+rX /home/claude/.local /home/claude/.claude.json

# Put the native binary on PATH (~/.local/bin/claude). This also resolves the
# "~/.local/bin is not in your PATH" doctor warning.
ENV PATH="/home/claude/.local/bin:${PATH}"

# Disable the auto-updater and non-essential network traffic. Set via ENV (not
# a file under ~/.claude) so it is NOT shadowed by a mounted volume. A pinned,
# reproducible image must never self-update at runtime.
ENV DISABLE_AUTOUPDATER=1 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# Mount point for ~/.claude (credentials, memory, project context, session-env).
# On Kubernetes the pod sets securityContext.fsGroup so the mounted volume is
# group-writable by the runtime uid; otherwise session-env creation fails with
# EACCES on first session start.
VOLUME ["/home/claude/.claude"]

USER claude
WORKDIR /home/claude

# Verify binary is functional
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD claude --version || exit 1

# tini as PID 1; claude as the actual workload
ENTRYPOINT ["/sbin/tini", "--", "claude"]
