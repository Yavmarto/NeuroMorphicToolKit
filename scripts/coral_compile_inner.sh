#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq curl gnupg python3 python3-venv python3-pip libgl1 libglib2.0-0 libusb-1.0-0 > /dev/null

echo "=== Installing edgetpu-compiler (Coral apt repo) ==="
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
  | gpg --dearmor -o /usr/share/keyrings/coral-edgetpu.gpg
echo "deb [signed-by=/usr/share/keyrings/coral-edgetpu.gpg] https://packages.cloud.google.com/apt coral-edgetpu-stable main" \
  > /etc/apt/sources.list.d/coral-edgetpu.list
apt-get update -qq
apt-get install -y -qq edgetpu-compiler > /dev/null
command -v edgetpu_compiler
edgetpu_compiler --version 2>/dev/null || edgetpu_compiler --help 2>&1 | head -3

python3 -m venv /opt/venv
. /opt/venv/bin/activate
pip install -q --upgrade pip
# ponytail: Ultralytics 8.4+ redirects format=tflite to LiteRT (broken in container);
# 8.3.x uses TensorFlow SavedModel -> INT8 TFLite -> edgetpu_compiler.
pip install -q --no-cache-dir \
  "ultralytics==8.3.59" onnxscript onnx onnx2tf tf_keras tflite_support \
  onnxslim sng4onnx onnx_graphsurgeon onnxruntime

cd /work

echo "=== Step 1: Export YOLOv8n to INT8 TFLite (generic intermediate) ==="
python - <<'PY'
from pathlib import Path
from ultralytics import YOLO

model = YOLO("yolov8n.pt")
result = model.export(format="tflite", int8=True)
print("Ultralytics tflite export:", result)
tflite_files = sorted(Path(".").rglob("*full_integer_quant.tflite"))
assert tflite_files, "No *_full_integer_quant.tflite produced"
for p in tflite_files:
    if "_edgetpu" not in p.name:
        print(f"PASS: {p} ({p.stat().st_size} bytes)")
PY

TFLITE="$(find /work -name '*full_integer_quant.tflite' ! -name '*_edgetpu.tflite' | head -1)"
test -n "$TFLITE"

echo "=== Step 2: edgetpu_compiler on INT8 TFLite (generic compile path) ==="
TFLITE_DIR="$(dirname "$TFLITE")"
TFLITE_BASE="$(basename "$TFLITE" .tflite)"
cd "$TFLITE_DIR"
edgetpu_compiler -s "$(basename "$TFLITE")"
EDGETPU="${TFLITE_BASE}_edgetpu.tflite"
test -f "$EDGETPU"
echo "PASS: edgetpu_compiler produced $TFLITE_DIR/$EDGETPU ($(stat -c%s "$EDGETPU") bytes)"
cd /work

echo "=== Step 3: Ultralytics export(format=edgetpu) integrated path ==="
python - <<'PY'
from pathlib import Path
from ultralytics import YOLO

model = YOLO("yolov8n.pt")
result = model.export(format="edgetpu")
print("Ultralytics edgetpu export:", result)
edgetpu_files = sorted(Path(".").rglob("*_edgetpu.tflite"))
assert edgetpu_files, "No *_edgetpu.tflite from format=edgetpu"
for p in edgetpu_files:
    print(f"PASS: {p} ({p.stat().st_size} bytes)")
PY

echo "=== Artifact summary ==="
find /work -name '*_edgetpu.tflite' -o -name '*full_integer_quant.tflite' | sort
