#!/usr/bin/env bash
# =============================================================================
# 07_assess.sh — Assembly quality assessment
#
# Runs BUSCO and QUAST on the final purged assembly to evaluate:
#   - BUSCO: gene completeness using cetartiodactyla_odb10 lineage
#            Target: >90% complete (Toren et al. 2025 achieved 94.6%)
#   - QUAST: contiguity stats (N50, contig count, total length)
#
# Submit: sbatch scripts/07_assess.sh
# Manual: bash scripts/07_assess.sh
#
# Cite:
#   BUSCO: Simao et al. (2015) Bioinformatics, 31(19), 3210-3212
#          Manni et al. (2021) Current Protocols, 1, e323
#   QUAST: Gurevich et al. (2013) Bioinformatics, 29(8), 1072-1075
# =============================================================================
#SBATCH --job-name=gw_07_assess
#SBATCH --output=logs/07_assess_%j.out
#SBATCH --error=logs/07_assess_%j.err
#SBATCH --partition=euan
#SBATCH --account=euan
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --mail-type=FAIL,END
#SBATCH --mail-user=ishannb@stanford.edu
#SBATCH --chdir=/oak/stanford/groups/euan/projects/ishannb/grayWhaleAssembly/grayWhaleGenomeAssembly
set -euo pipefail

REPO_DIR="/oak/stanford/groups/euan/projects/ishannb/grayWhaleAssembly/grayWhaleGenomeAssembly"
CONFIG="${CONFIG:-${REPO_DIR}/config/config.yaml}"

eval $(python3 "${REPO_DIR}/scripts/parse_config.py" "${CONFIG}")
THREADS=${SLURM_CPUS_PER_TASK:-16}

ASSEMBLY="${OUTPUT_BASE_DIR}/05_purged/purged_assembly.fasta"
OUT_DIR="${OUTPUT_BASE_DIR}/06_assessment"

echo "=============================================="
echo "  Step 7: Assembly Assessment"
echo "  Input:    ${ASSEMBLY}"
echo "  BUSCO db: ${BUSCO_LINEAGE}"
echo "  Output:   ${OUT_DIR}"
echo "=============================================="

source /home/users/ishannb/miniconda3/etc/profile.d/conda.sh
conda activate gw_assembly
mkdir -p "${OUT_DIR}"

if [[ ! -f "${ASSEMBLY}" ]]; then
    echo "ERROR: Purged assembly not found: ${ASSEMBLY}"
    echo "       Run 06_purge.sh first."
    exit 1
fi

# ── BUSCO ──────────────────────────────────────────────────────────────────────
BUSCO_OUT="${OUT_DIR}/busco"
if [[ -f "${BUSCO_OUT}/short_summary.txt" ]] || \
   ls "${BUSCO_OUT}"/short_summary*.txt 2>/dev/null | grep -q .; then
    echo "BUSCO results already exist — skipping."
else
    echo "Running BUSCO (lineage: ${BUSCO_LINEAGE})..."
    busco \
        --in "${ASSEMBLY}" \
        --out "${BUSCO_OUT}" \
        --lineage_dataset "${BUSCO_LINEAGE}" \
        --mode "${BUSCO_MODE}" \
        --cpu "${THREADS}" \
        --force

    echo ""
    echo "BUSCO summary:"
    cat "${BUSCO_OUT}"/short_summary*.txt
fi

# ── QUAST ──────────────────────────────────────────────────────────────────────
QUAST_OUT="${OUT_DIR}/quast"
if [[ -f "${QUAST_OUT}/report.txt" ]]; then
    echo "QUAST results already exist — skipping."
else
    echo "Running QUAST..."
    quast.py \
        "${ASSEMBLY}" \
        --output-dir "${QUAST_OUT}" \
        --threads "${THREADS}" \
        --eukaryote \
        --large \
        --min-contig 10000

    echo ""
    echo "QUAST summary:"
    cat "${QUAST_OUT}/report.txt"
fi

# ── Final summary ──────────────────────────────────────────────────────────────
echo ""
echo "=============================================="
echo "  Assessment complete!"
echo ""
echo "  BUSCO: ${BUSCO_OUT}/short_summary*.txt"
echo "  QUAST: ${QUAST_OUT}/report.txt"
echo ""
echo "  Benchmark (Toren et al. 2025 gray whale assembly):"
echo "    Assembly size: ~2.4 Gb"
echo "    N50:           ~15 Mb"
echo "    BUSCO:         94.6% complete (cetartiodactyla_odb10)"
echo "=============================================="
