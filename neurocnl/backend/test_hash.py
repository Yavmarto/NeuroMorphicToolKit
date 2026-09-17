import os

os.environ["NEUROCNL_FIREBASE_BUCKET"] = "nmtk-41e11.firebasestorage.app"
from app.services.dataset_catalog import _entry_id, load_dataset_catalog

catalog = load_dataset_catalog(refresh=True)
for e in catalog.datasets[:2]:
    print(repr(e.storage_path), e.id, _entry_id(e.folder_path, e.storage_path))
