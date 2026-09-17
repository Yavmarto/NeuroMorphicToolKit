import json
import urllib.request
from urllib.parse import quote

bucket = "nmtk-41e11.firebasestorage.app"
files = [
    "datasets/mnist_spike/mnist_spike.h5",
    "datasets/nmnist/nmnist.h5",
    "datasets/dvs_gesture/dvs_gesture.h5",
    "datasets/shd/shd.h5",
    "datasets/ntidigits/ntidigits.h5",
]

for name in files:
    url = f"https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{quote(name, safe='')}"
    req = urllib.request.Request(url)
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            print(f"{name}: {data.get('size')}")
    except Exception as e:
        print(f"{name}: {e}")
