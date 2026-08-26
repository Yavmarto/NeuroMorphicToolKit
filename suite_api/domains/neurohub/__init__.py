"""neurohub domain.

The neurohub package is installed as a top-level package (pip install -e Neurohub/).
All routers carry no prefix themselves — the original main.py applies
prefix="/api/neurohub" at include_router time.

Neurohub's lifespan (Alembic migrations + workflow worker loop) is migrated
into suite_api's lifespan via the neurohub_startup / neurohub_shutdown helpers
defined in suite_api/domains/neurohub/lifespan.py.

The NEUROHUB_DB_URL env var is set here (before neurohub imports run) so that
neurohub.db.database picks up the correct SQLite path.
"""

import os

from suite_api.storage import default_neurohub_db_url

# Neurohub's database engine is initialised at import time via os.getenv().
# We must set NEUROHUB_DB_URL *before* the neurohub package is first imported.
if "NEUROHUB_DB_URL" not in os.environ:
    os.environ["NEUROHUB_DB_URL"] = default_neurohub_db_url()
