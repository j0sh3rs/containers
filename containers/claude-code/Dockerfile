# syntax=docker/dockerfile:1

# Pin to a major LTS line, not the floating `lts` tag, for reproducible
# builds and to avoid surprise major-version bumps.
ARG NODE_VERSION=24
ARG CLAUDE_CODE_VERSION=latest

# --- builder: install claude-code with native build deps ---
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
# git is used by Claude for repo operations; ca-certificates for TLS.
# hadolint ignore=DL3018
RUN apk add --no-cache \
    git \
    ca-certificates \
    bash \
    tini

# Create non-root user and ensure the credential/config dir is owned by it
# before declaring the VOLUME, so the mounted volume is writable as `claude`.
RUN addgroup -S claude && \
    adduser -S claude -G claude && \
    mkdir -p /home/claude/.claude && \
    chown -R claude:claude /home/claude

# Copy only the installed CLI artifacts from builder
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=builder /usr/local/bin/claude /usr/local/bin/claude

# Mount point for ~/.claude (credentials, memory, project context)
VOLUME ["/home/claude/.claude"]

USER claude
WORKDIR /home/claude

# Verify binary is functional
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD claude --version || exit 1

# tini as PID 1; claude as the actual workload
ENTRYPOINT ["/sbin/tini", "--", "claude"]
