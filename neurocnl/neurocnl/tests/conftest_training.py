"""Isolated conftest for training_registry tests.

This conftest allows running the training_registry test suite WITHOUT
installing the full neurocnl package (which requires nengo, numpy, etc).

The training_registry module only imports from stdlib (dataclasses, enum, typing),
so it can be tested in total isolation from the rest of neurocnl.

Usage (from neurocnl/ root):
    PYTHONPATH=neurocnl python -m pytest neurocnl/tests/test_training_registry.py -v --override-ini="confcutdir=neurocnl/tests"

If the root conftest still gets picked up, use:
    python -m pytest neurocnl/tests/test_training_registry.py -v -p no:conftest --override-ini="confcutdir=neurocnl/tests"
"""

import sys
from pathlib import Path

# Add ONLY the package directory, not the project root.
# This allows "from neurocnl.training_registry import ..." to work
# without triggering neurocnl.__init__.py's heavy imports.
_package_dir = Path(__file__).resolve().parent.parent
if str(_package_dir) not in sys.path:
    sys.path.insert(0, str(_package_dir))
