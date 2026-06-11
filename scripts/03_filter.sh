#!/usr/bin/env bash
# =============================================================================
# 03_filter.sh — Read filtering with Filtlong
#
# Filtering parameters (min_length, keep_percent, target_bases) are computed
# automatically by scripts/calculate_params.py based on:
#   - sample.total_data_gb  (actual input data volume)
#   - genome.estimated_size_gb  (expected genome size)
#
# The strategy adapts to coverage depth:
#   >80x  → subsample to 60x, min_length 5000
#   40-80x → subsample to 50x if needed, min_length 3000
#   <40x  → keep everything, min_length 1000 (warn user)
#
# To override, set filtlong.override: true in config.yaml.
#
# Submit: sbatch scripts/03_filter.sh
# Manual: bash scripts/03_filter.sh
#
# Cite: Wick R (2021) Filtlong, github.com/rrwick/Filtlong
# =============================================================================
#SBATCH --job-name=gw_03_filter
#SBATCH --output=logs/03_filter_%j.out
#SBATCH --error=logs/03_filter_%j.err
#SBATCH --partition=euan
#SBATCH --account=euan
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=8:00:00
#SBATCH --mail-type=FAIL,END
#SBATCH --mail-user=ishannb@stanford.edu
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${REPO_DIR}/config/config.yaml"

eval $(python3 "${REPO_DIR}/scripts/parse_config.py" "${CONFIG}")
THREADS=${SLURM_CPUS_PER_TASK:-8}

INPUT="${OUTPUT_BASE_DIR}/00_merged_reads/all_reads.fastq.gz"
OUT_DIR="${OUTPUT_BASE_DIR}/02_filtered"
FILTERED="${OUT_DIR}/filtered_reads.fastq.gz"

# ── Compute filtering parameters ───────────────────────────────────────────────
# calculate_params.py reads total_data_gb and genome size from config and
# decides min_length, keep_percent, and target_bases automatically.
# The full summary is printed here so it appears in the SLURM log.
echo "Computing filtering parameters..."
python3 "${REPO_DIR}/scripts/calculate_params.py" "${CONFIG}" --summary
eval $(python3 "${REPO_DIR}/scripts/calculate_params.py" "${CONFIG}" --export)

if [[ -n "${COMPUTED_WARNINGS}" ]]; then
    echo ""
    echo ">>> ${COMPUTED_WARNINGS}"
    echo ""
fi

echo "=============================================="
echo "  Step 3: Read Filtering (Filtlong)"
echo "  Min length:   ${COMPUTED_MIN_LENGTH} bp"
echo "  Keep percent: ${COMPUTED_KEEP_PERCENT}%"
echo "  Target bases: ${COMPUTED_TARGET_BASES:-disabled}"
echo "  Output:       ${FILTERED}"
echo "=============================================="

conda activate gw_assembly
mkdir -p "${OUT_DIR}"

# ── Guard ──────────────────────────────────────────────────────────────────────
if [[ -f "${FILTERED}" ]]; then
    echo "Filtered reads already exist — skipping."
    exit 0
fi

# ── Verify input ───────────────────────────────────────────────────────────────
if [[ ! -f "${INPUT}" ]]; then
    echo "ERROR: Merged reads not found: ${INPUT}"
    echo "       Run 02_merge.sh first."
    exit 1
fi

# ── Run Filtlong ───────────────────────────────────────────────────────────────
FILTLONG_CMD=(filtlong
    --min_length "${COMPUTED_MIN_LENGTH}"
    --keep_percent "${COMPUTED_KEEP_PERCENT}"
)
if [[ -n "${COMPUTED_TARGET_BASES}" ]]; then
    FILTLONG_CMD+=(--target_bases "${COMPUTED_TARGET_BASES}")
fi

"${FILTLONG_CMD[@]}" "${INPUT}" \
    | pigz -p "${THREADS}" \
    > "${FILTERED}"

# ── Post-filter stats ──────────────────────────────────────────────────────────
echo ""
echo "Filtering complete. Computing stats..."
seqkit stats -a "${FILTERED}" | tee "${OUT_DIR}/filtered_stats.txt"

echo ""
echo "Output: ${FILTERED}"
