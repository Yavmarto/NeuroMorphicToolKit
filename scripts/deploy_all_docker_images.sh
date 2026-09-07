#!/usr/bin/env bash

set -e

# Ensure Docker CLI and helper tools (e.g. docker-credential-osxkeychain) are on PATH
for candidate in "/Applications/Docker.app/Contents/Resources/bin" "$HOME/.docker/bin"; do
  if [ -d "$candidate" ]; then
    case ":$PATH:" in
      *":$candidate:"*) ;;
      *) export PATH="$candidate:$PATH" ;;
    esac
  fi
done

# Use the provided org/username or fallback to the canonical GitHub org for this repo
GITHUB_USER=${1:-completed-spoon-6}
GITHUB_USER=$(echo "$GITHUB_USER" | tr '[:upper:]' '[:lower:]')
REPO_NAME="neuromorphictoolkit"
TARGET_FILTER=${2:-}

echo "Deploying images to ghcr.io/${GITHUB_USER}/${REPO_NAME}..."

# Attempt to log in using CR_PAT or GitHub CLI
if [ -n "${CR_PAT:-}" ]; then
  echo "Logging into ghcr.io using CR_PAT..."
  echo "$CR_PAT" | docker login ghcr.io -u "$GITHUB_USER" --password-stdin
elif command -v gh &> /dev/null; then
  echo "Logging into ghcr.io using GitHub CLI..."
  echo "💡 Note: If push fails with 'token does not match expected scopes', run: gh auth refresh -h github.com -s write:packages"
  gh auth token | docker login ghcr.io -u "$GITHUB_USER" --password-stdin
else
  echo "⚠️ gh cli not found. Make sure you are logged in to ghcr.io:"
  echo "echo YOUR_PAT | docker login ghcr.io -u $GITHUB_USER --password-stdin"
  sleep 2
fi

# Ensure we run from the repository root
cd "$(dirname "$0")/.."

# Format: "image_name:dockerfile_path:optional_build_arg"
images=(
  "neurocnl:neurocnl/backend/Dockerfile:"
  "neurochip:Neurochip/Dockerfile:"
  "neurobench:Neurobench/Dockerfile:"
  "neurosense:Neurosense/Dockerfile:"
  "neurohub:Neurohub/Dockerfile:"
  "suite-api:suite_api/Dockerfile:"
  "neurosense-hw-worker:workers/neurosense_hw/Dockerfile:"
  "neurobench-runner-worker:workers/neurobench_runner/Dockerfile:"
  "neurochip-hw-worker:workers/neurochip_hw/Dockerfile:"
  "neurocnl-physics-worker:workers/neurocnl_physics/Dockerfile:INSTALL_PHYSICS=1"
  "lava-backend:Dockerfile.lava:"
  "launcher-control:Dockerfile.control:"
  "jupyter-server:workers/jupyter_server/Dockerfile:"
  "snn-mlir-compiler:workers/snn_mlir_compiler/Dockerfile:"
)

should_run=1
if [[ "$TARGET_FILTER" == --from=* ]]; then
  should_run=0
  FROM_IMG="${TARGET_FILTER#--from=}"
fi

for entry in "${images[@]}"; do
  IFS=":" read -r image file build_arg <<< "$entry"

  if [ -n "$TARGET_FILTER" ]; then
    if [[ "$TARGET_FILTER" == --from=* ]]; then
      if [ "$image" = "$FROM_IMG" ]; then
        should_run=1
      fi
      if [ "$should_run" -eq 0 ]; then
        echo "Skipping $image (waiting for $FROM_IMG)..."
        continue
      fi
    elif [ "$image" != "$TARGET_FILTER" ]; then
      continue
    fi
  fi

  tag="ghcr.io/${GITHUB_USER}/${REPO_NAME}/${image}:latest"
  echo "--------------------------------------------------------"
  echo "Building and pushing: $tag"
  echo "Dockerfile: $file"

  success=0
  for attempt in 1 2 3; do
    if [ "$attempt" -gt 1 ]; then
      echo "⚠️ Retrying $image (attempt $attempt of 3)..."
    fi

    set +e
    if [ -n "$build_arg" ]; then
      docker buildx build --platform linux/amd64 --build-arg "$build_arg" -t "$tag" -f "$file" --push .
    else
      docker buildx build --platform linux/amd64 -t "$tag" -f "$file" --push .
    fi
    exit_code=$?
    set -e

    if [ "$exit_code" -eq 0 ]; then
      success=1
      break
    fi

    echo "⚠️ Build/push attempt $attempt for $image failed (exit code $exit_code). Retrying in 10s..."
    sleep 10
  done

  if [ "$success" -ne 1 ]; then
    echo "❌ Failed to build and push $image after 3 attempts."
    exit 1
  fi

  # Cross-platform (amd64-on-arm64) builds are emulated and leave large layer
  # caches behind; Docker Desktop's VM disk is a fixed size, so back-to-back
  # heavy images (torch, tensorflow, akida SDK, ...) can exhaust it mid-run
  # even though each individual push already succeeded. Reclaim build cache
  # after every image instead of only at the end — but keep a generous
  # floor: pruning too aggressively (e.g. 10GB) evicts shared base-image
  # layers a later image still has cached-and-reused, and BuildKit only
  # notices the blob is gone once it tries to push it ("unknown blob"),
  # failing a build that otherwise built and "succeeded" cleanly.
  docker buildx prune -f --keep-storage 25GB >/dev/null
done

echo "--------------------------------------------------------"
echo "✅ All requested images deployed successfully!"
