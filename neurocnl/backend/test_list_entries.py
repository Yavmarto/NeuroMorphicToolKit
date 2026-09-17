import asyncio
import os

os.environ["NEUROCNL_FIREBASE_BUCKET"] = "nmtk-41e11.firebasestorage.app"

from app.services.dataset_cache import dataset_cache


async def main():
    await dataset_cache.initialize()
    entries = await dataset_cache.list_entries()
    for e in entries[:2]:
        print(e["id"], e["size_bytes"])


asyncio.run(main())
