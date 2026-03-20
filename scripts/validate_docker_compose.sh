#!/bin/bash
set -e

# Validate root docker-compose.yml configuration and profiles
# Usage: ./scripts/validate_docker_compose.sh [--build]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

BUILD_FLAG=""
if [ "$1" = "--build" ]; then
  BUILD_FLAG="--build"
fi

PASS=0
FAIL=0

check() {
  local label="$1"
  shift
  echo -n "  Checking $label... "
  if "$@" > /dev/null 2>&1; then
    echo "OK"
    PASS=$((PASS + 1))
  else
    echo "FAIL"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Docker Compose Validation ==="
echo ""

# 1. Validate base config
echo "[1/4] Validating base configuration"
check "docker-compose.yml syntax" docker compose config --quiet

# 2. Validate each profile
echo ""
echo "[2/4] Validating profiles"
for profile in core physics full; do
  check "profile '$profile'" docker compose --profile "$profile" config --quiet
done

# 3. Check Dockerfiles exist and are non-empty
echo ""
echo "[3/4] Checking Dockerfiles"
SERVICES=("neurocnl:neurocnl/backend/Dockerfile" "Neurosim:Dockerfile" "Neurochip:Dockerfile" "Neurobench:Dockerfile" "Neurosense:Dockerfile" "Neurohub:Dockerfile")
for entry in "${SERVICES[@]}"; do
  ctx="${entry%%:*}"
  df="${entry##*:}"
  check "$ctx Dockerfile" test -s "$ctx/$df"
done

# 4. Optionally build images
if [ -n "$BUILD_FLAG" ]; then
  echo ""
  echo "[4/4] Building images (this may take a while)"
  for profile in core physics full; do
    check "build profile '$profile'" docker compose --profile "$profile" build
  done
else
  echo ""
  echo "[4/4] Skipping image build (pass --build to enable)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
