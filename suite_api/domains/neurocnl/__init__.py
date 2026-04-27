"""neurocnl domain — sys.path preamble.

The neurocnl backend package uses 'backend' as its top-level import name,
so we insert the neurocnl submodule root into sys.path before importing routers.
"""
import sys
from pathlib import Path

_backend_path = Path(__file__).parents[3] / "neurocnl"
if str(_backend_path) not in sys.path:
    sys.path.insert(0, str(_backend_path))
