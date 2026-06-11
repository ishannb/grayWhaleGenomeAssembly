#!/usr/bin/env bash
# =============================================================================
# 00_setup.sh — One-time environment setup
#
# Creates conda environments and output directory structure.
# Run this ONCE before submitting any pipeline jobs.
#
# Usage: bash scripts/00_setup.sh
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${REPO_DIR}/config/config.yaml"

echo "=============================================="
echo "  Gray Whale Genome Assembly — Setup"
echo "=============================================="
echo "Repo: ${REPO_DIR}"

# ── Parse output base dir ──────────────────────────────────────────────────────
BASE_DIR=$(python3 -c "
import yaml
with open('${CONFIG}') as f:
    c = yaml.safe_load(f)
print(c['output']['base_dir'])
")

echo "Output dir: ${BASE_DIR}"
echo ""

# ── Create output directories ──────────────────────────────────────────────────
echo "[1/3] Creating output directories..."
mkdir -p \
    "${BASE_DIR}/00_merged_reads" \
    "${BASE_DIR}/01_qc" \
    "${BASE_DIR}/02_filtered" \
    "${BASE_DIR}/03_assembly" \
    "${BASE_DIR}/04_polished" \
    "${BASE_DIR}/05_purged" \
    "${BASE_DIR}/06_assessment" \
    "${REPO_DIR}/logs"
echo "      Done."

# ── Check conda ────────────────────────────────────────────────────────────────
echo "[2/3] Checking conda..."
if ! command -v conda &>/dev/null; then
    echo "ERROR: conda not found. Load it first, e.g.: module load anaconda"
    exit 1
fi
echo "      Found: $(which conda)"

# ── Create conda environments ──────────────────────────────────────────────────
echo "[3/3] Creating conda environments (~10-20 min)..."

echo "  --> gw_qc..."
conda env create -f "${REPO_DIR}/envs/qc.yml" --force
echo "      Done."

echo "  --> gw_assembly..."
conda env create -f "${REPO_DIR}/envs/assembly.yml" --force
echo "      Done."

echo ""
echo "=============================================="
echo "  Setup complete! Now run:"
echo "    bash scripts/run_pipeline.sh"
echo "=============================================="
