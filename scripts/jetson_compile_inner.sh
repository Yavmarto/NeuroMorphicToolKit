#!/usr/bin/env bash
# ponytail: CEL-246 compile-only — TensorRT graph parse on any NVIDIA GPU host.
# Upgrade path: Jetson Orin board spike (Phase 4a) for real .engine + benchmark.
set -euo pipefail

cd /work

echo "=== Step 0: Environment ==="
python3 -c "import tensorrt as trt; print('TensorRT', trt.__version__)"
command -v trtexec && trtexec --version 2>/dev/null | head -3 || true

echo "=== Step 1: Export YOLOv8n to ONNX (opset 17, Jetson-friendly) ==="
python3 - <<'PY'
from ultralytics import YOLO

model = YOLO("yolov8n.pt")
# ponytail: opset 17 is the safe middle ground for JetPack 6.x TensorRT 10.x.
model.export(format="onnx", imgsz=640, simplify=True, opset=17)
import os

size = os.path.getsize("yolov8n.onnx")
print(f"ONNX export OK: yolov8n.onnx ({size} bytes)")
assert size > 1000, "ONNX file too small"
PY

echo "=== Step 2: ONNX structural check ==="
python3 - <<'PY'
import onnx

model = onnx.load("yolov8n.onnx")
onnx.checker.check_model(model)
print("ONNX checker OK")
print(f"IR version: {model.ir_version}, opset: {model.opset_import[0].version}")
PY

echo "=== Step 3: TensorRT parse (trtexec --skipInference) ==="
# Builds the TensorRT network without running inference; catches unsupported ops.
trtexec --onnx=yolov8n.onnx --skipInference --saveEngine=yolov8n_desktop.engine

if [[ -f yolov8n_desktop.engine ]]; then
  size=$(stat -c%s yolov8n_desktop.engine 2>/dev/null || stat -f%z yolov8n_desktop.engine)
  echo "PASS: TensorRT engine built ($size bytes) — graph is TensorRT-parseable"
else
  echo "FAIL: trtexec did not produce an engine file" >&2
  exit 1
fi

echo "=== Step 4: ONNX Runtime TensorRT EP session (compile check) ==="
python3 - <<'PY'
import numpy as np
import onnxruntime as ort

providers = ort.get_available_providers()
print("ORT providers:", providers)
if "TensorrtExecutionProvider" not in providers:
    raise SystemExit("SKIP: TensorrtExecutionProvider not available")

sess = ort.InferenceSession(
    "yolov8n.onnx",
    providers=[
        (
            "TensorrtExecutionProvider",
            {
                "trt_engine_cache_enable": True,
                "trt_engine_cache_path": "/work/ort_trt_cache",
            },
        ),
        "CUDAExecutionProvider",
    ],
)
inp = sess.get_inputs()[0]
dummy = np.zeros((1, 3, 640, 640), dtype=np.float32)
sess.run(None, {inp.name: dummy})
print("PASS: ORT TensorRT EP built session and ran one inference")
PY

echo "=== Artifact summary ==="
find /work -maxdepth 2 \( -name "*.onnx" -o -name "*.engine" \) -print | sort
