#!/usr/bin/env bash
# ponytail: CEL-245 QNN CPU-backend spike — Ubuntu 22.04 container, no Snapdragon device.
# Upgrade path: optional CI job on Linux runner once QAIRT SDK is cached on the host.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${1:-./qnn-cpu-out}"
IMAGE="${QNN_CPU_SPIKE_IMAGE:-ubuntu:22.04}"
QAIRT_SDK_ROOT="${QAIRT_SDK_ROOT:-}"

if [[ -z "$QAIRT_SDK_ROOT" ]]; then
  echo "ERROR: QAIRT_SDK_ROOT is not set."
  echo "Download and extract Qualcomm AI Runtime (Community) SDK, then export:"
  echo "  export QAIRT_SDK_ROOT=/path/to/qairt/<version>"
  echo "See current tasks/2026-09-15/CEL-245-qnn-cpu-spike-findings.md"
  exit 1
fi

if [[ ! -f "$QAIRT_SDK_ROOT/bin/envsetup.sh" ]]; then
  echo "ERROR: QAIRT_SDK_ROOT does not look like a QAIRT/QNN SDK tree: $QAIRT_SDK_ROOT"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
QAIRT_SDK_ROOT="$(cd "$QAIRT_SDK_ROOT" && pwd)"

echo "=== QNN CPU-backend spike (CEL-245) ==="
echo "Output:         $OUTPUT_DIR"
echo "QAIRT_SDK_ROOT: $QAIRT_SDK_ROOT"
echo "Image:          $IMAGE"

docker run --rm \
  -e QAIRT_SDK_ROOT=/qairt-sdk \
  -v "$OUTPUT_DIR:/work" \
  -v "$QAIRT_SDK_ROOT:/qairt-sdk:ro" \
  -v "$SCRIPT_DIR/qnn_cpu_inner.sh:/cel245_inner.sh:ro" \
  "$IMAGE" bash /cel245_inner.sh

echo "=== Done. Artifacts in $OUTPUT_DIR ==="
