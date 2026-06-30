#!/usr/bin/env bash
# =============================================================================
# install_medaka.sh — Create a dedicated conda environment for Medaka
#
# Medaka is installed in its own minimal environment (gw_medaka) with
# Python 3.8, which is what medaka 1.11.x was built and tested against.
# This avoids dependency conflicts with the main gw_assembly environment.
#
# Usage: bash scripts/install_medaka.sh
# =============================================================================
set -euo pipefail

echo "=============================================="
echo "  Creating gw_medaka environment"
echo "=============================================="

conda create -n gw_medaka \
    -c bioconda \
    -c conda-forge \
    python=3.8 \
    medaka \
    --yes

echo ""
echo "Verifying install..."
conda run -n gw_medaka medaka --version
echo ""
echo "Available R10.4.1 SUP models:"
conda run -n gw_medaka medaka tools list_models | grep "r1041_e82_400bps_sup" || \
    echo "  (run: conda run -n gw_medaka medaka tools list_models)"

echo ""
echo "=============================================="
echo "  gw_medaka environment ready."
echo "  Used by: scripts/05_polish.sh"
echo "=============================================="
