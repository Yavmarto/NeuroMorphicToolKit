"""Launcher control service package."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from .server import LauncherControlServer

__all__ = ["LauncherControlServer", "create_server"]


def __getattr__(name: str) -> Any:
    """Load public server exports lazily so service modules stay independent."""
    if name in __all__:
        from .server import LauncherControlServer, create_server

        exports = {
            "LauncherControlServer": LauncherControlServer,
            "create_server": create_server,
        }
        return exports[name]
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
