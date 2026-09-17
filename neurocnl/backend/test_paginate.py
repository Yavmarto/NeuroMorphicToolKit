import os

os.environ["NEUROCNL_FIREBASE_BUCKET"] = "nmtk-41e11.firebasestorage.app"
from urllib.parse import quote

from app.services.dataset_catalog import _firebase_endpoint, _read_json

bucket = "nmtk-41e11.firebasestorage.app"
url = f"{_firebase_endpoint(bucket)}?prefix={quote('Davis 24/', safe='')}&delimiter=/"
payload = _read_json(url)
print("Items:", len(payload.get("items", [])))
print("Next token:", payload.get("nextPageToken"))
