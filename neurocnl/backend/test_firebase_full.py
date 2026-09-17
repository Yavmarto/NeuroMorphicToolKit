import json
import urllib.request

bucket = "nmtk-41e11.firebasestorage.app"
url = f"https://firebasestorage.googleapis.com/v0/b/{bucket}/o"
req = urllib.request.Request(url)
with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read().decode("utf-8"))
    print(json.dumps(data.get("items", [])[:2], indent=2))
