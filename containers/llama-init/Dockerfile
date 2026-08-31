# syntax=docker/dockerfile:1

# Pin to a specific Alpine release so a plain `docker build` is reproducible
# and never silently drifts on the floating `latest` tag. Renovate bumps this.
# renovate: datasource=docker depName=alpine versioning=docker
ARG ALPINE_VERSION=3.24

FROM alpine:${ALPINE_VERSION}

# ca-certificates is required for aria2 to verify TLS on https:// downloads.
# tini provides PID 1 init so a SIGTERM stops in-flight downloads cleanly
# instead of leaving orphaned children.
# hadolint ignore=DL3018
RUN apk add --no-cache \
    aria2 \
    ca-certificates \
    tini && \
    adduser -D -h /home/aria2 aria2

USER aria2
WORKDIR /home/aria2

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD ["aria2c", "--version"]

ENTRYPOINT ["/sbin/tini", "--", "aria2c"]
