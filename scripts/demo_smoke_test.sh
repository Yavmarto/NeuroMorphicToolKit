#!/bin/bash
set -e

# NeuroMorphicToolkit (NMTK) — POC Demo Smoke Test Script
# This script validates that the core backend APIs are functional.

API_BASE_URL=${API_BASE_URL:-"http://localhost:8000"}
TIMEOUT=60
WAIT_INTERVAL=2

echo "🚀 Starting NMTK POC Smoke Test..."
echo "📍 Using API Base URL: $API_BASE_URL"

# 1. Start backends
echo "🚀 Starting neurocnl backend..."
PYTHONPATH=neurocnl:neurocnl/backend python3 -m uvicorn backend.app.main:app --port 8000 > /tmp/nmtk_smoke_test_backend.log 2>&1 &
BACKEND_PID=$!

cleanup() {
  echo "🧹 Cleaning up..."
  kill $BACKEND_PID 2>/dev/null || true
  rm -f /tmp/nmtk_smoke_test_backend.log
}

trap cleanup EXIT

# 2. Wait for health checks
echo "⏳ Waiting for backend health check..."
for i in $(seq 1 $(($TIMEOUT / $WAIT_INTERVAL))); do
  if curl -s "$API_BASE_URL/health" | grep -q '"status":"ok"'; then
    echo "✅ Backend is healthy!"
    break
  fi
  if [ "$i" -eq $(($TIMEOUT / $WAIT_INTERVAL)) ]; then
    echo "❌ Timeout waiting for backend health check."
    exit 1
  fi
  sleep $WAIT_INTERVAL
done

# Define a simple CNL spec for testing
TEST_SPEC="# Test Spec\nThe sensory neuron MUST fire ONLY IF membrane potential exceeds 0.5\nThe motor neuron MUST emit a spike ONLY IF membrane potential exceeds 0.7\nThe connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 2.0\nThe sensory neuron membrane potential MUST decay WITH time constant of 0.01 seconds\nThe sensory neuron MUST NOT fire DURING the refractory period of 0.01 seconds"

# 3. POST a CNL spec to /api/parse
echo "🔍 Testing /api/parse..."
PARSE_RESPONSE=$(curl -s -X POST "$API_BASE_URL/api/parse" \
  -H "Content-Type: application/json" \
  -d "{\"spec\": \"$TEST_SPEC\"}")

if echo "$PARSE_RESPONSE" | grep -q '"errors":0'; then
  echo "✅ Parse successful!"
else
  echo "❌ Parse failed: $PARSE_RESPONSE"
  exit 1
fi

# 4. POST to /api/validate
echo "⚖️ Testing /api/validate..."
VALIDATE_RESPONSE=$(curl -s -X POST "$API_BASE_URL/api/validate" \
  -H "Content-Type: application/json" \
  -d "{\"spec\": \"$TEST_SPEC\"}")

if echo "$VALIDATE_RESPONSE" | grep -q '"overall":true'; then
  echo "✅ Validation successful!"
else
  echo "❌ Validation failed: $VALIDATE_RESPONSE"
  exit 1
fi

# 5. POST to /api/simulate
echo "⚡ Testing /api/simulate..."
SIMULATE_RESPONSE=$(curl -s -X POST "$API_BASE_URL/api/simulate" \
  -H "Content-Type: application/json" \
  -d "{\"spec\": \"$TEST_SPEC\", \"duration\": 0.1}")

JOB_ID=$(echo "$SIMULATE_RESPONSE" | grep -o '"job_id":"[^"]*' | cut -d'"' -f4)

if [ -n "$JOB_ID" ]; then
  echo "✅ Simulation job submitted (ID: $JOB_ID)"
else
  echo "❌ Simulation submission failed: $SIMULATE_RESPONSE"
  exit 1
fi

# 6. Poll for simulation results
echo "⏳ Waiting for simulation results..."
for i in $(seq 1 15); do
  JOB_STATUS_RESPONSE=$(curl -s "$API_BASE_URL/api/jobs/$JOB_ID")
  STATUS=$(echo "$JOB_STATUS_RESPONSE" | grep -o '"status":"[^"]*' | cut -d'"' -f4)

  if [ "$STATUS" == "completed" ]; then
    echo "✅ Simulation completed successfully!"
    break
  elif [ "$STATUS" == "failed" ]; then
    echo "❌ Simulation job failed!"
    exit 1
  fi
  sleep 2
done

echo "🎉 All POC Smoke Tests Passed!"
exit 0
