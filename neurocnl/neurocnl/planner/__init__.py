"""Advisory backend planner for IR support classification.

Split by planning phase: generic advisory support classification
(``_support``) and the three fail-closed per-backend deployability
planners (``_teensy``, ``_pynq``, ``_akida``). This module re-exports the
combined public API so existing ``from neurocnl.planner import ...``
call sites keep working unchanged.
"""

from __future__ import annotations

from neurocnl.network_facts import DEFAULT_POPULATION_SIZE as _DEFAULT_POPULATION_SIZE
from neurocnl.network_facts import is_port_population as _is_port_population

from ._akida import plan_akida_exportability
from ._pynq import plan_pynq_exportability
from ._support import PlannerResult, plan_backend_support
from ._teensy import plan_teensy_deployability

__all__ = [
    "PlannerResult",
    "plan_backend_support",
    "plan_teensy_deployability",
    "plan_pynq_exportability",
    "plan_akida_exportability",
    # Compatibility re-exports; imported externally as `neurocnl.planner._DEFAULT_POPULATION_SIZE`
    # and `neurocnl.planner._is_port_population`.
    "_DEFAULT_POPULATION_SIZE",
    "_is_port_population",
]
