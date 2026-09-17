"""NMTK environment manager — a Jupyter Server extension.

Exposes a small REST API under ``<base_url>/nmtk-envs/api/`` for cloning the
immutable NeuroStudio base kernel into customisable per-user environments,
installing packages into them, and exporting/importing ``requirements.txt`` to
share an environment. New environments register Jupyter kernelspecs, so they
appear automatically in the JupyterLab launcher.
"""
from __future__ import annotations

__version__ = "0.1.0"


def _jupyter_server_extension_points() -> list[dict]:
    return [{"module": "nmtk_env_manager"}]


def _load_jupyter_server_extension(server_app) -> None:
    """Entry point invoked by Jupyter Server when the extension is enabled."""
    # Imported lazily so ``nmtk_env_manager.manager`` stays importable (for unit
    # tests) without tornado / jupyter_server present.
    from .handlers import register_handlers
    from .manager import EnvironmentManager

    # Provision per-framework kernels idempotently before accepting requests.
    # With --system-site-packages, each venv create takes ~100 ms; 8 envs ≈ <1 s.
    mgr = EnvironmentManager()
    try:
        mgr.provision_framework_envs()
        server_app.log.info(
            "[nmtk_env_manager] Framework environments provisioned."
        )
    except Exception as exc:  # noqa: BLE001 - never block Jupyter startup
        server_app.log.warning(
            "[nmtk_env_manager] Framework env provisioning failed (non-fatal): %s", exc
        )

    register_handlers(server_app)


# Backwards-compatible alias for older Jupyter Server discovery.
load_jupyter_server_extension = _load_jupyter_server_extension
