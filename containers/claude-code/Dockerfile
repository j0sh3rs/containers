# syntax=docker/dockerfile:1

# Pin to a major LTS line, not the floating `lts` tag, for reproducible
# builds and to avoid surprise major-version bumps.
ARG NODE_VERSION=24
ARG CLAUDE_CODE_VERSION=latest

# --- builder: install claude-code with native build deps ---
# NOTE: claude-code is installed via `npm -g` into /usr/local, NOT the native
# installer. The native installer puts the binary under $HOME/.local, but the
# k8s runner Job mounts an empty emptyDir over the WHOLE of /home/claude, which
# would shadow a home-based binary (claude: not found). Installing to
# /usr/local keeps the binary OUTSIDE any mounted path so it survives both the
# daemon (PVC at ~/.claude subdir) and the runner (emptyDir at whole home).
# Trade-off: `claude /doctor` shows cosmetic install-method/PATH warnings. The
# CLI is fully functional regardless; the daemon never blocks on doctor.
FROM node:${NODE_VERSION}-alpine AS builder

# python3/make/g++ are needed for native npm modules; git for any
# git-based dependencies. This whole stage is discarded from the final image.
# Lifecycle scripts run here (--ignore-scripts=false) because some deps need
# them to build — the supply-chain blast radius is contained to the builder.
# hadolint ignore=DL3018
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git && \
    npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    --prefix /usr/local \
    --ignore-scripts=false

# --- runtime: minimal image without build toolchain ---
FROM node:${NODE_VERSION}-alpine AS runtime

# Runtime dependencies only. tini provides PID 1 init for proper signal
# forwarding and zombie reaping (Claude spawns bash/tool subprocesses).
# git is used by Claude for repo operations; ca-certificates for TLS;
# libgcc/libstdc++ are the musl runtime libs the bundled native binary needs.
# hadolint ignore=DL3018
RUN apk add --no-cache \
    git \
    ca-certificates \
    bash \
    libgcc \
    libstdc++ \
    tini

# Create the `claude` user with home /home/claude to match the deployment
# (HOME=/home/claude; PVC mounted at /home/claude/.claude).
#
# The baked uid does NOT need to match the runtime uid: the pod overrides it
# via securityContext.runAsUser (daemon 1024, runner 1001) and sets fsGroup so
# the mounted ~/.claude volume is group-writable. We chown the home dir at
# build time only so the image is sane when run without an override.
RUN addgroup -S claude && \
    adduser -S claude -G claude -h /home/claude && \
    mkdir -p /home/claude/.claude && \
    chown -R claude:claude /home/claude

# Copy only the installed CLI artifacts from builder. /usr/local/bin/claude is
# outside /home/claude, so it is never shadowed by a volume mount.
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=builder /usr/local/bin/claude /usr/local/bin/claude

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
