#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_DIR="${ARTIFACT_DIR:-./voyager-compile-out}"
AXM="$(find "$ARTIFACT_DIR" -name '*.axm' -type f | head -1 || true)"

if [[ -z "$AXM" ]]; then
  echo "ERROR: no .axm under $ARTIFACT_DIR — run 'make voyager-compile-spike' first." >&2
  exit 1
fi

echo "Using compiled artifact: $AXM"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 required." >&2
  exit 1
fi

VENV="${VOYAGER_AIPU_VENV:-/tmp/voyager-aipu-venv}"
if [[ ! -d "$VENV" ]]; then
  python3 -m venv "$VENV"
fi
# shellcheck disable=SC1091
source "$VENV/bin/activate"
pip install -q --upgrade pip
pip install -q --no-cache-dir \
  --extra-index-url https://software.axelera.ai/artifactory/api/pypi/axelera-pypi/simple \
  axelera-rt opencv-python-headless onnxruntime ultralytics

if command -v axdevice >/dev/null 2>&1; then
  echo "=== axdevice ==="
  axdevice || axdevice --refresh || true
else
  echo "WARN: axdevice not on PATH; driver may not be installed yet."
fi

python - <<'PY' "$AXM"
import sys
import time
import urllib.request
from pathlib import Path

import cv2
from axelera.runtime import op

axm = Path(sys.argv[1])
assert axm.is_file(), axm

urllib.request.urlretrieve(
    "https://github.com/ultralytics/assets/releases/download/v0.0.0/bus.jpg",
    "bus.jpg",
)
image = cv2.imread("bus.jpg")
assert image is not None

cpu_pipeline = op.seq(
    op.color_convert("RGB", src="BGR"),
    op.letterbox(640, 640),
    op.to_tensor(),
    op.onnx_model("yolov8n.onnx", provider="cpu"),
    op.decode_detections(algo="yolov8", num_classes=80),
    op.nms(),
    op.to_image_space(),
    op.ax_detection(class_id_type=op.CocoClasses),
)

# ponytail: export ONNX once if missing; avoids re-downloading weights on every spike run.
if not Path("yolov8n.onnx").exists():
    from ultralytics import YOLO

    YOLO("yolov8n.pt").export(format="onnx", imgsz=640, simplify=True)

aipu_pipeline = op.seq(
    op.color_convert("RGB", src="BGR"),
    op.letterbox(640, 640),
    op.to_tensor(),
    op.load(str(axm)),
    op.decode_detections(algo="yolov8", num_classes=80),
    op.nms(),
    op.to_image_space(),
    op.ax_detection(class_id_type=op.CocoClasses),
)

def bench(name, pipeline):
    t0 = time.perf_counter()
    dets = pipeline(image)
    ms = (time.perf_counter() - t0) * 1000
    print(f"{name}: {len(dets)} detections in {ms:.1f} ms")
    for d in dets[:5]:
        print(f"  {d.class_id.name} {d.score:.3f}")
    return ms, len(dets)

print("=== CPU baseline (Phase 1 path) ===")
cpu_ms, cpu_n = bench("cpu_onnx", cpu_pipeline)

print("=== AIPU path (Phase 3) ===")
aipu_ms, aipu_n = bench("aipu_axm", aipu_pipeline)

speedup = cpu_ms / aipu_ms if aipu_ms > 0 else float("inf")
print(f"=== Summary: AIPU {speedup:.2f}x vs CPU on bus.jpg ===")
assert aipu_n > 0, "AIPU path returned zero detections"
PY

echo "=== CEL-238 AIPU spike PASS ==="
