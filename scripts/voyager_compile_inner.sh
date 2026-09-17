#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq python3 python3-venv python3-pip curl libgl1 libglib2.0-0 > /dev/null

python3 -m venv /opt/venv
. /opt/venv/bin/activate
pip install -q --upgrade pip

echo "=== Installing axelera-devkit (compiler-only) ==="
pip install -q --no-cache-dir \
  --extra-index-url https://software.axelera.ai/artifactory/api/pypi/axelera-pypi/simple \
  axelera-devkit ultralytics onnx

python -c "import axelera; print('axelera-devkit import OK')"
command -v axcompile && axcompile --version 2>/dev/null || true

cd /work

echo "=== Step 1: Export YOLOv8n to ONNX ==="
python - <<'PY'
from ultralytics import YOLO
model = YOLO("yolov8n.pt")
model.export(format="onnx", imgsz=640, simplify=True)
import os
size = os.path.getsize("yolov8n.onnx")
print(f"ONNX export OK: yolov8n.onnx ({size} bytes)")
assert size > 1000, "ONNX file too small"
PY

echo "=== Step 2: axcompile ONNX -> compiled_model artifacts (optional) ==="
# ponytail: raw Ultralytics ONNX uses opset 18 Split nodes axcompile cannot import;
# Ultralytics format=axelera (step 3) is the supported path for YOLO.
if axcompile -i yolov8n.onnx -o compiled_axcompile/; then
  if [ -f compiled_axcompile/compiled_model/manifest.json ]; then
    echo "PASS: axcompile produced compiled_model/manifest.json"
  fi
else
  echo "SKIP: axcompile failed on default ONNX export (use Ultralytics axelera path below)"
  find compiled_axcompile -type f 2>/dev/null | head -10 || true
fi

echo "=== Step 3: Ultralytics export(format=axelera) -> .axm ==="
python - <<'PY'
from pathlib import Path
from ultralytics import YOLO

model = YOLO("yolov8n.pt")
result = model.export(format="axelera")
print("Ultralytics axelera export:", result)
axm_files = sorted(Path(".").rglob("*.axm"))
assert axm_files, "No .axm file produced"
for p in axm_files:
    print(f"PASS: {p} ({p.stat().st_size} bytes)")
PY

echo "=== Artifact summary ==="
find /work -name "*.axm" -o -name "manifest.json" | sort
