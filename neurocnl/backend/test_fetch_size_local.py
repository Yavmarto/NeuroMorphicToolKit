from app.services.dataset_catalog import _fetch_size, _firebase_endpoint

bucket = "nmtk-41e11.firebasestorage.app"
name = "Davis 24/Davis346blue-2018-12-07T13-56-01+0100-00000001-0 disk high BW pr.aedat"
print(f"URL: {_firebase_endpoint(bucket, storage_path=name)}")
print(f"Size: {_fetch_size(bucket, name)}")
