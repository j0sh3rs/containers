# syntax=docker/dockerfile:1
# TODO: replace this scaffold Dockerfile with the actual build

FROM ubuntu:24.04 AS runtime

RUN useradd -m -s /bin/bash appuser

USER appuser
WORKDIR /home/appuser

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD echo "ok"

ENTRYPOINT ["/bin/bash"]
