#!/usr/bin/env bash
set -e

# Build Single Module Frontend - NeuroMorphicToolKit
# Usage: ./scripts/build_module.sh <module_name> <default_port>

MODULE=$1
DEFAULT_PORT=$2

if [ -z "$MODULE" ] || [ -z "$DEFAULT_PORT" ]; then
  echo "Usage: $0 <module_name> <default_port>"
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Load .env variables if file exists
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Resolve port from env (if exists) or use default
ENV_VAR_NAME="$(echo $MODULE | tr '[:lower:]' '[:upper:]')_PORT"
if [ "$MODULE" = "neurocnl" ]; then ENV_VAR_NAME="NEUROCNL_PORT"; fi

# Indirect variable expansion for port
eval PORT=\${$ENV_VAR_NAME:-$DEFAULT_PORT}
FRONTEND_DIR="$REPO_ROOT/$MODULE/frontend"
API_HOST="${NMTK_API_HOST:-localhost}"
API_BASE_URL="http://$API_HOST:$PORT"

BUILD_ARGS=(
  --release
  --no-wasm-dry-run
  --dart-define=API_BASE_URL="$API_BASE_URL"
)

if [ "$MODULE" = "neurocnl" ]; then
  BUILD_ARGS+=(
    --dart-define=NEUROCHIP_BASE_URL="http://$API_HOST:8002"
  )
fi

if [ -d "$FRONTEND_DIR" ]; then
  echo "------------------------------------------------------------"
  echo "==> Building $MODULE frontend (Port: $PORT, API host: $API_HOST)"
  echo "------------------------------------------------------------"

  cd "$FRONTEND_DIR"
  flutter pub get

  # We use dart-define to inject the backend URL into the web app
  flutter build web "${BUILD_ARGS[@]}"

  echo "==> $MODULE build complete."
else
  echo "==> Error: $MODULE frontend directory not found at $FRONTEND_DIR"
  exit 1
fi
