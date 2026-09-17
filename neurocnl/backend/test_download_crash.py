import asyncio
import os

os.environ["NEUROCNL_FIREBASE_BUCKET"] = "nmtk-41e11.firebasestorage.app"
os.environ["NEUROCNL_DATA_DIR"] = "/tmp/test_cnl_data"
import traceback

from app.services.dataset_cache import dataset_cache


async def main():
    await dataset_cache.initialize()
    print("Initialized")
    try:
        res = await dataset_cache.ensure_downloaded("davis-24-ec9adfc5218d")
        print("Success:", res)
    except Exception as e:
        print("Crashed!")
        traceback.print_exc()


asyncio.run(main())
