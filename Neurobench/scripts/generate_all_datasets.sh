#!/usr/bin/env bash
# =============================================================================
# generate_all_datasets.sh
# Installs dependencies and generates all NeuroBench synthetic datasets
# consecutively. Safe to re-run — skips already-generated files.
#
# Usage:
#   bash scripts/generate_all_datasets.sh [--preset smoke|medium|large] [--seed N]
#
# Requirements:
#   Python 3.11+, pip accessible as "pip" or "pip3"
#   ~30 min (medium), ~3 hours (large)
# =============================================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
PRESET="${PRESET:-medium}"
SEED="${SEED:-42}"
OUTPUT_DIR="${OUTPUT_DIR:-neurobench/data/generated}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --preset) PRESET="$2"; shift 2 ;;
        --seed)   SEED="$2";   shift 2 ;;
        --output) OUTPUT_DIR="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

echo "======================================================================"
echo "  NeuroBench Synthetic Dataset Generator"
echo "  Preset  : $PRESET"
echo "  Seed    : $SEED"
echo "  Output  : $OUTPUT_DIR"
echo "======================================================================"

# ── Change to repo root ───────────────────────────────────────────────────────
cd "$REPO_ROOT"

# ── Step 0: Install / verify dependencies ────────────────────────────────────
echo ""
echo "[0/6] Installing dependencies..."

PIP="pip"
if ! command -v pip &>/dev/null; then
    PIP="pip3"
fi

$PIP install --quiet \
    numpy \
    h5py \
    numba \
    scipy \
    scikit-learn \
    joblib

# Optional: GPU acceleration (RTX 3060 uses CUDA 12)
if python -c "import cupy" 2>/dev/null; then
    echo "  cupy already installed — GPU acceleration enabled"
else
    echo "  Installing cupy-cuda12x (optional, for perturbation transforms)..."
    $PIP install --quiet cupy-cuda12x 2>/dev/null || \
        echo "  cupy install skipped (not critical — NumPy fallback will be used)"
fi

echo "  Dependencies OK"

# ── Step 1: Download reference datasets for validator calibration ─────────────
echo ""
echo "[1/6] Checking reference datasets for validator calibration..."

REFERENCE_DIR="neurobench/data/reference"
mkdir -p "$REFERENCE_DIR"

# SHD — Spiking Heidelberg Digits
SHD_TRAIN="$REFERENCE_DIR/shd_train.h5"
if [ ! -f "$SHD_TRAIN" ]; then
    echo "  Downloading SHD (Spiking Heidelberg Digits)..."
    # Direct download from compneuro.net — ~350 MB
    curl -L --progress-bar \
        "https://zenkelab.org/datasets/shd_train.h5.gz" \
        -o "${SHD_TRAIN}.gz" 2>/dev/null || \
    curl -L --progress-bar \
        "https://compneuro.net/datasets/shd_train.h5.gz" \
        -o "${SHD_TRAIN}.gz" 2>/dev/null || \
        echo "  WARNING: Could not download SHD. Validator will use hardcoded defaults."
    [ -f "${SHD_TRAIN}.gz" ] && gunzip -f "${SHD_TRAIN}.gz" && echo "  SHD downloaded OK"
else
    echo "  SHD already present — skipping download"
fi

# NinaPro DB5 requires a registration form — cannot auto-download.
# Provide instructions instead.
NINAPRO_PLACEHOLDER="$REFERENCE_DIR/ninapro_db5_placeholder.txt"
if [ ! -f "$NINAPRO_PLACEHOLDER" ]; then
    cat > "$NINAPRO_PLACEHOLDER" << 'EOF'
NinaPro DB5 — 8-channel forearm EMG, 6 gestures
Download from: http://ninapro.hevs.ch/NinaPro-DB5
No registration fee but a brief form is required.

Place the downloaded files in this directory, then re-run:
  python neurobench/data/scripts/calibrate_emg_validator.py \
      --ninapro-dir neurobench/data/reference/

