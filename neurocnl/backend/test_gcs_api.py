import json
import urllib.request

bucket = "nmtk-41e11.firebasestorage.app"
url = f"https://storage.googleapis.com/storage/v1/b/{bucket}/o?prefix=Davis%2024/&delimiter=/"
req = urllib.request.Request(url)
try:
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        print(json.dumps(data.get("items", [])[:1], indent=2))
except Exception as e:
    print(e)
