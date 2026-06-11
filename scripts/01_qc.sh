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
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${REPO_DIR}/config/config.yaml"

# ── Parse config ───────────────────────────────────────────────────────────────
eval $(python3 "${REPO_DIR}/scripts/parse_config.py" "${CONFIG}")
THREADS=${SLURM_CPUS_PER_TASK:-8}
OUT_DIR="${OUTPUT_BASE_DIR}/01_qc"

echo "=============================================="
echo "  Step 1: Read QC (NanoPlot)"
echo "  FASTQ dirs: ${INPUT_FASTQ_DIRS}"
echo "  Output:     ${OUT_DIR}"
echo "=============================================="

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
    done < <(find "${DIR}" -name "*.fastq.gz" -o -name "*.fastq" -print0 2>/dev/null)
done

if [[ ${#FASTQ_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No FASTQ files found in configured directories."
    exit 1
fi
echo "Found ${#FASTQ_FILES[@]} FASTQ file(s) across both runs."

# ── Run NanoPlot ───────────────────────────────────────────────────────────────
NanoPlot \
    --fastq "${FASTQ_FILES[@]}" \
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
