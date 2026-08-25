#!/usr/bin/env bash
# =============================================================================
# 03_filter.sh — Robust concatenate + filter for large file counts
#
# Handles datasets with tens of thousands of FASTQ files without hitting the
# shell ARG_MAX limit. Works in two stages:
#   1. Concatenate all input files into one merged file, reading the file
#      list via `xargs -a` so cat is invoked in safe batches automatically.
#   2. Run Filtlong on that single merged file.
#
# Both stages integrity-check their output so a killed job never leaves a
# truncated file that the guard would mistake for complete.
#
# Submit: sbatch scripts/03_filter.sh
#
# Cite: Wick R (2021) Filtlong, github.com/rrwick/Filtlong
# =============================================================================
#SBATCH --job-name=gw_03_filter
#SBATCH --output=logs/03_filter_%j.out
#SBATCH --error=logs/03_filter_%j.err
#SBATCH --partition=euan
#SBATCH --account=euan
# Blue whale's filter used exactly 32.0 GiB of a 32G request -- it completed,
# but with zero headroom -- and took 10 h 21 m over 14,677 files. Fin whale has
# 27,263 files and 1.3x the bases, so both limits are raised.
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=48:00:00
#SBATCH --mail-type=FAIL,END
#SBATCH --mail-user=ishannb@stanford.edu
#SBATCH --chdir=/oak/stanford/groups/euan/projects/ishannb/grayWhaleAssembly/grayWhaleGenomeAssembly
set -euo pipefail

REPO_DIR="/oak/stanford/groups/euan/projects/ishannb/grayWhaleAssembly/grayWhaleGenomeAssembly"
CONFIG="${CONFIG:-${REPO_DIR}/config/config.yaml}"

eval $(python3 "${REPO_DIR}/scripts/parse_config.py" "${CONFIG}")
THREADS=${SLURM_CPUS_PER_TASK:-8}

OUT_DIR="${OUTPUT_BASE_DIR}/02_filtered"
MERGE_DIR="${OUTPUT_BASE_DIR}/00_merged_reads"
MERGED="${MERGE_DIR}/all_reads.fastq.gz"
FILTERED="${OUT_DIR}/filtered_reads.fastq.gz"
FILELIST="${OUT_DIR}/input_files.txt"

# ── Compute filtering parameters ───────────────────────────────────────────────
echo "Computing filtering parameters..."
python3 "${REPO_DIR}/scripts/calculate_params.py" "${CONFIG}" --summary
eval $(python3 "${REPO_DIR}/scripts/calculate_params.py" "${CONFIG}" --export)

if [[ -n "${COMPUTED_WARNINGS}" ]]; then
    echo ""
    echo ">>> ${COMPUTED_WARNINGS}"
    echo ""
fi

echo "=============================================="
echo "  Step 3: Concatenate + Filter"
echo "  Min length:   ${COMPUTED_MIN_LENGTH} bp"
echo "  Keep percent: ${COMPUTED_KEEP_PERCENT}%"
echo "  Target bases: ${COMPUTED_TARGET_BASES:-disabled}"
echo "=============================================="

source /home/users/ishannb/miniconda3/etc/profile.d/conda.sh
conda activate gw_assembly
mkdir -p "${OUT_DIR}" "${MERGE_DIR}"

# ── Guard: skip only if a COMPLETE filtered file exists ───────────────────────
if [[ -f "${FILTERED}" ]]; then
    if gzip -t "${FILTERED}" 2>/dev/null; then
        echo "Complete filtered reads already exist — skipping."
        exit 0
    else
        echo "Existing filtered file is truncated — removing."
        rm -f "${FILTERED}"
    fi
fi

# ── Collect input file list ────────────────────────────────────────────────────
echo "Collecting FASTQ files..."
> "${FILELIST}"
for DIR in ${INPUT_FASTQ_DIRS}; do
    if [[ ! -d "${DIR}" ]]; then
        echo "WARNING: directory not found: ${DIR}"
        continue
    fi
    COUNT=$(find "${DIR}" -name "*.fastq.gz" | tee -a "${FILELIST}" | wc -l)
    echo "  ${DIR}: ${COUNT} files"
done
TOTAL_FILES=$(wc -l < "${FILELIST}")
if [[ "${TOTAL_FILES}" -eq 0 ]]; then
    echo "ERROR: No FASTQ files found."
    exit 1
fi
echo "Total input files: ${TOTAL_FILES}"

# ── Stage 1: Concatenate into one merged file ─────────────────────────────────
# Reuse an existing COMPLETE merged file if present; otherwise (re)build it.
# `xargs -a` batches cat automatically, so ARG_MAX is never exceeded.
NEED_MERGE=1
if [[ -f "${MERGED}" ]] && gzip -t "${MERGED}" 2>/dev/null; then
    echo "Complete merged file already exists — reusing it."
    NEED_MERGE=0
fi

if [[ "${NEED_MERGE}" -eq 1 ]]; then
    echo "Concatenating ${TOTAL_FILES} files at $(date)..."
    rm -f "${MERGED}"
    # xargs invokes cat in batches under ARG_MAX; >> appends each batch.
    # All inputs are gzip; concatenated gzip streams are valid gzip.
    xargs -a "${FILELIST}" cat >> "${MERGED}"
    echo "Concatenation finished at $(date)."

    if ! gzip -t "${MERGED}" 2>/dev/null; then
        echo "ERROR: merged file failed integrity check (job likely killed)."
        exit 1
    fi
fi

# ── Stage 2: Filter the single merged file ────────────────────────────────────
FILTLONG_CMD=(filtlong
    --min_length "${COMPUTED_MIN_LENGTH}"
    --keep_percent "${COMPUTED_KEEP_PERCENT}"
)
if [[ -n "${COMPUTED_TARGET_BASES}" ]]; then
    FILTLONG_CMD+=(--target_bases "${COMPUTED_TARGET_BASES}")
fi

echo ""
echo "Running Filtlong at $(date)..."
"${FILTLONG_CMD[@]}" "${MERGED}" \
    | pigz -p "${THREADS}" \
    > "${FILTERED}"
echo "Filtlong finished at $(date)."

# ── Verify output ──────────────────────────────────────────────────────────────
if ! gzip -t "${FILTERED}" 2>/dev/null; then
    echo "ERROR: filtered output failed integrity check."
    exit 1
fi

# ── Optional: free the large merged file to save scratch space ────────────────
# Comment this out if you want to keep the merged reads.
echo "Removing intermediate merged file to save space..."
rm -f "${MERGED}"

# ── Stats (non-fatal) ──────────────────────────────────────────────────────────
echo ""
echo "Computing filtered read stats (non-fatal)..."
seqkit stats -a "${FILTERED}" > "${OUT_DIR}/filtered_stats.txt" 2>&1 \
    && cat "${OUT_DIR}/filtered_stats.txt" \
    || echo "stats skipped (non-fatal)"

echo ""
echo "Output: ${FILTERED}"
