"""neurobench domain.

Neurobench uses sys.path insertion because its package name is 'app' (bare).
Its routers carry no prefix — prefixes are applied when including them.

Neurobench's app/config.py has been updated with extra="ignore" so that
suite-level env vars (SUITE_API_PORT, NEUROCNL_PORT, etc.) in the root .env
do not cause ValidationError when loading Settings().
"""

import sys
from pathlib import Path

# Ensure 'app' resolves to Neurobench's app package
_nb_path = Path(__file__).parents[3] / "Neurobench" / "neurobench"
if str(_nb_path) not in sys.path:
    sys.path.insert(0, str(_nb_path))
