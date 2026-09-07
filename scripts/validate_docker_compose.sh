#!/bin/bash
set -e

# Validate root docker-compose.yml configuration and profiles
# Usage: ./scripts/validate_docker_compose.sh [--build] [--up]

# Ensure Docker CLI and helper tools (e.g. docker-credential-osxkeychain) are on PATH
for candidate in "/Applications/Docker.app/Contents/Resources/bin" "$HOME/.docker/bin"; do
  if [ -d "$candidate" ]; then
    case ":$PATH:" in
      *":$candidate:"*) ;;
      *) export PATH="$candidate:$PATH" ;;
    esac
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

BUILD_FLAG=""
UP_FLAG=""
for arg in "$@"; do
  case $arg in
    --build) BUILD_FLAG="--build" ;;
    --up) UP_FLAG="true" ;;
  esac
done

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

wait_for_health() {
  local profile="$1"
  local timeout=60
  local start_time=$(date +%s)

  echo "  Waiting for services in profile '$profile' to be healthy..."
  while true; do
    local current_time=$(date +%s)
    if [ $((current_time - start_time)) -gt $timeout ]; then
      echo "  Timed out waiting for healthchecks"
      return 1
    fi

    local status=$(docker compose --profile "$profile" ps --format json)
    # This is a simplification; a more robust check would parse JSON
    if ! echo "$status" | grep -q '"Health":"starting"'; then
        if ! echo "$status" | grep -q '"Health":"unhealthy"'; then
            if echo "$status" | grep -q '"Health":"healthy"'; then
                echo "  All services healthy"
                return 0
            fi
        else
            echo "  Found unhealthy services"
            return 1
        fi
    fi
    sleep 2
  done
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
SERVICES=("neurocnl:backend/Dockerfile" "Neurochip:Dockerfile" "Neurobench:Dockerfile" "Neurosense:Dockerfile" "Neurohub:Dockerfile" ".:Dockerfile.lava")
for entry in "${SERVICES[@]}"; do
  ctx="${entry%%:*}"
  df="${entry##*:}"
  check "$ctx Dockerfile" test -s "$ctx/$df"
done

# 4. Build and optionally start services
if [ -n "$BUILD_FLAG" ]; then
  echo ""
  echo "[4/4] Building images"
  for profile in core physics full; do
    check "build profile '$profile'" docker compose --profile "$profile" build
  done

  if [ "$UP_FLAG" = "true" ]; then
    echo ""
    echo "[5/4] Testing runtime startup and health"
    for profile in core physics full; do
      echo "  Testing profile '$profile'..."
      docker compose --profile "$profile" up -d
      if wait_for_health "$profile"; then
        echo "  Profile '$profile' startup: OK"
        PASS=$((PASS + 1))
      else
        echo "  Profile '$profile' startup: FAIL"
        FAIL=$((FAIL + 1))
      fi
      docker compose --profile "$profile" down
    done
  fi
else
  echo ""
  echo "[4/4] Skipping image build (pass --build to enable)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
