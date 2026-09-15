#!/usr/bin/env bash
set -eo pipefail
export DEBIAN_FRONTEND=noninteractive
export PYTHONPATH="${PYTHONPATH-}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH-}"

if [[ -z "${QAIRT_SDK_ROOT:-}" || ! -f "${QAIRT_SDK_ROOT}/bin/envsetup.sh" ]]; then
  echo "ERROR: mounted QAIRT_SDK_ROOT missing envsetup.sh"
  exit 1
fi

apt-get update -qq
apt-get install -y -qq \
  python3 python3-venv python3-pip curl wget ca-certificates lsb-release time \
  clang-14 llvm-14 lld-14 > /dev/null

# ponytail: SDK setup scripts own the exact apt/python pins; we only bootstrap enough to run them.
source "${QAIRT_SDK_ROOT}/bin/envsetup.sh"
if [[ -x "${QNN_SDK_ROOT}/bin/check-linux-dependency.sh" ]]; then
  bash "${QNN_SDK_ROOT}/bin/check-linux-dependency.sh"
fi

python3 -m venv /opt/venv
. /opt/venv/bin/activate
pip install -q --upgrade pip
if [[ -x "${QNN_SDK_ROOT}/bin/check-python-dependency" ]]; then
  "${QNN_SDK_ROOT}/bin/check-python-dependency"
fi
# ponytail: ultralytics wants numpy 2.x but SDK-pinned opencv needs numpy 1.x — keep SDK pin.
pip install -q onnx onnxruntime ultralytics "numpy<2"

python - <<'PY'
import importlib.metadata as md
for pkg in ("onnx", "onnxruntime", "ultralytics", "numpy"):
    print(f"{pkg}: {md.version(pkg)}")
PY

cd /work
QNN_BIN="${QNN_SDK_ROOT}/bin/x86_64-linux-clang"
QNN_LIB="${QNN_SDK_ROOT}/lib/x86_64-linux-clang"
export LD_LIBRARY_PATH="${QNN_LIB}:${LD_LIBRARY_PATH:-}"
export PATH="${QNN_BIN}:${PATH}"

echo "=== Step 1: Export YOLOv8n ONNX (shared with Voyager spikes) ==="
/usr/bin/time -f "export_seconds=%e" -o export_timing.txt python - <<'PY'
from ultralytics import YOLO
import os

model = YOLO("yolov8n.pt")
model.export(format="onnx", imgsz=640, simplify=True)
size = os.path.getsize("yolov8n.onnx")
print(f"ONNX export OK: yolov8n.onnx ({size} bytes)")
assert size > 1000
PY
cat export_timing.txt

echo "=== Step 2: Discover ONNX input tensor ==="
python - <<'PY' > onnx_input_meta.env
import onnx

model = onnx.load("yolov8n.onnx")
inp = model.graph.input[0]
name = inp.name
shape = []
for dim in inp.type.tensor_type.shape.dim:
    shape.append(int(dim.dim_value) if dim.dim_value > 0 else 1)
print(f"INPUT_NAME={name}")
print(f"INPUT_SHAPE={','.join(str(x) for x in shape)}")
PY
# shellcheck disable=SC1091
source onnx_input_meta.env
echo "input=${INPUT_NAME} shape=${INPUT_SHAPE}"

echo "=== Step 3: qnn-onnx-converter ==="
# ponytail: QNN 2.47 converter expects legacy onnx.version API — downgrade after Ultralytics export.
pip install -q "onnx==1.16.2"
/usr/bin/time -f "convert_seconds=%e" -o convert_timing.txt \
  "${QNN_BIN}/qnn-onnx-converter" \
  --input_network yolov8n.onnx \
  --output_path yolov8n.cpp \
  --input_dim "${INPUT_NAME}" "${INPUT_SHAPE}"
cat convert_timing.txt
test -s yolov8n.cpp
test -s yolov8n.bin

echo "=== Step 4: qnn-model-lib-generator ==="
/usr/bin/time -f "compile_seconds=%e" -o compile_timing.txt \
  "${QNN_BIN}/qnn-model-lib-generator" \
  -c yolov8n.cpp \
  -b yolov8n.bin \
  -o model_libs \
  -t x86_64-linux-clang
cat compile_timing.txt
MODEL_SO="$(find model_libs -name 'lib*.so' | head -1)"
test -n "$MODEL_SO"

echo "=== Step 5: Prepare CPU input_list ==="
python - <<'PY'
import os
import numpy as np
import onnx

model = onnx.load("yolov8n.onnx")
inp = model.graph.input[0]
name = inp.name
shape = []
for dim in inp.type.tensor_type.shape.dim:
    shape.append(int(dim.dim_value) if dim.dim_value > 0 else 1)
arr = np.random.rand(*shape).astype(np.float32)
raw_path = os.path.abspath("input0.raw")
arr.tofile(raw_path)
with open("input_list.txt", "w", encoding="utf-8") as f:
    f.write(f"{name}:= {raw_path}\n")
print(f"input_list for {name} shape={shape} bytes={os.path.getsize(raw_path)}")
PY

echo "=== Step 6: qnn-net-run on libQnnCpu.so ==="
/usr/bin/time -f "infer_seconds=%e" -o infer_timing.txt \
  "${QNN_BIN}/qnn-net-run" \
  --model "$MODEL_SO" \
  --backend "${QNN_LIB}/libQnnCpu.so" \
  --input_list input_list.txt \
  --output_dir output_cpu
cat infer_timing.txt

python - <<'PY'
from pathlib import Path

def read_seconds(path: str) -> float:
    text = Path(path).read_text(encoding="utf-8").strip()
    for line in text.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            if key.endswith("seconds"):
                return float(value)
    return float(text.split()[-1])

parts = {
    "export": read_seconds("export_timing.txt"),
    "convert": read_seconds("convert_timing.txt"),
    "compile": read_seconds("compile_timing.txt"),
    "infer": read_seconds("infer_timing.txt"),
}
parts["total"] = sum(parts.values())
lines = [f"{k}_seconds={v:.3f}" for k, v in parts.items()]
Path("timing_summary.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
print("PASS: QNN CPU spike completed")
for line in lines:
    print(line)
PY

echo "=== Artifact summary ==="
find /work -maxdepth 3 \( -name '*.so' -o -name 'timing_summary.txt' -o -name 'yolov8n.onnx' \) | sort
