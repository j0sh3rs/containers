# sitecustomize.py — stabilize uuid.getnode() for the OMEGA Pro license.
#
# WHY THIS EXISTS
# ---------------
# The OMEGA Pro license is machine-fingerprint bound. The vendor wheel computes
# (omega_platform.license._device_fingerprint_hash):
#
#     sha256(device_id + platform.system() + platform.machine()
#            + platform.node() + str(uuid.getnode()))
#
# uuid.getnode() returns the host's primary NIC MAC. Inside a Kubernetes pod on
# Cilium, every pod gets a freshly RANDOMIZED (locally-administered) MAC, so
# uuid.getnode() changes on every rollout. The fingerprint therefore changed
# each restart and the pro_tools gate failed ("bound to a different machine
# fingerprint") even after a successful `omega activate` — init-omega exit 1,
# CrashLoopBackOff.
#
# Pinning the MAC at the network layer was not possible: PodSecurity `baseline`
# (the cluster default) forbids hostNetwork, and Cilium 1.19 has no per-pod
# static-MAC annotation.
#
# THE FIX
# -------
# Python auto-imports a module named `sitecustomize` on interpreter startup if
# it is anywhere on sys.path. omega-init.sh drops this file into the PVC venv's
# site-packages, so both the init container (`omega activate`) and the app
# container (`omega serve`) load it before any OMEGA code runs. It replaces
# uuid.getnode() with a deterministic 48-bit value derived from a random seed
# persisted on the PVC (.omega/.node_seed). The PVC is openebs-hostpath RWO and
# the pod is node-pinned, so the seed — and thus the fingerprint — is stable
# for the life of the volume, independent of the pod's real (random) MAC.
#
# Removing this file (or the OMEGA_STABLE_NODE=0 escape hatch) restores stock
# behavior; the license then re-binds to whatever MAC the next activation sees.

import os
import uuid


def _seed_dir():
    # Mirror omega-serve.sh / omega-init.sh: OMEGA_HOME, else $HOME/.omega.
    home = os.environ.get("OMEGA_HOME")
    if home:
        return home
    return os.path.join(os.path.expanduser("~"), ".omega")


def _stable_node():
    """Deterministic 48-bit node id from a PVC-persisted seed.

    Returns a valid locally-administered unicast MAC encoded as an int, the
    same shape uuid.getnode() yields. Falls back to the real getnode() on any
    error so a seed-write failure degrades to stock behavior rather than
    crashing the interpreter.
    """
    import hashlib

    try:
        d = _seed_dir()
        os.makedirs(d, exist_ok=True)
        seed_file = os.path.join(d, ".node_seed")
        if os.path.exists(seed_file):
            with open(seed_file) as fh:
                seed = fh.read().strip()
        else:
            seed = uuid.uuid4().hex
            with open(seed_file, "w") as fh:
                fh.write(seed)
            try:
                os.chmod(seed_file, 0o600)
            except OSError:
                pass
        node = int.from_bytes(hashlib.sha256(seed.encode()).digest()[:6], "big")
        # First octet bits: bit 40 = multicast (clear -> unicast),
        # bit 41 = locally administered (set). Yields a valid LAA unicast MAC.
        node |= 1 << 41
        node &= ~(1 << 40)
        return node
    except Exception:
        return _ORIG_GETNODE()


_ORIG_GETNODE = uuid.getnode

if os.environ.get("OMEGA_STABLE_NODE", "1") != "0":
    uuid.getnode = _stable_node
