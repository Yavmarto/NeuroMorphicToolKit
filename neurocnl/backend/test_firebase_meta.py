import json
import urllib.request
from urllib.parse import quote

bucket = "nmtk-41e11.firebasestorage.app"
name = "Davis 24/Davis346blue-2018-12-07T13-56-01+0100-00000001-0 disk high BW pr.aedat"
url = f"https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{quote(name, safe='')}"
req = urllib.request.Request(url)
with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read().decode("utf-8"))
    print(f"Size: {data.get('size')}")
