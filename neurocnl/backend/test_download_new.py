import asyncio
import os

os.environ["NEUROCNL_FIREBASE_BUCKET"] = "nmtk-41e11.firebasestorage.app"
os.environ["NEUROCNL_DATA_DIR"] = "/tmp/test_cnl_data_new"
from app.services.dataset_cache import dataset_cache


async def main():
    await dataset_cache.initialize()
    try:
        res = await dataset_cache.ensure_downloaded("davis-24-77dbc2f97a7c")
        print("SUCCESS:", res)
    except Exception as e:
        print("FAILED:", type(e).__name__, str(e))


asyncio.run(main())
