#!/usr/bin/env bash
# NeuroStudio UI golden-path verification (CEL-261).
#
# Fast path (default): widget tests drive the real Studio Run UI with the same
# committed `.nmtk` workspaces as `neuro ci golden-paths`.
#
# Live path (optional): set NMTK_GOLDEN_PATHS_LIVE=1 plus the same server
# credentials as cel108; runs integration_test/cel261_studio_golden_paths_e2e_test.dart
# against the dev backend.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT/nmtk/neuro_toolkit"

echo "==> Studio UI golden paths (widget tests)"
flutter test test/features/neurocnl/golden_paths/ -r expanded

if [[ "${NMTK_GOLDEN_PATHS_LIVE:-}" == "1" ]]; then
  echo "==> Studio UI golden paths (live backend)"
  flutter test integration_test/cel261_studio_golden_paths_e2e_test.dart -d macos -r expanded
fi
