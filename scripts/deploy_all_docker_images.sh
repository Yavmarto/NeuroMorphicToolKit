#!/usr/bin/env bash

set -e

# Use the provided org/username or fallback to the canonical GitHub org for this repo
GITHUB_USER=${1:-completed-spoon-6}
GITHUB_USER=$(echo "$GITHUB_USER" | tr '[:upper:]' '[:lower:]')
REPO_NAME="neuromorphictoolkit"

echo "Deploying images to ghcr.io/${GITHUB_USER}/${REPO_NAME}..."

# Attempt to log in using GitHub CLI if available
if command -v gh &> /dev/null; then
  echo "Logging into ghcr.io using GitHub CLI..."
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

for entry in "${images[@]}"; do
  IFS=":" read -r image file build_arg <<< "$entry"

  tag="ghcr.io/${GITHUB_USER}/${REPO_NAME}/${image}:latest"
  echo "--------------------------------------------------------"
  echo "Building and pushing: $tag"
  echo "Dockerfile: $file"

  if [ -n "$build_arg" ]; then
    docker buildx build --platform linux/amd64 --build-arg "$build_arg" -t "$tag" -f "$file" --push .
  else
    docker buildx build --platform linux/amd64 -t "$tag" -f "$file" --push .
  fi
done

echo "--------------------------------------------------------"
echo "✅ All images deployed successfully!"
