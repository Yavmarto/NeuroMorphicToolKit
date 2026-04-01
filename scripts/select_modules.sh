#!/usr/bin/env bash
set -e

# Interactive Module Selection - NeuroMorphicToolKit
# Allows selecting modules to rebuild using a simple text-based checklist.

MODULES=("neurocnl" "Neurosim" "Neurochip" "Neurobench" "Neurosense" "Neurohub")
SELECTED=()

echo "============================================================"
echo "Select modules to build (enter numbers separated by space):"
echo "============================================================"

for i in "${!MODULES[@]}"; do
  echo "  $((i+1))) ${MODULES[$i]}"
done
echo "  a) All"
echo "  q) Quit"
echo ""

read -p "Your choice: " choices

if [[ "$choices" == "q" ]]; then
  echo "Exiting..."
  exit 0
fi

if [[ "$choices" == "a" ]]; then
  SELECTED=("${MODULES[@]}")
else
  for choice in $choices; do
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#MODULES[@]}" ]; then
      SELECTED+=("${MODULES[$choice-1]}")
    fi
  done
fi

if [ ${#SELECTED[@]} -eq 0 ]; then
  echo "No modules selected."
  exit 0
fi

echo ""
echo "Building: ${SELECTED[*]}"
echo ""

for mod in "${SELECTED[@]}"; do
  make build-"$mod"
done
