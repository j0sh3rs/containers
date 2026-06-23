#!/usr/bin/env bash
# omega-init.sh — one-time-per-PVC bootstrap, run by the k8s initContainer.
#
# Why a PVC-resident venv instead of a baked image venv:
#   `omega activate` shells out to `sys.executable -m pip install <pro wheel>`,
#   mutating its own venv in place. A read-only image layer can't receive that
#   install, and copying a baked venv breaks because pip shebangs + sys.prefix
#   would still point at the image path (Pro lands somewhere the daemon never
#   imports from). So the venv is created ON the PVC, where everything resolves
#   to /data/venv consistently for both this container and the app container.
#
# The public OSS bits (omega-memory[server] + the MIT shim) install from an
# OFFLINE wheelhouse baked into the image — no network needed for them. Only
# the licensed Pro wheel is fetched at runtime, by `omega activate`, from the
# vendor, gated by $OMEGA_LICENSE_KEY. The public image carries zero licensed
# code.
set -euo pipefail

OMEGA_DATA="${OMEGA_DATA:-/data}"
VENV="${OMEGA_DATA}/venv"
WHEELHOUSE="/opt/wheelhouse"
SHIM_SRC="/opt/omega-pro-shim"
MARKER="${OMEGA_DATA}/.omega/.init-complete"

export OMEGA_HOME="${OMEGA_DATA}/.omega"
export OMEGA_ONNX_MODEL_DIR="${OMEGA_DATA}/models/bge-small-en-v1.5-onnx"

log() { printf '[omega-init] %s\n' "$*"; }

mkdir -p "${OMEGA_HOME}" "${OMEGA_ONNX_MODEL_DIR}"

# --- 1. Create / reuse the venv on the PVC ---------------------------------
if [ ! -x "${VENV}/bin/python" ]; then
	log "creating venv at ${VENV}"
	python3 -m venv "${VENV}"
fi
# shellcheck disable=SC1091
. "${VENV}/bin/activate"
python -m pip install --quiet --upgrade pip

# --- 2. Install the OSS core + server extra from the offline wheelhouse -----
# --no-index: never reach PyPI; everything OSS is pinned in the image wheelhouse.
log "installing omega-memory[server] from offline wheelhouse"
python -m pip install --quiet --no-index --find-links "${WHEELHOUSE}" \
	"omega-memory[server]"

# --- 3. Activate Pro: pulls the licensed wheel from the vendor at runtime ---
# Idempotent — omega_platform.license.activate() re-validates and refreshes the
# cached license.json on every run. Requires egress to admin.omegamax.co.
if [ -z "${OMEGA_LICENSE_KEY:-}" ]; then
	log "FATAL: OMEGA_LICENSE_KEY unset; cannot activate Pro"
	exit 1
fi
log "activating Pro license (downloads Pro wheel into ${VENV})"
omega activate "${OMEGA_LICENSE_KEY}"

# --- 4. Install the capability shim (opens the pro_tools gate) --------------
log "installing omega-pro-shim"
python -m pip install --quiet "${SHIM_SRC}"

# --- 5. Write config.json with entity scoping enabled -----------------------
# Operator decision: entity-scoped memory. Callers pass entity_id per
# project/client to partition the single shared DB.
CONFIG="${OMEGA_HOME}/config.json"
log "writing ${CONFIG} (entity_scoping.enabled=true)"
cat >"${CONFIG}" <<JSON
{
  "storage_path": "${OMEGA_HOME}",
  "model_dir": "${OMEGA_ONNX_MODEL_DIR}",
  "entity_scoping": {
    "enabled": true
  }
}
JSON

# --- 6. Verify the gate actually opened before declaring success ------------
log "verifying pro_tools capability"
python - <<'PY'
import sys
from omega.plugins import has_capability
ok = has_capability("pro_tools")
print(f"[omega-init] has_capability('pro_tools') = {ok}")
sys.exit(0 if ok else 1)
PY

date -u +%Y-%m-%dT%H:%M:%SZ >"${MARKER}"
log "init complete"
