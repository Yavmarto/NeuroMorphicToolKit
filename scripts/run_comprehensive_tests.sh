#!/bin/bash
# scripts/run_comprehensive_tests.sh
set -e

echo "📦 Running Comprehensive Test Suite..."

# 1. Unit & Property tests (Estimated: 5 mins)
echo "🧪 Running Unit and Property tests..."
export PYTHONPATH=$PYTHONPATH:$(pwd)/neurocnl:$(pwd)/Neurochip:$(pwd)/Neurosense:$(pwd)/Neurohub:$(pwd)/Neurosim:$(pwd)/Neuro-Dream-Hand
pytest --cov=neurocnl --cov=neurosim --cov=neurosense --cov=neurochip --cov=neurobench --cov=neurohub --cov=neurodreamhand \
    neurocnl/neurocnl/tests/ \
    neurocnl/backend/tests/ \
    Neurosim/neurosim/tests/ \
    Neurosense/neurosense/tests/ \
    Neurochip/neurochip/tests/ \
    Neurobench/neurobench/tests/ \
    Neurohub/neurohub/tests/ \
    Neuro-Dream-Hand/tests/ \
    --tb=short

# 2. Load tests (Estimated: 3 mins)
# Note: Requires services to be running.
if [ "$RUN_LOAD_TESTS" = "true" ]; then
    ./scripts/run_load_tests.sh
fi

# 3. Chaos tests (Estimated: 5 mins)
if [ "$RUN_CHAOS_TESTS" = "true" ]; then
    ./scripts/run_chaos_tests.sh
fi

echo "🏁 Comprehensive Test Suite finished successfully."
