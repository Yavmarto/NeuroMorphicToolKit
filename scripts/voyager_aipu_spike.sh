#!/usr/bin/env bash
# ponytail: CEL-238 Phase 3 — native Linux only; needs Metis board + metis-dkms.
# Upgrade path: wire into neurochip_hw worker after benchmark proves speedup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACT_DIR="${1:-./voyager-compile-out}"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: voyager-aipu-spike requires native Linux with Metis driver access (not macOS/Docker-only)." >&2
  exit 1
fi

if ! command -v lspci >/dev/null 2>&1; then
  echo "ERROR: lspci not found; install pciutils." >&2
  exit 1
fi

if ! lspci | grep -Eiq 'axelera|metis'; then
  echo "BLOCKED: no Metis/Axelera device in lspci output." >&2
  echo "Procure and install a Metis board, load metis-dkms, then re-run." >&2
  echo "See: current tasks/2026-09-14/CEL-238-phase3-runbook.md" >&2
  exit 2
fi

ARTIFACT_DIR="$(cd "$ARTIFACT_DIR" && pwd)"
export ARTIFACT_DIR

echo "=== Voyager AIPU spike (CEL-238) ==="
echo "Artifacts: $ARTIFACT_DIR"
bash "$SCRIPT_DIR/voyager_aipu_inner.sh"
