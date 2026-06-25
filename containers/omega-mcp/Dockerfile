# syntax=docker/dockerfile:1

# OMEGA memory MCP server, served over Streamable HTTP for cluster-internal use
# behind mcpjungle.
#
# Built on uv (astral) for fast, reproducible installs — but on a GLIBC base,
# NOT Alpine. This was checked, not assumed: onnxruntime and sqlite-vec both
# publish manylinux wheels ONLY (zero musllinux wheels as of onnxruntime 1.27.0
# / sqlite-vec 0.1.9). On Alpine, uv would fall back to building onnxruntime
# from sdist (cmake + protobuf, multi-hour arm64 build). uv installs the same
# PyPI artifacts pip would — it cannot conjure musl wheels — so musl buys
# nothing here and costs a brutal source build. Hence the uv *trixie-slim*
# (Debian) image, not *alpine*. The claude-code image can use Alpine because
# its Node binary is musl-native; this one cannot.
#
# This image is PUBLIC (ghcr.io/j0sh3rs). It therefore contains ZERO licensed
# code. It ships only an offline wheelhouse of the OSS `omega-memory[full]`
# (Apache-2.0). The licensed `omega_memory_pro` wheel is fetched at RUNTIME by
# `omega activate` (see omega-init.sh), inside the private cluster, gated by the
# operator's license key. Nothing licensed is ever baked or published here.
#
# NOTE: this image previously also baked a local MIT "omega-pro-shim" wheel that
# registered the `omega.plugins` entry point the upstream Pro wheel was missing
# (omega-memory#63). Upstream fixed that in the 1.5.4 customer wheel on
# 2026-06-24 — it now ships its own `omega_pro` entry point — so the shim is
# removed. omega-init.sh heals any PVC still holding the old in-place 1.5.4.

# renovate: datasource=docker depName=python versioning=docker
ARG PYTHON_VERSION=3.14
# renovate: datasource=pypi depName=omega-memory
ARG OMEGA_VERSION=1.5.4
# Pin uv to a specific version (best practice per the uv Docker guide) so image
# builds are reproducible and don't drift on a floating tag.
# renovate: datasource=docker depName=ghcr.io/astral-sh/uv versioning=semver
ARG UV_VERSION=0.11.23

# Alias the uv image as a named stage. `FROM` supports ARG expansion in its
# image ref, but `COPY --from=<image>:${VAR}` does NOT — BuildKit rejects a
# variable in --from that points at an external image. Defining this stage is
# the documented workaround: downstream stages `COPY --from=uvbin` (a stage
# name, no expansion needed) while the version stays single-sourced here.
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uvbin

# --- wheelhouse: pre-download the OSS dependency closure --------------------
# Done in a builder stage so the runtime image carries wheels, not a cache, and
# the initContainer can install fully offline (--no-index).
#
# uv has no `download`/wheelhouse subcommand, so the OSS closure is collected
# with `pip download` (plain python:slim guarantees pip is present).
FROM python:${PYTHON_VERSION}-slim AS wheelhouse
ARG OMEGA_VERSION
# uv binary, copied from the aliased stage above (single-sourced UV_VERSION).
COPY --from=uvbin /uv /uvx /bin/
# OSS dependency closure. [full] = server (mcp/starlette/uvicorn) + encrypt
# (cryptography/keyring, for the Profile module's AES-256-GCM keychain store).
RUN mkdir -p /opt/wheelhouse && \
    pip download --no-cache-dir --dest /opt/wheelhouse \
      "omega-memory[full]==${OMEGA_VERSION}"

# --- runtime ---------------------------------------------------------------
# uv's Debian-slim image: ships uv + a managed CPython, glibc base.
FROM ghcr.io/astral-sh/uv:${UV_VERSION}-python${PYTHON_VERSION}-trixie-slim AS runtime

# tini: PID 1 init (signal forwarding + zombie reaping for the asyncio daemon).
# ca-certificates: TLS to admin.omegamax.co (Pro wheel) + HF (model download).
# git: OMEGA uses it for some repo-context features; cheap to include.
# No build toolchain: the OSS closure, the Pro wheel, and the shim are all
# pure-python or prebuilt manylinux wheels, so nothing compiles at runtime.
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      tini \
      ca-certificates \
      git && \
    rm -rf /var/lib/apt/lists/*

# Pin uid 1024, gid 100 (users) to match the pod securityContext, the
# openebs-hostpath ownership, and the rest of the j0sh3rs/* AI stack. Avoids
# the uid-drift EACCES class of bugs documented in the claude-code image.
RUN groupadd -g 100 users 2>/dev/null || true && \
    useradd -m -u 1024 -g 100 -s /bin/bash omega

# Offline wheelhouse (OSS closure) + entrypoint scripts. All live OUTSIDE /data
# so the PVC mount never shadows them. Nothing here is written to at runtime, so
# root ownership is fine — the uid-1024 pod only READS the wheelhouse and
# installs FROM it into the PVC venv.
COPY --from=wheelhouse /opt/wheelhouse /opt/wheelhouse
COPY rootfs/usr/local/bin/omega-init.sh /usr/local/bin/omega-init.sh
COPY rootfs/usr/local/bin/omega-serve.sh /usr/local/bin/omega-serve.sh
# sitecustomize.py pins uuid.getnode() so the OMEGA Pro license fingerprint is
# MAC-independent (Cilium randomizes the pod MAC per rollout). omega-init.sh
# copies it into the runtime PVC venv site-packages; Python auto-imports it on
# every interpreter start (init `omega activate` AND app `omega serve`).
COPY rootfs/usr/local/share/omega/sitecustomize.py /usr/local/share/omega/sitecustomize.py
RUN chmod 0755 /usr/local/bin/omega-init.sh /usr/local/bin/omega-serve.sh && \
    chmod 0644 /usr/local/share/omega/sitecustomize.py

# UV_* knobs for predictable container behavior:
#   LINK_MODE=copy   — PVC venv may be on a filesystem uv can't hardlink into.
#   NO_CACHE=1       — no uv cache layer; installs come from the wheelhouse.
#   PYTHON_DOWNLOADS=never — use the image's CPython, never fetch one at runtime.
ENV UV_LINK_MODE=copy \
    UV_NO_CACHE=1 \
    UV_PYTHON_DOWNLOADS=never \
    OMEGA_DATA=/data \
    OMEGA_HTTP_HOST=0.0.0.0 \
    OMEGA_HTTP_PORT=8377
VOLUME ["/data"]

USER omega
WORKDIR /home/omega
EXPOSE 8377

# Liveness: the daemon's own /health endpoint.
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8377/health',timeout=4).status==200 else 1)" || exit 1

# Default entrypoint runs the server. The k8s initContainer overrides command
# to /usr/local/bin/omega-init.sh; the app container uses this default.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/omega-serve.sh"]
