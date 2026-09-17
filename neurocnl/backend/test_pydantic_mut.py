from app.services.dataset_catalog import FirebaseStorageObject

obj = FirebaseStorageObject(name="test")
obj.size_bytes = 123
print(obj.size_bytes)
