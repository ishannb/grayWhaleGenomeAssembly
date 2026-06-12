#!/usr/bin/env bash
# =============================================================================
# install_medaka.sh — Install Medaka into the gw_assembly environment
#
# Installs medaka 1.11.3 via bioconda directly into the gw_assembly env
# without needing to activate it first.
#
# Usage: bash scripts/install_medaka.sh
# =============================================================================
set -euo pipefail

echo "=============================================="
echo "  Installing Medaka into gw_assembly"
echo "=============================================="

# Install directly into the named environment — no activation needed
conda install -n gw_assembly \
    -c bioconda \
    -c conda-forge \
    medaka=1.11.3 \
    --yes

echo ""
echo "Verifying install..."
conda run -n gw_assembly medaka --version
conda run -n gw_assembly medaka tools list_models | grep "r1041_e82_400bps_sup" | head -5

echo ""
echo "=============================================="
echo "  Medaka installed successfully."
echo "=============================================="
