import json
import urllib.request

bucket = "nmtk-41e11.firebasestorage.app"
url = f"https://firebasestorage.googleapis.com/v0/b/{bucket}/o"

req = urllib.request.Request(url)
try:
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        for item in data.get("items", []):
            if "size" in item:
                print(f"{item['name']}: {item['size']}")
except Exception as e:
    print(e)
