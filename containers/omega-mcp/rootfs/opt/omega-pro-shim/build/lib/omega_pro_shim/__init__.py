"""Local capability shim for omega_memory_pro.

The omega_memory_pro wheel (1.5.x) ships the omega_platform code but registers
no `omega.plugins` entry point advertising the `pro_tools` capability. Core
gates Pro-tool loading on that capability (it deliberately does not trust the
license file alone), so all Pro tools stay dark despite a valid license.

This package registers the missing entry point. It advertises `pro_tools` only
when omega_platform is importable AND the license validates as Pro, so the shim
cannot unlock entitlement on its own — it just bridges the packaging gap.

Upstream bug: https://github.com/omega-memory/omega-memory/issues/63
Remove this shim once the upstream wheel ships its own entry point.
"""

from __future__ import annotations

import logging

from omega.plugins import OmegaPlugin

logger = logging.getLogger("omega.pro_shim")


def _license_is_pro() -> bool:
    """Return True only when omega_platform confirms an active Pro license."""
    try:
        from omega_platform.license import is_pro
    except ImportError:
        return False
    try:
        return bool(is_pro())
    except Exception as exc:  # never let a shim crash MCP startup
        logger.debug("is_pro() check failed: %s", exc)
        return False


class ProCapabilityShim(OmegaPlugin):
    """Advertise the `pro_tools` capability when entitlement is genuine.

    Schemas/handlers stay empty on purpose: core's _BUILTIN_MODULES loop in
    mcp_server.py imports omega_platform.* directly once the gate opens. The
    shim only needs to flip has_capability("pro_tools") to True.
    """

    @property
    def CAPABILITIES(self) -> set[str]:
        return {"pro_tools"} if _license_is_pro() else set()
