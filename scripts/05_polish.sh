#!/usr/bin/env bash
# =============================================================================
# 05_polish.sh — Assembly polishing with Medaka
#
# Corrects systematic errors in the Flye draft assembly by re-aligning
# raw reads and applying a trained neural network consensus model.
#
# Model: r1041_e82_400bps_sup_v5.0.0
#   -> Matches R10.4.1 flow cell + SUP basecalling via MinKNOW
#   -> Run `medaka tools list_models` to verify availability
#
# Submit: sbatch scripts/05_polish.sh
# Manual: bash scripts/05_polish.sh
#
# Cite: Oxford Nanopore Technologies (2023) Medaka v1.11,
#       github.com/nanoporetech/medaka
# =============================================================================
#SBATCH --job-name=gw_05_polish
#SBATCH --output=logs/05_polish_%j.out
#SBATCH --error=logs/05_polish_%j.err
#SBATCH --partition=gpu
#SBATCH --account=euan
#SBATCH --gres=gpu:1
# A 12GB GPU (TITAN Xp) is not enough: medaka inference on a 2.4Gb draft OOMs
# trying to allocate ~5.8GB on top of an already-fragmented heap. Require a
# 32GB+ card. Note the euan partition's GPUs are all 12GB TITAN Xp, so this
# job must run in the shared gpu partition.
#SBATCH -C "GPU_MEM:32GB|GPU_MEM:48GB|GPU_MEM:80GB"
#SBATCH --cpus-per-task=16
#SBATCH --mem=160G
#SBATCH --time=48:00:00
#SBATCH --mail-type=FAIL,END
#SBATCH --mail-user=ishannb@stanford.edu
#SBATCH --chdir=/oak/stanford/groups/euan/projects/ishannb/grayWhaleAssembly/grayWhaleGenomeAssembly
set -euo pipefail

REPO_DIR="/oak/stanford/groups/euan/projects/ishannb/grayWhaleAssembly/grayWhaleGenomeAssembly"
CONFIG="${CONFIG:-${REPO_DIR}/config/config.yaml}"

eval $(python3 "${REPO_DIR}/scripts/parse_config.py" "${CONFIG}")
THREADS=${SLURM_CPUS_PER_TASK:-32}

READS="${OUTPUT_BASE_DIR}/02_filtered/filtered_reads.fastq.gz"
DRAFT="${OUTPUT_BASE_DIR}/03_assembly/assembly.fasta"
OUT_DIR="${OUTPUT_BASE_DIR}/04_polished"
POLISHED="${OUT_DIR}/consensus.fasta"

echo "=============================================="
echo "  Step 5: Polishing (Medaka)"
echo "  Model:   ${MEDAKA_MODEL}"
echo "  Rounds:  ${MEDAKA_ROUNDS}"
echo "  Threads: ${THREADS}"
echo "=============================================="

# medaka_consensus is a wrapper that shells out to minimap2/samtools/bcftools/
# bgzip/tabix. The py-medaka module ships medaka alone, so the helpers must be
# loaded alongside it or the run dies during medaka's version check.
ml biology py-medaka/2.1.0_py312 samtools/1.16.1 bcftools/1.16 htslib/1.16 minimap2/2.30

# The previous OOM had only 575MB actually allocated but 5.8GB reserved-and-
# unallocated by the caching allocator -- i.e. fragmentation, not true demand.
# Expandable segments let the allocator grow blocks instead of stranding them.
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

mkdir -p "${OUT_DIR}"

# ── Guard ──────────────────────────────────────────────────────────────────────
if [[ -f "${POLISHED}" ]]; then
    echo "Polished assembly already exists — skipping."
    exit 0
fi

# ── Verify inputs ──────────────────────────────────────────────────────────────
if [[ ! -f "${DRAFT}" ]]; then
    echo "ERROR: Draft assembly not found: ${DRAFT}"
    echo "       Run 04_assemble.sh first."
    exit 1
fi

# ── Verify model exists ────────────────────────────────────────────────────────
echo "Checking Medaka model: ${MEDAKA_MODEL}"
if ! medaka tools list_models 2>/dev/null | grep -q "${MEDAKA_MODEL}"; then
    echo "WARNING: Model '${MEDAKA_MODEL}' not found. Available models:"
    medaka tools list_models
    echo ""
    echo "Update medaka.model in config/config.yaml and retry."
    exit 1
fi

# ── Polishing rounds ───────────────────────────────────────────────────────────
CURRENT_DRAFT="${DRAFT}"

for ROUND in $(seq 1 "${MEDAKA_ROUNDS}"); do
    ROUND_DIR="${OUT_DIR}/round_${ROUND}"
    ROUND_OUT="${ROUND_DIR}/consensus.fasta"

    if [[ -f "${ROUND_OUT}" ]]; then
        echo "Round ${ROUND} already complete — skipping."
        CURRENT_DRAFT="${ROUND_OUT}"
        continue
    fi

    echo "Polishing round ${ROUND}/${MEDAKA_ROUNDS} at $(date)..."
    mkdir -p "${ROUND_DIR}"

    medaka_consensus \
        -i "${READS}" \
        -d "${CURRENT_DRAFT}" \
        -o "${ROUND_DIR}" \
        -m "${MEDAKA_MODEL}" \
        -b 100 \
        -t "${THREADS}"

    CURRENT_DRAFT="${ROUND_OUT}"
    echo "Round ${ROUND} complete."
done

# ── Copy final result ──────────────────────────────────────────────────────────
cp "${CURRENT_DRAFT}" "${POLISHED}"

echo ""
echo "Polishing complete."
seqkit stats -a "${POLISHED}" | tee "${OUT_DIR}/polished_stats.txt"
echo ""
echo "Output: ${POLISHED}"
