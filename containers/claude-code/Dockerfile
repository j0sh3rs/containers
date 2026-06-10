# syntax=docker/dockerfile:1

ARG NODE_VERSION=lts
ARG CLAUDE_CODE_VERSION=latest

# --- builder: install claude-code with native build deps ---
FROM node:${NODE_VERSION}-alpine AS builder

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

# Create non-root user
RUN addgroup -S claude && adduser -S claude -G claude

# Copy only the installed CLI artifacts from builder
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=builder /usr/local/bin/claude /usr/local/bin/claude

# Runtime dependencies only
# hadolint ignore=DL3018
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
