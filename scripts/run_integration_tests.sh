#!/bin/bash
set -e

# Load environment variables if .env exists
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

echo "🚀 Starting NMTK full stack with Docker Compose..."
docker compose --profile full up -d

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

# Wait for all services
check_health "neurocnl" "http://localhost:8000"
check_health "neurosim" "http://localhost:8000"
check_health "neurochip" "http://localhost:8002"
check_health "neurobench" "http://localhost:8003"
check_health "neurosense" "http://localhost:8004"
check_health "neurohub" "http://localhost:8005"

echo "🧪 Running cross-module integration tests..."
# Pass service URLs pointing to localhost for the host-based test runner
export NEUROCNL_URL=http://localhost:8000
export NEUROSIM_URL=http://localhost:8000
export NEUROCHIP_URL=http://localhost:8002
export NEUROSENSE_URL=http://localhost:8004
export NEUROHUB_URL=http://localhost:8005
export NEUROBENCH_URL=http://localhost:8003

pytest tests/integration/test_cross_module.py

TEST_EXIT_CODE=$?

echo "🧹 Shutting down stack..."
docker compose down

exit $TEST_EXIT_CODE
