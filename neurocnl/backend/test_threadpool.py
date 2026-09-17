import json
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import quote

bucket = "nmtk-41e11.firebasestorage.app"


def get_size(name):
    url = f"https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{quote(name, safe='')}"
    req = urllib.request.Request(url)
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return name, data.get("size")
    except Exception as e:
        return name, None


names = [
    "Davis 24/Davis346blue-2018-12-07T13-56-01+0100-00000001-0 disk high BW pr.aedat",
    "Davis 24/Davis346blue-2018-12-30T04-44-31-0800-00000001-0- tobi juggling pasadena shorter.aedat",
    "Davis 24/Davis346blue-2019-01-14T14-20-34+0100-00000001-0 ramp up down.aedat",
    "Davis 24/Davis346blue-2019-06-18T12-28-04+0200-00000002-0 train bias control.aedat",
    "Davis 24/Davis346blue-2019-11-28T06-51-04+0100-00000003-0 blaine card change.aedat",
] * 4  # 20 files

start = time.time()
with ThreadPoolExecutor(max_workers=10) as executor:
    results = list(executor.map(get_size, names))

print(f"Time taken: {time.time() - start:.2f}s")
print(results[0])
