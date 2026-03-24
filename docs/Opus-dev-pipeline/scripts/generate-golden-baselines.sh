#!/usr/bin/env bash
#
# generate-golden-baselines.sh — Creates golden simulation baselines.
#
# Run this after neurocnl is working to capture known-good simulation
# outputs. These baselines are used by regression tests.
#
# Usage:
#   cd NeuroMorphicToolKit
#   bash Research-Spec-driven-development/Opus-dev-pipeline/scripts/generate-golden-baselines.sh
#
set -euo pipefail

BASELINE_DIR="neurocnl/baselines/golden"
mkdir -p "$BASELINE_DIR"

echo "Generating golden baselines..."

python3 -c "
import json
from neurocnl.pipeline import run_pipeline

# Baseline 1: 3-neuron reflex arc
spec = '''The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds
The sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0'''

result = run_pipeline(spec, duration=1.0, skip_assertions=True)

baseline = {
    'name': 'reflex_arc_3neuron',
    'spec_text': spec,
    'expected_latency': result.summary.get('input_to_output_latency'),
    'expected_motor_rate': result.summary.get('motor_mean_rate', 0),
    'expected_sensory_rate': result.summary.get('sensory_mean_rate', 0),
    'validation_overall': result.validation['overall'],
    'duration': 1.0,
    'dt': 0.001,
}

with open('$BASELINE_DIR/reflex_arc_3neuron.json', 'w') as f:
    json.dump(baseline, f, indent=2)
    print(f'  Written: $BASELINE_DIR/reflex_arc_3neuron.json')
    print(f'  Latency: {baseline[\"expected_latency\"]}')
    print(f'  Motor rate: {baseline[\"expected_motor_rate\"]} Hz')
"

echo ""
echo "Golden baselines generated. Commit these files."
echo "They will be used by simulation regression tests."
