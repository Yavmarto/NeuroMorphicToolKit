import os

os.environ["NEUROCNL_FIREBASE_BUCKET"] = "nmtk-41e11.firebasestorage.app"
os.environ["NEUROCNL_DATA_DIR"] = "/tmp/test_cnl_data_2"
from app.services.dataset_catalog import load_dataset_catalog

catalog = load_dataset_catalog(refresh=True)
ids = [e.id for e in catalog.datasets]
print("Is 2ab12514b739 in catalog?:", "davis-24-2ab12514b739" in ids)
print(ids)
