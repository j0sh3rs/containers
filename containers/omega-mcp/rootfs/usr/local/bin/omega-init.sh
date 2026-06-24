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
# The public OSS bits (omega-memory[full]) install from an OFFLINE wheelhouse
# baked into the image — no network needed for them. Only the licensed Pro
# wheel is fetched at runtime, by `omega activate`, from the vendor, gated by
# $OMEGA_LICENSE_KEY. The public image carries zero licensed code.
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
#
# Also rebuild on an INCOMPLETE venv. A reused venv is only trustworthy if it
# actually carries the omega CLI (`omega-memory` ships it as the console_script
# `omega = omega.cli:main`). A venv that is python-matched but missing
# bin/omega — a half-finished prior init, or a venv from an older image layout —
# would pass the version check, no-op through the offline install (uv reports
# the requirement "satisfied" and lays no script), then die at step 3 with a
# bare `omega: command not found`. Treat a missing bin/omega as a corrupt venv
# and rebuild clean; the model/DB/license live elsewhere on the PVC, so this
# only re-installs packages.
NEED_VENV=1
if [ -x "${VENV}/bin/python" ]; then
	WANT_PY="$(python3 -c 'import sys;print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
	HAVE_PY="$("${VENV}/bin/python" -c 'import sys;print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "?")"
	if [ "${WANT_PY}" != "${HAVE_PY}" ]; then
		log "venv python ${HAVE_PY} != image python ${WANT_PY}; rebuilding venv"
		rm -rf "${VENV}"
	elif [ ! -x "${VENV}/bin/omega" ]; then
		log "venv at ${VENV} lacks the omega CLI (incomplete/older layout); rebuilding venv"
		rm -rf "${VENV}"
	else
		NEED_VENV=0
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

# --- 2. Install omega-memory[full] offline from the wheelhouse --------------
# --no-index: never reach PyPI; the full OSS closure is pinned in the image
# wheelhouse. [full] = server (mcp/starlette/uvicorn) + encrypt (cryptography/
# keyring for the Profile module).
#
# The omega-pro-shim is GONE: upstream omega_memory_pro 1.5.4 now ships its own
# `omega.plugins` entry point (omega_pro = omega_platform.plugin:
# OmegaPlatformPlugin), so the packaging gap that the shim bridged is closed.
# See omega-memory#63 (fixed 2026-06-24). The pro_tools gate is now opened by
# the vendor wheel alone; step 6 verifies that.
# --upgrade: a reused PVC venv may already hold an OLDER omega-memory. Without
# this, uv reports the unpinned requirement "satisfied" and installs nothing
# (the "Checked 1 package" no-op), so an image carrying a newer wheelhouse never
# actually upgrades the running venv. --upgrade makes the wheelhouse version
# authoritative — the image's pinned OSS closure wins over whatever the PVC had.
log "installing omega-memory[full] from offline wheelhouse"
uv pip install --no-index --find-links "${WHEELHOUSE}" --upgrade \
	"omega-memory[full]"

# The omega CLI must now exist; everything downstream (omega activate / setup /
# serve) shells out to it. If it is absent here the install silently did not
# land the console_script — fail loud now instead of at `omega activate` with a
# bare "command not found".
[ -x "${VENV}/bin/omega" ] || fail "omega CLI missing at ${VENV}/bin/omega after install; venv is broken"

# --- 3. Activate Pro: pulls the licensed wheel from the vendor at runtime ---
# Idempotent — re-validates and refreshes the cached license.json each run.
# Requires egress to admin.omegamax.co.
[ -n "${OMEGA_LICENSE_KEY:-}" ] || fail "OMEGA_LICENSE_KEY unset; cannot activate Pro"

# Heal stale PVCs onto the fixed Pro wheel. The vendor republished the fix
# IN PLACE as omega_memory_pro-1.5.4 (same version, same filename — see
# omega-memory#63, fixed 2026-06-24). pip/uv treat ==1.5.4 as already
# satisfied, so on a PVC that installed the OLD buggy 1.5.4 (no omega.plugins
# entry point), `omega activate` would NOT redownload it — leaving the
# pro_tools gate shut now that the shim is gone. So: if Pro is installed but
# does NOT advertise the new `omega_pro` entry point, uninstall it first,
# forcing `omega activate` to pull the fixed wheel fresh. Fresh PVCs and
# already-healed PVCs skip this (the entry point is present), so it costs a
# Pro re-download at most once per PVC.
if python -c 'import importlib.util,sys; sys.exit(0 if importlib.util.find_spec("omega_platform") else 1)' 2>/dev/null; then
	HAS_EP="$(
		python - <<'PY'
from importlib.metadata import entry_points
eps = entry_points(group="omega.plugins")
print("yes" if any(ep.name == "omega_pro" for ep in eps) else "no")
PY
	)"
	if [ "${HAS_EP}" = "no" ]; then
		log "stale Pro wheel detected (no omega_pro entry point); uninstalling to force redownload of the fixed 1.5.4"
		uv pip uninstall omega_memory_pro 2>/dev/null || true
	fi
fi

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
#   - the upstream `omega_pro` plugin entry point is absent (would mean a stale
#     buggy Pro wheel survived — the shim is gone, so nothing else supplies it)
#   - the pro_tools capability gate did not open
log "verifying sqlite-vec, onnxruntime, ONNX model, omega_pro entry point, and pro_tools"
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

# upstream omega_pro plugin entry point present? (the fix from omega-memory#63)
# With the local shim removed, this entry point can ONLY come from the fixed
# vendor wheel. Its absence means a stale buggy 1.5.4 survived the heal in
# step 3 — fail loudly rather than serve with Pro dark.
try:
    from importlib.metadata import entry_points
    eps = entry_points(group="omega.plugins")
    if any(ep.name == "omega_pro" for ep in eps):
        print("[omega-init]   omega.plugins 'omega_pro' entry point present OK")
    else:
        problems.append(
            "omega_pro entry point missing (stale Pro wheel? expected the "
            "fixed omega_memory_pro 1.5.4 per omega-memory#63)"
        )
except Exception as exc:
    problems.append(f"entry point check failed: {exc}")

# pro_tools gate open?
try:
    from omega.plugins import has_capability
    if has_capability("pro_tools"):
        print("[omega-init]   has_capability('pro_tools') = True")
    else:
        problems.append("pro_tools capability is False (license gate shut)")
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
