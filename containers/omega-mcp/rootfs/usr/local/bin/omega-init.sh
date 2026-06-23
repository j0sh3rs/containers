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
# Why HOME=/data:
#   OMEGA hardcodes its cache to `Path.home()/.cache/omega` (NOT overridable by
#   OMEGA_ONNX_MODEL_DIR — that env var is only consulted as a late fallback by
#   the embedding loader, and `omega setup --download-model` ignores it
#   entirely). The ONLY lever that puts the embedding model, the DB, and the
#   license cache on the PVC consistently — for both download and runtime read
#   — is HOME. So everything below runs with HOME=/data.
#
# The public OSS bits (omega-memory[full] + the MIT shim wheel) install from an
# OFFLINE wheelhouse baked into the image — no network needed for them. Only
# the licensed Pro wheel is fetched at runtime, by `omega activate`, from the
# vendor, gated by $OMEGA_LICENSE_KEY. The public image carries zero licensed
# code.
set -euo pipefail

OMEGA_DATA="${OMEGA_DATA:-/data}"
VENV="${OMEGA_DATA}/venv"
WHEELHOUSE="/opt/wheelhouse"
MARKER="${OMEGA_DATA}/.omega/.init-complete"

# HOME is the single lever (see header). Everything OMEGA-pathed hangs off it.
export HOME="${OMEGA_DATA}"
export OMEGA_HOME="${OMEGA_DATA}/.omega"
MODEL_DIR="${OMEGA_DATA}/.cache/omega/models/bge-small-en-v1.5-onnx"

log() { printf '[omega-init] %s\n' "$*"; }
fail() {
	log "FATAL: $*"
	exit 1
}

mkdir -p "${OMEGA_HOME}" "${MODEL_DIR}"

# --- 1. Create / reuse the venv on the PVC ---------------------------------
# `uv venv --seed` seeds pip into the venv. pip is REQUIRED: `omega activate`
# (step 3) shells out to `sys.executable -m pip install <pro wheel>`, so a
# pip-less uv venv would break activation. --seed makes uv's venv behave like
# the classic `python -m venv` here.
#
# Rebuild on interpreter mismatch. The venv lives on the PVC and outlives the
# image. If the image's python minor version changes (e.g. 3.12 -> 3.14), the
# old venv's `bin/python` now resolves to the NEW interpreter, but packages
# installed under the OLD version's lib/pythonX.Y/site-packages are invisible
# to it. That silently split a prior deploy: omega_platform sat in python3.12/
# while the running 3.14 interpreter couldn't import it, so is_pro() failed and
# the pro_tools gate stayed shut. Detect the mismatch and rebuild clean. The
# model, DB, and license live elsewhere on the PVC, so this only re-installs
# packages — it does not re-download the model.
NEED_VENV=1
if [ -x "${VENV}/bin/python" ]; then
	WANT_PY="$(python3 -c 'import sys;print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
	HAVE_PY="$("${VENV}/bin/python" -c 'import sys;print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "?")"
	if [ "${WANT_PY}" = "${HAVE_PY}" ]; then
		NEED_VENV=0
	else
		log "venv python ${HAVE_PY} != image python ${WANT_PY}; rebuilding venv"
		rm -rf "${VENV}"
	fi
fi
if [ "${NEED_VENV}" -eq 1 ]; then
	log "creating venv at ${VENV} (uv venv --seed)"
	uv venv --seed "${VENV}"
fi
# shellcheck disable=SC1091
. "${VENV}/bin/activate"
# Point uv at this venv for all subsequent `uv pip` calls.
export VIRTUAL_ENV="${VENV}"

# --- 2. Install omega-memory[full] + shim, both offline from the wheelhouse -
# --no-index: never reach PyPI; the full OSS closure AND the pre-built shim
# wheel are pinned in the image wheelhouse. [full] = server (mcp/starlette/
# uvicorn) + encrypt (cryptography/keyring for the Profile module).
log "installing omega-memory[full] + omega-pro-shim from offline wheelhouse"
uv pip install --no-index --find-links "${WHEELHOUSE}" \
	"omega-memory[full]" "omega-pro-shim"

# --- 3. Activate Pro: pulls the licensed wheel from the vendor at runtime ---
# Idempotent — re-validates and refreshes the cached license.json each run.
# Requires egress to admin.omegamax.co.
[ -n "${OMEGA_LICENSE_KEY:-}" ] || fail "OMEGA_LICENSE_KEY unset; cannot activate Pro"
log "activating Pro license (downloads Pro wheel into ${VENV})"
omega activate "${OMEGA_LICENSE_KEY}"

# --- 4. Download the embedding model onto the PVC (idempotent) -------------
# `omega setup --download-model` writes to HOME/.cache/omega/... and skips if
# already present, so this is a no-op on every boot after the first. Keeping
# the model on the PVC is what prevents a ~130MB re-download per restart.
log "ensuring bge-small-en-v1.5 ONNX model present on PVC"
omega setup --download-model

# --- 5. Write config.json with entity scoping enabled -----------------------
# Operator decision: entity-scoped memory. Callers pass entity_id per
# project/client to partition the single shared DB.
CONFIG="${OMEGA_HOME}/config.json"
log "writing ${CONFIG} (entity_scoping.enabled=true)"
cat >"${CONFIG}" <<JSON
{
  "storage_path": "${OMEGA_HOME}",
  "model_dir": "${MODEL_DIR}",
  "entity_scoping": {
    "enabled": true
  }
}
JSON

# --- 6. Verify the full dependency surface before declaring success ---------
# Fails the initContainer (and therefore the pod) if any of:
#   - sqlite-vec extension not loadable
#   - onnxruntime missing
#   - the bge ONNX model not on the PVC
#   - the pro_tools capability gate did not open
log "verifying sqlite-vec, onnxruntime, ONNX model, and pro_tools"
MODEL_DIR="${MODEL_DIR}" python - <<'PY'
import os
import sys

problems = []

# onnxruntime present?
try:
    import onnxruntime  # noqa: F401
    print(f"[omega-init]   onnxruntime {onnxruntime.__version__} OK")
except Exception as exc:
    problems.append(f"onnxruntime import failed: {exc}")

# sqlite-vec loadable into a real connection?
try:
    import sqlite3
    import sqlite_vec
    con = sqlite3.connect(":memory:")
    con.enable_load_extension(True)
    sqlite_vec.load(con)
    ver = con.execute("select vec_version()").fetchone()[0]
    print(f"[omega-init]   sqlite-vec {ver} OK")
    con.close()
except Exception as exc:
    problems.append(f"sqlite-vec load failed: {exc}")

# embedding model on the PVC?
model_file = os.path.join(os.environ["MODEL_DIR"], "model.onnx")
if os.path.exists(model_file):
    mb = os.path.getsize(model_file) / 1_000_000
    print(f"[omega-init]   ONNX model present ({mb:.0f} MB) at {model_file}")
else:
    problems.append(f"ONNX model missing at {model_file}")

# pro_tools gate open?
try:
    from omega.plugins import has_capability
    if has_capability("pro_tools"):
        print("[omega-init]   has_capability('pro_tools') = True")
    else:
        problems.append("pro_tools capability is False (shim/license gate shut)")
except Exception as exc:
    problems.append(f"capability check failed: {exc}")

if problems:
    for p in problems:
        print(f"[omega-init]   FAIL: {p}", file=sys.stderr)
    sys.exit(1)
print("[omega-init]   all checks passed")
PY

date -u +%Y-%m-%dT%H:%M:%SZ >"${MARKER}"
log "init complete"
