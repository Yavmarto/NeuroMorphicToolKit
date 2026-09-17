"""Shared probes for Studio target / framework SDK availability.

Used by ``/notebook/target-availability`` and simulator capability checks so
install surfaces and runtime probes stay aligned.
"""

from __future__ import annotations

import importlib.util
import os
from typing import Final

# Target id -> importable module name.  Lava targets are handled separately.
TARGET_SDK_MODULES: Final[dict[str, str]] = {
    "brian2_sim": "brian2",
    "nengo_sim": "nengo",
    "sinabs_sim": "sinabs",
    "snntorch_sim": "snntorch",
    "sc_neurocore_sim": "sc_neurocore",
    "sc_neurocore_fpga": "sc_neurocore",
    "akida": "akida",
    "brian2": "brian2",
    "sinabs": "sinabs",
    "rockpool": "rockpool",
    "pynn": "pyNN",
    "nengo": "nengo",
}

# Keys returned by ``probe_target_availability`` (must cover Studio deploy targets).
TARGET_AVAILABILITY_KEYS: Final[tuple[str, ...]] = (
    "lava_sim",
    "lava",
    "brian2_sim",
    "nengo_sim",
    "sinabs_sim",
    "snntorch_sim",
    "sc_neurocore_sim",
    "sc_neurocore_fpga",
    "akida",
    "brian2",
    "sinabs",
    "rockpool",
    "pynn",
    "nengo",
    "generic",
)


def lava_worker_url() -> str | None:
    """Return the configured Lava worker URL, treating blank env values as unset."""
    value = os.getenv("NEUROCNL_LAVA_WORKER_URL")
    return value.strip() if value and value.strip() else None


def brian2_worker_url() -> str | None:
    """Return the configured Brian2 worker URL, treating blank env values as unset."""
    value = os.getenv("NEUROCNL_BRIAN2_WORKER_URL")
    return value.strip() if value and value.strip() else None


def module_importable(module_name: str) -> bool:
    """Return True when *module_name* can be imported in the active interpreter.

    ``find_spec`` alone is not sufficient: it only confirms the module is
    findable on disk, not that importing it actually succeeds — a package
    with a broken/mismatched native extension (e.g. a torch install whose
    compiled ``torch._C`` doesn't match) has a resolvable spec but raises on
    import. Relying on ``find_spec`` alone made capability/dispatch-gate
    checks report "available" for a package that then failed for real at
    dispatch time, producing a dispatch-failure 422 where callers expect a
    clean "missing dependency" 503.
    """
    try:
        importlib.import_module(module_name)
        return True
    except ImportError:
        return False


def lava_worker_reachable() -> bool:
    """Return True when the isolated Lava worker health endpoint responds."""
    worker_url = lava_worker_url()
    if not worker_url:
        return False
    try:
        import httpx  # noqa: PLC0415
    except ImportError:
        return False

    health_url = f"{worker_url.rstrip('/')}/health"
    try:
        response = httpx.get(health_url, timeout=2.0)
    except httpx.HTTPError:
        return False
    if response.status_code != 200:
        return False
    try:
        payload = response.json()
    except ValueError:
        return True
    if isinstance(payload, dict) and "lava_importable" in payload:
        return bool(payload.get("lava_importable"))
    return True


def brian2_worker_reachable() -> bool:
    """Return True when the isolated Brian2 worker health endpoint responds."""
    worker_url = brian2_worker_url()
    if not worker_url:
        return False
    try:
        import httpx  # noqa: PLC0415
    except ImportError:
        return False

    health_url = f"{worker_url.rstrip('/')}/health"
    try:
        response = httpx.get(health_url, timeout=2.0)
    except httpx.HTTPError:
        return False
    if response.status_code != 200:
        return False
    try:
        payload = response.json()
    except ValueError:
        return True
    if isinstance(payload, dict) and "brian2_importable" in payload:
        return bool(payload.get("brian2_importable"))
    return True


def brian2_available(*, strict: bool = False) -> bool:
    """Brian2 is available in-process or via the dedicated brian2-backend worker."""
    if module_importable("brian2"):
        return True
    if strict:
        return brian2_worker_reachable()
    if brian2_worker_url():
        return True
    return brian2_worker_reachable()


def lava_available(*, strict: bool = False) -> bool:
    """Lava is available in-process or via the dedicated lava-backend worker.

    When *strict* is True (Studio target picker), the worker must respond to
    ``/health``.  Otherwise a configured ``NEUROCNL_LAVA_WORKER_URL`` is enough
    for simulator capability/run gating.
    """
    if module_importable("lava"):
        return True
    if strict:
        return lava_worker_reachable()
    if lava_worker_url():
        return True
    return lava_worker_reachable()


def probe_target_availability() -> dict[str, bool]:
    """Return availability for every Studio notebook / deploy target."""
    lava_ok = lava_available(strict=True)
    brian2_ok = brian2_available(strict=True)
    result: dict[str, bool] = {
        "lava_sim": lava_ok,
        "lava": lava_ok,
        "brian2_sim": brian2_ok,
        "generic": True,
    }
    for target_id, module_name in TARGET_SDK_MODULES.items():
        result[target_id] = module_importable(module_name)
    return result
