#!/usr/bin/env bash
# =============================================================================
# 04_assemble.sh — De novo genome assembly with Flye
#
# Assembles the filtered ONT reads into contigs using Flye's repeat-graph
# algorithm. Uses --nano-hq mode for R10.4.1 / Q20+ SUP-called reads.
# --keep-haplotypes is set so purge_dups can cleanly separate haplotigs.
#
# Expected runtime: 48-72 h for a ~2.4 Gb genome at 60x coverage.
# Expected RAM:     ~400-500 Gb (request bigmem node if euan partition allows)
#
# Submit: sbatch scripts/04_assemble.sh
# Manual: bash scripts/04_assemble.sh
#
# Cite: Kolmogorov et al. (2019) Assembly of long error-prone reads using
#       repeat graphs. Nature Biotechnology, 37, 540-546.
# =============================================================================
#SBATCH --job-name=gw_04_assembly
#SBATCH --output=logs/04_assembly_%j.out
#SBATCH --error=logs/04_assembly_%j.err
#SBATCH --partition=bigmem
#SBATCH --account=euan
# Sized from measured blue whale usage: 312.7 GiB peak against a 400G request
# on 120 Gb of filtered reads. Fin whale carries ~156 Gb, so 400G would have
# been marginal. 600G leaves real headroom; bigmem allows up to 64 GB/core, so
# 64 cores supports up to 4 TB. Cores raised 32 -> 64 to cut wall time: blue
# whale needed 37.7 h at 32 cores and hit the partition's 24 h ceiling, which
# is why --resume exists below.
#SBATCH --cpus-per-task=64
#SBATCH --mem=600G
#SBATCH --time=24:00:00
#SBATCH --mail-type=BEGIN,FAIL,END
#SBATCH --mail-user=ishannb@stanford.edu
#SBATCH --chdir=/oak/stanford/groups/euan/projects/ishannb/grayWhaleAssembly/grayWhaleGenomeAssembly
set -euo pipefail

REPO_DIR="/oak/stanford/groups/euan/projects/ishannb/grayWhaleAssembly/grayWhaleGenomeAssembly"
CONFIG="${CONFIG:-${REPO_DIR}/config/config.yaml}"

eval $(python3 "${REPO_DIR}/scripts/parse_config.py" "${CONFIG}")
THREADS=${SLURM_CPUS_PER_TASK:-64}

INPUT="${OUTPUT_BASE_DIR}/02_filtered/filtered_reads.fastq.gz"
OUT_DIR="${OUTPUT_BASE_DIR}/03_assembly"
ASSEMBLY="${OUT_DIR}/assembly.fasta"

echo "=============================================="
echo "  Step 4: De Novo Assembly (Flye)"
echo "  Read type:    ${FLYE_READ_TYPE}"
echo "  Genome size:  ${GENOME_ESTIMATED_SIZE}"
echo "  Threads:      ${THREADS}"
echo "  Output:       ${OUT_DIR}"
echo "=============================================="

source /home/users/ishannb/miniconda3/etc/profile.d/conda.sh
conda activate gw_assembly
mkdir -p "${OUT_DIR}"

# ── Guard ──────────────────────────────────────────────────────────────────────
if [[ -f "${ASSEMBLY}" ]]; then
    echo "Assembly already exists — skipping (delete ${OUT_DIR} to rerun)."
    exit 0
fi

# ── Verify input ───────────────────────────────────────────────────────────────
if [[ ! -f "${INPUT}" ]]; then
    echo "ERROR: Filtered reads not found: ${INPUT}"
    echo "       Run 03_filter.sh first."
    exit 1
fi

# ── Run Flye ───────────────────────────────────────────────────────────────────
# If a previous Flye run left progress in the output dir, resume it
RESUME_FLAG=""
if [[ -f "${OUT_DIR}/flye.log" ]] && [[ -d "${OUT_DIR}/20-repeat" || -d "${OUT_DIR}/10-consensus" ]]; then
    echo "Detected previous Flye progress — resuming."
    RESUME_FLAG="--resume"
fi

echo "Starting Flye assembly at $(date)..."

flye \
    "--${FLYE_READ_TYPE}" "${INPUT}" \
    --genome-size "${GENOME_ESTIMATED_SIZE}" \
    --out-dir "${OUT_DIR}" \
    --threads "${THREADS}" \
    --iterations "${FLYE_ITERATIONS}" \
    ${RESUME_FLAG} \
    ${FLYE_EXTRA_FLAGS}

echo "Flye finished at $(date)."

# ── Assembly stats ─────────────────────────────────────────────────────────────
echo ""
echo "Assembly statistics:"
seqkit stats -a "${ASSEMBLY}" | tee "${OUT_DIR}/assembly_stats.txt"

echo ""
echo "Flye log summary (last 20 lines):"
tail -20 "${OUT_DIR}/flye.log"

echo ""
echo "Output: ${ASSEMBLY}"
