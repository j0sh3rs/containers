# syntax=docker/dockerfile:1

# OMEGA memory MCP server, served over Streamable HTTP for cluster-internal use
# behind mcpjungle.
#
# Base is debian-slim (glibc), NOT Alpine like the claude-code image: OMEGA
# depends on onnxruntime, which publishes no musl wheels. A musl base would
# fail to install the embedding runtime.
#
# This image is PUBLIC (ghcr.io/j0sh3rs). It therefore contains ZERO licensed
# code. It ships only:
#   - an offline wheelhouse of the OSS `omega-memory[server]` (Apache-2.0), and
#   - the MIT capability shim source (./rootfs/opt/omega-pro-shim).
# The licensed `omega_memory_pro` wheel is fetched at RUNTIME by `omega
# activate` (see omega-init.sh), inside the private cluster, gated by the
# operator's license key. Nothing licensed is ever baked or published here.

ARG PYTHON_VERSION=3.12
ARG OMEGA_VERSION=1.5.4

# --- wheelhouse: pre-download the OSS dependency closure -------------------
# Done in a builder stage so the runtime image carries wheels, not a pip cache,
# and the initContainer can install fully offline (--no-index).
FROM python:${PYTHON_VERSION}-slim AS wheelhouse
ARG OMEGA_VERSION
# hadolint ignore=DL3013
RUN python -m pip install --quiet --no-cache-dir --upgrade pip wheel
RUN mkdir -p /opt/wheelhouse && \
    pip download --no-cache-dir --dest /opt/wheelhouse \
      "omega-memory[server]==${OMEGA_VERSION}"

# --- runtime ---------------------------------------------------------------
FROM python:${PYTHON_VERSION}-slim AS runtime

# tini: PID 1 init (signal forwarding + zombie reaping for the asyncio daemon).
# ca-certificates: TLS to admin.omegamax.co (Pro wheel) + HF (model download).
# git: OMEGA uses it for some repo-context features; cheap to include.
# build-essential is intentionally OMITTED — the OSS closure and the Pro wheel
# are both pure-python (py3-none-any), so no compiler is needed at runtime.
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

# Offline OSS wheelhouse + MIT shim source + entrypoint scripts. All live
# OUTSIDE /data so the PVC mount never shadows them.
COPY --from=wheelhouse /opt/wheelhouse /opt/wheelhouse
COPY rootfs/opt/omega-pro-shim /opt/omega-pro-shim
COPY rootfs/usr/local/bin/omega-init.sh /usr/local/bin/omega-init.sh
COPY rootfs/usr/local/bin/omega-serve.sh /usr/local/bin/omega-serve.sh
RUN chmod 0755 /usr/local/bin/omega-init.sh /usr/local/bin/omega-serve.sh

# The venv, memory DB, license, and model cache all live on the PVC mounted
# here (see omega-init.sh). Declared so a bare `docker run` still persists.
ENV OMEGA_DATA=/data \
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
