#!/usr/bin/env bash
# omega-serve.sh — app-container entrypoint. Activates the PVC venv and runs
# the OMEGA MCP server as an HTTP daemon in the foreground (PID 1 via tini).
#
# `omega serve --daemon` sets OMEGA_TRANSPORT=http and calls asyncio.run(main()),
# which blocks serving Streamable HTTP at /mcp (health at /health). Foreground +
# signal-friendly, exactly what a container wants. The initContainer must have
# completed (venv + Pro + license + config all on the PVC) before this runs.
set -euo pipefail

OMEGA_DATA="${OMEGA_DATA:-/data}"
VENV="${OMEGA_DATA}/venv"

# HOME must match omega-init.sh: OMEGA's model/db/license paths all hang off
# Path.home(). Setting it here makes the daemon read the same PVC locations the
# initContainer populated (model at HOME/.cache/omega, db + license at
# OMEGA_HOME). OMEGA_ONNX_MODEL_DIR is intentionally NOT used — it is a dead
# lever for the download path and only a late fallback for the read path.
export HOME="${OMEGA_DATA}"
export OMEGA_HOME="${OMEGA_DATA}/.omega"
export OMEGA_TRANSPORT=http
export OMEGA_HTTP_HOST="${OMEGA_HTTP_HOST:-0.0.0.0}"
export OMEGA_HTTP_PORT="${OMEGA_HTTP_PORT:-8377}"
# Shared HTTP daemon: never idle-exit (a long-lived k8s Deployment, not a
# per-session stdio process). 0 disables the idle shutdown timer.
export OMEGA_IDLE_TIMEOUT="${OMEGA_IDLE_TIMEOUT:-0}"

if [ ! -x "${VENV}/bin/omega" ]; then
	echo "[omega-serve] FATAL: venv missing at ${VENV}; did the initContainer run?" >&2
	exit 1
fi

# shellcheck disable=SC1091
. "${VENV}/bin/activate"

exec omega serve --daemon
