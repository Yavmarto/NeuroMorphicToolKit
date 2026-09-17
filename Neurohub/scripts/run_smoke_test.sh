#!/bin/bash
set -e

# Configuration
NEUROHUB_PORT=8005
MOCK_SUITE_PORT=8082
export NEUROHUB_URL="http://localhost:$NEUROHUB_PORT"
export NEUROHUB_API_KEY="smoke-test-key"
export NEUROHUB_ADMIN_API_KEY="smoke-test-key"
export NEUROHUB_AUTH_ENABLED="true"
export NEUROHUB_DB_URL="sqlite:///./smoke_test.db"

# Cleanup function
cleanup() {
  echo "Cleaning up..."
  kill $BACKEND_PID 2>/dev/null || true
  kill $MOCK_PID 2>/dev/null || true
  rm -f smoke_test.db
}
trap cleanup EXIT

echo "Starting Mock Suite Server on port $MOCK_SUITE_PORT..."
python neurohub/tests/mock_suite_server.py --port $MOCK_SUITE_PORT > mock_server.log 2>&1 &
MOCK_PID=$!

echo "Initializing database..."
rm -f smoke_test.db
alembic upgrade head

echo "Starting NeuroHub Backend on port $NEUROHUB_PORT..."
# Using uvicorn directly to run the app
uvicorn neurohub.app.main:app --host 127.0.0.1 --port $NEUROHUB_PORT > backend.log 2>&1 &
BACKEND_PID=$!

# Wait for services to be ready
echo "Waiting for services to start..."
MAX_RETRIES=30
COUNT=0
while ! curl -s "$NEUROHUB_URL/health" > /dev/null; do
  sleep 1
  COUNT=$((COUNT+1))
  if [ $COUNT -ge $MAX_RETRIES ]; then
    echo "Backend failed to start. Logs:"
    cat backend.log
    exit 1
  fi
done

# Keep tailing logs in background to see errors
tail -f backend.log &
TAIL_PID=$!
cleanup() {
  echo "Cleaning up..."
  kill $BACKEND_PID 2>/dev/null || true
  kill $MOCK_PID 2>/dev/null || true
  kill $TAIL_PID 2>/dev/null || true
  rm -f smoke_test.db
}

echo "Configuring NeuroHub to use Mock Suite..."
curl -X PUT "$NEUROHUB_URL/api/neurohub/config" \
  -H "X-API-Key: $NEUROHUB_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"neurosim_url\": \"http://localhost:$MOCK_SUITE_PORT\",
    \"neurochip_url\": \"http://localhost:$MOCK_SUITE_PORT\",
    \"neurobench_url\": \"http://localhost:$MOCK_SUITE_PORT\",
    \"neurosense_url\": \"http://localhost:$MOCK_SUITE_PORT\",
    \"neurocnl_url\": \"http://localhost:$MOCK_SUITE_PORT\",
    \"shared_storage_path\": \"./shared_assets_smoke\",
    \"default_project_settings\": {}
  }"

echo "Running Smoke Test..."
if pytest neurohub/tests/test_smoke.py; then
  echo "SMOKE TEST PASSED"
else
  echo "SMOKE TEST FAILED. Backend Logs:"
  cat backend.log
  exit 1
fi
