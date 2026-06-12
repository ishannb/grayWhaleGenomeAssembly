#!/usr/bin/env bash
# =============================================================================
# install_medaka.sh — Install Medaka into the gw_assembly environment
#
# Medaka is installed separately because recent versions (2.2.x) require
# PyTorch 2.9 which is not yet broadly available via conda-forge.
# We install medaka 1.11.3 via bioconda which is stable, well-tested,
# and fully supports the r1041_e82_400bps_sup model for R10.4.1 data.
#
# Usage: bash scripts/install_medaka.sh
# =============================================================================
set -euo pipefail

echo "=============================================="
echo "  Installing Medaka into gw_assembly"
echo "=============================================="

# Activate the assembly environment
conda activate gw_assembly

# Install medaka 1.11.3 from bioconda — last version before PyTorch 2.9 dep
# Fully supports R10.4.1 SUP models including r1041_e82_400bps_sup_v5.0.0
conda install -n gw_assembly -c bioconda -c conda-forge medaka=1.11.3 --yes

echo ""
echo "Verifying install..."
medaka --version
medaka tools list_models | grep "r1041_e82_400bps_sup" | head -5

echo ""
echo "=============================================="
echo "  Medaka installed successfully."
echo "  Update config.yaml if needed — available"
echo "  models shown above."
echo "=============================================="
