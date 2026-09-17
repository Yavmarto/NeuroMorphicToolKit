#!/bin/bash
# Change to project root
cd "$(dirname "$0")/.." || exit 1

OUTPUT="deerflow_handoff.md"
echo "# DeerFlow Context for Nengo-FPGA and SPA Integration" > $OUTPUT
echo "This document contains all the necessary file context required to implement the architectural plan." >> $OUTPUT
echo "" >> $OUTPUT

files=(
    "docs/nengo_fpga_and_spa_plan.md"
    "Neuro-Dream-Hand/scripts/step15_pynq_deployment.py"
    "Neuro-Dream-Hand/neurodreamhand/hardware/pynq_exporter.py"
    "neurocnl/backend/app/services/nengo_code_exporter.py"
    "neurocnl/backend/app/schemas/parse.py"
    "Neuro-Dream-Hand/cnl-specs/reflex_arc.cnl"
)

for file in "${files[@]}"; do
    echo "## File: \`$file\`" >> $OUTPUT
    echo '```python' >> $OUTPUT
    cat "$file" >> $OUTPUT
    echo '```' >> $OUTPUT
    echo "" >> $OUTPUT
done
echo "Handoff generated at $OUTPUT"
