import os

os.environ["NEUROCNL_FIREBASE_BUCKET"] = "nmtk-41e11.firebasestorage.app"
from app.services.dataset_catalog import load_dataset_catalog

catalog = load_dataset_catalog(refresh=True)
for e in catalog.datasets:
    if e.id == "davis-24-ec9adfc5218d":
        print("FOUND:", e.id, repr(e.storage_path))
        break
else:
    print("NOT FOUND")
