import asyncio
import os
from pathlib import Path

from app.services.dataset_cache import dataset_cache

os.environ["NEUROCNL_DATA_DIR"] = "/tmp/test_cnl_data_missing"
DATA_DIR = Path("/tmp/test_cnl_data_missing")
DATA_DIR.mkdir(parents=True, exist_ok=True)
db_path = DATA_DIR / "datasets.db"
if db_path.exists():
    db_path.unlink()


async def main():
    try:
        await dataset_cache.get_ready_path("some_id")
    except Exception as e:
        print("CRASHED:", type(e).__name__, str(e))


asyncio.run(main())
