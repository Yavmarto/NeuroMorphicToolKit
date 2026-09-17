#!/usr/bin/env bash
# scripts/deploy.sh
# Builds and deploys the Neurohub API to Cloud Run. Backend only — Neurohub's
# UI ships inside the main NMTK Flutter app, not as a separate hosted site,
# so there is no frontend deploy step here.
#
# Requires: gcloud CLI authenticated, docker daemon running.
# Run from the Neurohub/ directory. Usage: bash scripts/deploy.sh
set -euo pipefail

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
REGION="${CLOUD_RUN_REGION:-europe-west1}"
IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/neurohub/neurohub-api"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "🚀 Neurohub deploy → project=$PROJECT_ID region=$REGION"
echo ""

echo "▶ Building backend Docker image..."
# Build context is the repo root, not Neurohub/ — the Dockerfile's COPY paths
# (COPY Neurohub/pyproject.toml, etc.) are relative to the superproject root.
docker build -f Dockerfile -t "$IMAGE:latest" "$REPO_ROOT"

echo "▶ Pushing to Artifact Registry..."
docker push "$IMAGE:latest"

echo "▶ Deploying Cloud Run service..."
gcloud run services replace infrastructure/cloud-run-service.yaml --region="$REGION"

echo "▶ Allowing unauthenticated access (the API does its own per-user auth)..."
gcloud run services add-iam-policy-binding neurohub-api \
  --region="$REGION" \
  --member="allUsers" \
  --role="roles/run.invoker" >/dev/null

URL=$(gcloud run services describe neurohub-api --region="$REGION" --format='value(status.url)')

echo ""
echo "✅ Deployed: $URL"
echo ""
echo "Next: bake this into the Flutter release build as NEUROHUB_API_URL"
echo "(neurocnl/frontend/lib/config/app_config.dart's neurohubApiUrl default)"
echo "so every release build points here with zero extra steps."
