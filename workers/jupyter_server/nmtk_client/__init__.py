"""NMTK notebook client — thin HTTP wrappers for backend services.

Quick start::

    from nmtk_client import lava, suite

    # Check everything is reachable
    print(suite.health())
    print(lava.health())

    # Run a Lava simulation
    session = lava.compile(
        populations=[{"name": "pop", "size": 8, "threshold": 1.0}],
        connections=[],
    )
    results = lava.run(session, steps=200)
    lava.stop(session)
"""
from __future__ import annotations

from . import lava, suite
from ._base import NmtkConnectionError

__all__ = ["NmtkConnectionError", "lava", "suite"]
