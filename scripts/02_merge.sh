#!/usr/bin/env bash
# =============================================================================
# 02_merge.sh — Merge FASTQ files from both PromethION run directories
#
# Concatenates all .fastq.gz files from both runs into a single gzipped FASTQ.
# This is necessary because data was collected across two flow cell runs.
#
# Submit: sbatch scripts/02_merge.sh
# Manual: bash scripts/02_merge.sh
# =============================================================================
#SBATCH --job-name=gw_02_merge
#SBATCH --output=logs/02_merge_%j.out
#SBATCH --error=logs/02_merge_%j.err
#SBATCH --partition=euan
#SBATCH --account=euan
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=4:00:00
#SBATCH --mail-type=FAIL,END
#SBATCH --mail-user=ishannb@stanford.edu
#SBATCH --chdir=/oak/stanford/groups/euan/projects/ishannb/grayWhaleAssembly/grayWhaleGenomeAssembly
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${REPO_DIR}/config/config.yaml"

eval $(python3 "${REPO_DIR}/scripts/parse_config.py" "${CONFIG}")
THREADS=${SLURM_CPUS_PER_TASK:-8}
OUT_DIR="${OUTPUT_BASE_DIR}/00_merged_reads"
MERGED="${OUT_DIR}/all_reads.fastq.gz"

echo "=============================================="
echo "  Step 2: Merge reads from both run dirs"
echo "  Output: ${MERGED}"
echo "=============================================="

conda activate gw_qc
mkdir -p "${OUT_DIR}"

# ── Guard ──────────────────────────────────────────────────────────────────────
if [[ -f "${MERGED}" ]]; then
    echo "Merged file already exists — skipping."
    exit 0
fi

# ── Collect and merge ──────────────────────────────────────────────────────────
echo "Collecting FASTQ files from both run directories..."
FASTQ_FILES=()
for DIR in ${INPUT_FASTQ_DIRS}; do
    if [[ ! -d "${DIR}" ]]; then
        echo "WARNING: directory not found: ${DIR}"
        continue
    fi
    COUNT=$(find "${DIR}" -name "*.fastq.gz" | wc -l)
    echo "  ${DIR}: ${COUNT} files"
    while IFS= read -r -d '' f; do
        FASTQ_FILES+=("$f")
    done < <(find "${DIR}" -name "*.fastq.gz" -print0)
done

echo "Total files to merge: ${#FASTQ_FILES[@]}"
echo "Merging (streaming, no decompression)..."

# cat preserves gzip format when all inputs are .gz
cat "${FASTQ_FILES[@]}" > "${MERGED}"

# ── Verify and summarise ───────────────────────────────────────────────────────
echo "Merge complete. Running seqkit stats..."
seqkit stats -a "${MERGED}" | tee "${OUT_DIR}/merged_stats.txt"

TOTAL_GB=$(awk 'NR==2 {printf "%.1f", $5/1e9}' "${OUT_DIR}/merged_stats.txt")
echo ""
echo "Total data: ~${TOTAL_GB} Gb"
echo "Output:     ${MERGED}"
