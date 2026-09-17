#!/usr/bin/env bash
# ponytail: CEL-244 compiler-only spike — Ubuntu 22.04 container, no Coral USB.
# Upgrade path: wire into Makefile target + optional CI runner on linux x86_64.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${1:-./coral-compile-out}"
IMAGE="${CORAL_COMPILE_IMAGE:-ubuntu:22.04}"

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

echo "=== Coral compiler-only spike (CEL-244) ==="
echo "Output: $OUTPUT_DIR"
echo "Image:  $IMAGE"

docker run --rm \
  -v "$OUTPUT_DIR:/work" \
  -v "$SCRIPT_DIR/coral_compile_inner.sh:/cel244_inner.sh:ro" \
  "$IMAGE" bash /cel244_inner.sh

echo "=== Done. Artifacts in $OUTPUT_DIR ==="
