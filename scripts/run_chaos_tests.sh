#!/bin/bash
# scripts/run_chaos_tests.sh
# Randomly stops and restarts services while running a basic smoke test.

SERVICES=("neurocnl" "neurosim" "neurochip" "neurohub" "neurosense" "neurobench")

echo "🌪️ Starting Chaos Testing..."

# Function to run a quick health check
check_all_healthy() {
  for service in "${SERVICES[@]}"; do
    if ! curl -s "http://localhost:$(get_port $service)/health" | grep -q '"status":"\(ok\|healthy\)"'; then
      echo "⚠️ Service $service is NOT healthy."
      return 1
    fi
  done
  return 0
}

get_port() {
  case $1 in
    "neurocnl") echo 8000 ;;
    "neurosim") echo 8001 ;;
    "neurochip") echo 8002 ;;
    "neurobench") echo 8003 ;;
    "neurosense") echo 8004 ;;
    "neurohub") echo 8005 ;;
  esac
}

# 1. Ensure stack is up
docker compose --profile full up -d

for i in {1..5}; do
  TARGET=${SERVICES[$RANDOM % ${#SERVICES[@]}]}
  echo "💥 Killing $TARGET..."
  docker compose stop $TARGET

  # Allow some time for failures to propagate
  sleep 5

  echo "♻️ Restarting $TARGET..."
  docker compose start $TARGET

  # Wait for recovery
  echo "⏳ Waiting for recovery..."
  sleep 10

  if check_all_healthy; then
    echo "✅ System recovered after killing $TARGET"
  else
    echo "❌ System failed to recover after killing $TARGET"
    exit 1
  fi
done

echo "🎉 Chaos tests finished."
