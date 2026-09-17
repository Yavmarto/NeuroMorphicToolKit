import os

os.environ["NEUROCNL_FIREBASE_BUCKET"] = "nmtk-41e11.firebasestorage.app"
from app.services.dataset_catalog import load_dataset_catalog

catalog = load_dataset_catalog(refresh=True)
for entry in catalog.datasets:
    print(f"{entry.storage_path}: {entry.size_bytes}")
