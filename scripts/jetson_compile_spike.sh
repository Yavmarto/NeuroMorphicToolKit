#!/usr/bin/env bash
# ponytail: CEL-246 compiler-only spike — NVIDIA GPU host + Docker, no Jetson board.
# Upgrade path: optional CI job on Linux+GPU runner; Jetson hardware spike is Phase 4a.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${1:-./jetson-compile-out}"
IMAGE="${JETSON_COMPILE_IMAGE:-nvcr.io/nvidia/tensorrt:24.08-py3}"

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker daemon is not running." >&2
  exit 1
fi

GPU_ARGS=()
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  GPU_ARGS=(--gpus all)
  echo "NVIDIA GPU detected via nvidia-smi"
elif docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
  GPU_ARGS=(--gpus all)
  echo "NVIDIA GPU detected via Docker --gpus all"
else
  echo "BLOCKED: no NVIDIA GPU visible to Docker." >&2
  echo "This spike needs any x86/ARM Linux host with an NVIDIA GPU and nvidia-container-toolkit." >&2
  echo "Jetson board is NOT required for this phase — desktop GPU is enough for TensorRT parse validation." >&2
  echo "See: current tasks/2026-09-15/CEL-246-jetson-compile-findings.md" >&2
  exit 2
fi

echo "=== Jetson TensorRT compile-only spike (CEL-246) ==="
echo "Output: $OUTPUT_DIR"
echo "Image:  $IMAGE"

docker run --rm "${GPU_ARGS[@]}" \
  -v "$OUTPUT_DIR:/work" \
  -v "$SCRIPT_DIR/jetson_compile_inner.sh:/cel246_inner.sh:ro" \
  "$IMAGE" bash -c '
    set -euo pipefail
    pip install -q --upgrade pip
    pip install -q ultralytics onnx onnxruntime-gpu
    bash /cel246_inner.sh
  '

echo "=== Done. Artifacts in $OUTPUT_DIR ==="
