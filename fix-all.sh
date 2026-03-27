#!/usr/bin/env zsh
# fix-all.sh — Run `dart fix --apply` in every Dart/Flutter project
# found in the root repo and all submodules.
#
# Usage: ./fix-all.sh [--dry-run]
#   --dry-run  Show what would be fixed without applying changes.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=false
APPLY_FLAG="--apply"
FIXED=0
SKIPPED=0
FAILED=0

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  APPLY_FLAG=""
  echo "[DRY RUN] Showing available fixes without applying."
  echo ""
fi

# Detect whether a project is Flutter or pure Dart.
is_flutter_project() {
  local dir="$1"
  grep -q 'flutter:' "$dir/pubspec.yaml" 2>/dev/null
}

fix_project() {
  local dir="$1"
  local label="$2"

  echo ""
  echo "──────────────────────────────────────────"
  echo "  $label"
  echo "  ($dir)"
  echo "──────────────────────────────────────────"

  cd "$dir"

  # Skip build artifacts and generated directories
  if [[ "$dir" == *"/build/"* ]] || [[ "$dir" == *"/.dart_tool/"* ]]; then
    echo "  [SKIP] Build artifact directory."
    SKIPPED=$((SKIPPED + 1))
    cd "$ROOT_DIR"
    return 0
  fi

  # Ensure deps are available (needed for analysis)
  if is_flutter_project "$dir"; then
    echo "  Flutter project — running flutter pub get..."
    if ! flutter pub get --no-example 2>&1 | tail -1; then
      echo "  [WARN] flutter pub get failed — trying fix anyway..."
    fi
  else
    echo "  Pure Dart project — running dart pub get..."
    if ! dart pub get 2>&1 | tail -1; then
      echo "  [WARN] dart pub get failed — trying fix anyway..."
    fi
  fi

  # dart fix works for both Flutter and pure Dart projects
  echo "  Running: dart fix $APPLY_FLAG"
  if dart fix $APPLY_FLAG 2>&1; then
    echo "  [OK]"
    FIXED=$((FIXED + 1))
  else
    echo "  [FAIL] dart fix exited with errors."
    FAILED=$((FAILED + 1))
  fi

  cd "$ROOT_DIR"
}

echo "======================================================"
echo "  fix-all.sh — Apply Dart/Flutter fixes across repo"
echo "======================================================"

# Find all pubspec.yaml files, excluding build dirs and .dart_tool
PROJECTS=("${(@f)$(
  find "$ROOT_DIR" \
    -name "pubspec.yaml" \
    -not -path "*/build/*" \
    -not -path "*/.dart_tool/*" \
    -not -path "*/.*" \
    2>/dev/null | sort
)}")

echo ""
echo "Found ${#PROJECTS[@]} Dart/Flutter project(s)."

for pubspec in "${PROJECTS[@]}"; do
  project_dir="$(dirname "$pubspec")"
  # Create a readable label relative to the root
  label="${project_dir#"$ROOT_DIR/"}"
  fix_project "$project_dir" "$label"
done

echo ""
echo "======================================================"
echo "  Summary"
echo "    Fixed:   $FIXED"
echo "    Skipped: $SKIPPED"
echo "    Failed:  $FAILED"
echo "======================================================"
