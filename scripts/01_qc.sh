#!/usr/bin/env bash
# =============================================================================
# 01_qc.sh — Read QC with NanoPlot / NanoStat
#
# Assesses raw ONT read quality across BOTH run directories before filtering.
# Outputs: HTML report, summary stats, read length + quality distributions.
#
# Submit: sbatch scripts/01_qc.sh
# Manual: bash scripts/01_qc.sh
#
# Cite: De Coster & Rademakers (2023) NanoPack2, Bioinformatics
# =============================================================================
#SBATCH --job-name=gw_01_qc
#SBATCH --output=logs/01_qc_%j.out
#SBATCH --error=logs/01_qc_%j.err
#SBATCH --partition=euan
#SBATCH --account=euan
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=4:00:00
#SBATCH --mail-type=FAIL,END
#SBATCH --mail-user=ishannb@stanford.edu
#SBATCH --chdir=/oak/stanford/groups/euan/projects/ishannb/grayWhaleAssembly/grayWhaleGenomeAssembly
set -euo pipefail

REPO_DIR="/oak/stanford/groups/euan/projects/ishannb/grayWhaleAssembly/grayWhaleGenomeAssembly"
CONFIG="${CONFIG:-${REPO_DIR}/config/config.yaml}"

# ── Parse config ───────────────────────────────────────────────────────────────
eval $(python3 "${REPO_DIR}/scripts/parse_config.py" "${CONFIG}")
THREADS=${SLURM_CPUS_PER_TASK:-8}
OUT_DIR="${OUTPUT_BASE_DIR}/01_qc"

echo "=============================================="
echo "  Step 1: Read QC (NanoPlot)"
echo "  FASTQ dirs: ${INPUT_FASTQ_DIRS}"
echo "  Output:     ${OUT_DIR}"
echo "=============================================="

source /home/users/ishannb/miniconda3/etc/profile.d/conda.sh
conda activate gw_qc
mkdir -p "${OUT_DIR}"

# ── Guard: skip if already done ────────────────────────────────────────────────
if [[ -f "${OUT_DIR}/NanoPlot-report.html" ]]; then
    echo "QC report already exists — skipping (delete ${OUT_DIR} to rerun)."
    exit 0
fi

# ── Collect all FASTQ files from both run directories ─────────────────────────
echo "Collecting FASTQ files..."
FASTQ_FILES=()
for DIR in ${INPUT_FASTQ_DIRS}; do
    if [[ ! -d "${DIR}" ]]; then
        echo "WARNING: FASTQ directory not found: ${DIR}"
        continue
    fi
    while IFS= read -r -d '' f; do
        FASTQ_FILES+=("$f")
    done < <(find "${DIR}" \( -name "*.fastq.gz" -o -name "*.fastq" \) -print0 2>/dev/null)
done

if [[ ${#FASTQ_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No FASTQ files found in configured directories."
    exit 1
fi
echo "Found ${#FASTQ_FILES[@]} FASTQ file(s) across both runs."

# ── Run NanoPlot ───────────────────────────────────────────────────────────────
# With very large file counts (thousands of FASTQs), passing every file to
# NanoPlot exceeds the shell argument limit. NanoPlot only needs a
# representative sample to characterise read quality, so we cap the number
# of files passed. 500 files is more than enough for stable statistics.
MAX_QC_FILES=500
if [[ ${#FASTQ_FILES[@]} -gt ${MAX_QC_FILES} ]]; then
    echo "Large file count (${#FASTQ_FILES[@]}); sampling ${MAX_QC_FILES} for QC."
    QC_FILES=( "${FASTQ_FILES[@]:0:${MAX_QC_FILES}}" )
else
    QC_FILES=( "${FASTQ_FILES[@]}" )
fi

NanoPlot \
    --fastq "${QC_FILES[@]}" \
    --outdir "${OUT_DIR}" \
    --threads "${THREADS}" \
    --plots dot \
    --N50 \
    --loglength \
    --title "Gray Whale (E. robustus) ONT Reads — Pre-filter"

echo ""
echo "QC complete."
echo "Report: ${OUT_DIR}/NanoPlot-report.html"
echo "Stats:  ${OUT_DIR}/NanoStats.txt"
