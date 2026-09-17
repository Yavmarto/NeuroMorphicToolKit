#!/bin/bash
set -e

# Configuration
LOCUST_FILE="tests/load/locustfile.py"
HOST="http://localhost:8000"  # Target neurocnl as entry point or individual services
USERS=100
SPAWN_RATE=10
RUN_TIME="2m"

echo "🚀 Starting load test with $USERS users for $RUN_TIME..."

# Run locust in headless mode
locust -f "$LOCUST_FILE" \
    --host "$HOST" \
    --users "$USERS" \
    --spawn-rate "$SPAWN_RATE" \
    --run-time "$RUN_TIME" \
    --headless \
    --only-summary

echo "✅ Load test completed."
