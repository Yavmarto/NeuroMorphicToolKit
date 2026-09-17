#!/bin/bash
set -e

# Load environment variables if .env exists
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

echo "🚀 Starting NMTK full stack with Docker Compose..."
docker compose up -d

# Function to check health of a service
check_health() {
  local service=$1
  local url=$2
  echo "⏳ Waiting for $service to be healthy at $url..."
  for i in {1..30}; do
    if curl -s "$url/health" | grep -q '"status":"\(ok\|healthy\)"'; then
      echo "✅ $service is healthy!"
      return 0
    fi
    sleep 2
  done
  echo "❌ $service health check timed out!"
  return 1
}

# All ordinary module routes are mounted by Suite API.
check_health "suite_api" "http://localhost:9000/api/suite"

echo "🧪 Running cross-module integration tests..."
# Pass service URLs pointing to localhost for the host-based test runner
export SUITE_API_URL=http://localhost:9000

pytest tests/integration/test_cross_module.py

TEST_EXIT_CODE=$?

echo "🧹 Shutting down stack..."
docker compose down

exit $TEST_EXIT_CODE
