"""Root conftest for neurocnl package tests.

Adds source directories to sys.path so that tests can import modules
without requiring package installation.
"""

import sys
from pathlib import Path

# Add source directories and the package root to sys.path
root = Path(__file__).parent.parent
root_str = str(root)
if root_str not in sys.path:
    sys.path.insert(0, root_str)
