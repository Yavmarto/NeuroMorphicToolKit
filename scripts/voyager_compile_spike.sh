#!/usr/bin/env bash
# ponytail: CEL-237 compiler-only spike — Ubuntu 22.04 container, no Metis board.
# Upgrade path: wire into Makefile target + CI runner when hardware arrives.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${1:-./voyager-compile-out}"
IMAGE="${VOYAGER_COMPILE_IMAGE:-ubuntu:22.04}"

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

echo "=== Voyager compiler-only spike (CEL-237) ==="
echo "Output: $OUTPUT_DIR"
echo "Image:  $IMAGE"

docker run --rm \
  -v "$OUTPUT_DIR:/work" \
  -v "$SCRIPT_DIR/voyager_compile_inner.sh:/cel237_inner.sh:ro" \
  "$IMAGE" bash /cel237_inner.sh

echo "=== Done. Artifacts in $OUTPUT_DIR ==="