Until then, EMG validators use conservative hardcoded defaults.
EOF
    echo "  NinaPro DB5: see $NINAPRO_PLACEHOLDER for download instructions (form required)"
fi

# N-MNIST — calibrate sparsity validator
NMNIST_DIR="$REFERENCE_DIR/n-mnist"
if [ ! -d "$NMNIST_DIR" ]; then
    echo "  N-MNIST: auto-download not supported (binary format requires special tooling)."
    echo "  Sparsity validator will use N-MNIST-calibrated defaults (0.1%–5%)."
fi

echo "  Reference dataset check complete"

# ── Step 2: Create output directory ──────────────────────────────────────────
echo ""
echo "[2/6] Creating output directories..."
mkdir -p "$OUTPUT_DIR"
mkdir -p "neurobench/data/validators"
mkdir -p "neurobench/data/generators/utils"
mkdir -p "neurobench/data/transforms"
echo "  Directories OK"

# ── Step 3: Generate DS-1 — Canonical Spike Library ──────────────────────────
echo ""
echo "[3/6] Generating DS-1: Canonical Spike Library (${PRESET} preset)..."

DS1_OUT="$OUTPUT_DIR/ds1_canonical_spikes_${PRESET}.h5"

if [ -f "$DS1_OUT" ]; then
    echo "  Already exists: $DS1_OUT — skipping (delete to regenerate)"
else
    python neurobench/data/scripts/run_generator.py \
        --generator canonical_spikes \
        --preset "$PRESET" \
        --seed "$SEED" \
        --output "$DS1_OUT"
    echo "  DS-1 complete: $DS1_OUT"
fi

# Verify integrity
echo "  Verifying SHA-256..."
python -c "
from neurobench.data.generators.utils.io import verify
ok = verify('$DS1_OUT')
exit(0 if ok else 1)
"
echo "  DS-1 integrity: OK"

# ── Step 4: Generate DS-2 — EMG Gestures ─────────────────────────────────────
echo ""
echo "[4/6] Generating DS-2: EMG Gestures (${PRESET} preset)..."

DS2_OUT="$OUTPUT_DIR/ds2_emg_gestures_${PRESET}.h5"

if [ -f "$DS2_OUT" ]; then
    echo "  Already exists: $DS2_OUT — skipping"
else
    python neurobench/data/scripts/run_generator.py \
        --generator emg_gestures \
        --preset "$PRESET" \
        --seed "$SEED" \
        --output "$DS2_OUT"
    echo "  DS-2 complete: $DS2_OUT"
fi

python -c "
from neurobench.data.generators.utils.io import verify
ok = verify('$DS2_OUT')
exit(0 if ok else 1)
"
echo "  DS-2 integrity: OK"

# ── Step 5: Validate all generated datasets ───────────────────────────────────
echo ""
echo "[5/6] Running full statistical validation..."

python neurobench/data/scripts/validate_all.py \
    --directory "$OUTPUT_DIR" \
    --report "$OUTPUT_DIR/validation_report.json"

echo "  Validation report written to: $OUTPUT_DIR/validation_report.json"

# ── Step 6: Summary ───────────────────────────────────────────────────────────
echo ""
echo "[6/6] Summary"
echo "----------------------------------------------------------------------"
echo "  Preset: $PRESET | Seed: $SEED"
echo ""
ls -lh "$OUTPUT_DIR"/*.h5 2>/dev/null || echo "  No .h5 files found in $OUTPUT_DIR"
echo ""
echo "  Next steps:"
echo "    # Run a benchmark against the generated data:"
echo "    neurobench run spike_classification --network tests/fixtures/simple_net.cnl"
echo "    neurobench run grip_stability       --network tests/fixtures/simple_net.cnl"
echo ""
echo "    # Generate larger datasets (takes ~1.5 hours total):"
echo "    bash scripts/generate_all_datasets.sh --preset large"
echo ""
echo "    # Validate a specific file:"
echo "    python neurobench/data/scripts/validate_all.py --file $DS1_OUT"
echo "======================================================================"
echo "  Done."
echo "======================================================================"
