#!/usr/bin/env bash
set -e

# Build All Frontends - NeuroMorphicToolKit
# Orchestrates Flutter web builds for all modules with correct API URLs.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Load .env variables if file exists
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Define modules and their default ports
MODULE_LIST="neurocnl:8000 Neurosim:8001 Neurochip:8002 Neurobench:8003 Neurosense:8004 Neurohub:8005"
API_HOST="${NMTK_API_HOST:-localhost}"

echo "==> Building nmtk_ui_core shared package..."
cd nmtk_ui_core && flutter pub get && cd ..

for entry in $MODULE_LIST; do
  mod="${entry%%:*}"
  default_port="${entry#*:}"

  # Resolve port from env (if exists) or use default
  env_var_name="$(echo $mod | tr '[:lower:]' '[:upper:]')_PORT"
  if [ "$mod" = "neurocnl" ]; then env_var_name="NEUROCNL_PORT"; fi

  # Indirect variable expansion for port
  eval port=\${$env_var_name:-$default_port}
  frontend_dir="$REPO_ROOT/$mod/frontend"

  if [ -d "$frontend_dir" ]; then
    echo "------------------------------------------------------------"
    echo "==> Building $mod frontend (Port: $port, API host: $API_HOST)"
    echo "------------------------------------------------------------"

    cd "$frontend_dir"
    flutter pub get

    build_args=(
      --release
      --no-wasm-dry-run
      --dart-define=API_BASE_URL="http://$API_HOST:$port"
    )

    if [ "$mod" = "neurocnl" ]; then
      build_args+=(
        --dart-define=NEUROCHIP_BASE_URL="http://$API_HOST:8002"
      )
    fi

    # We use dart-define to inject the backend URL into the web app
    flutter build web "${build_args[@]}"

    echo "==> $mod build complete."
    cd "$REPO_ROOT"
  else
    echo "==> Skipping $mod (no frontend directory found)"
  fi
done

echo ""
echo "------------------------------------------------------------"
echo "ALL FRONTENDS BUILT SUCCESSFULLY."
echo "------------------------------------------------------------"
