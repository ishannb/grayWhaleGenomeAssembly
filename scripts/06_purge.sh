#!/usr/bin/env bash
# =============================================================================
# 06_purge.sh — Haplotig purging with purge_dups
#
# Identifies and removes duplicate contigs arising from heterozygosity
# being assembled as separate sequences rather than collapsed haplotypes.
# Operates on read-to-assembly coverage depth: true primary contigs show
# full coverage (~60x), haplotigs show ~half coverage (~30x).
#
# Submit: sbatch scripts/06_purge.sh
# Manual: bash scripts/06_purge.sh
#
# Cite: Guan et al. (2020) Identifying and removing haplotypic duplication
#       in primary genome assemblies. Bioinformatics, 36(9), 2896-2898.
# =============================================================================
#SBATCH --job-name=gw_06_purge
#SBATCH --output=logs/06_purge_%j.out
#SBATCH --error=logs/06_purge_%j.err
#SBATCH --partition=euan
#SBATCH --account=euan
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --mail-type=FAIL,END
#SBATCH --mail-user=ishannb@stanford.edu
#SBATCH --chdir=/oak/stanford/groups/euan/projects/ishannb/grayWhaleAssembly/grayWhaleGenomeAssembly
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${REPO_DIR}/config/config.yaml"

eval $(python3 "${REPO_DIR}/scripts/parse_config.py" "${CONFIG}")
THREADS=${SLURM_CPUS_PER_TASK:-16}

READS="${OUTPUT_BASE_DIR}/02_filtered/filtered_reads.fastq.gz"
ASSEMBLY="${OUTPUT_BASE_DIR}/04_polished/consensus.fasta"
OUT_DIR="${OUTPUT_BASE_DIR}/05_purged"
PURGED="${OUT_DIR}/purged_assembly.fasta"

echo "=============================================="
echo "  Step 6: Haplotig Purging (purge_dups)"
echo "  Input:   ${ASSEMBLY}"
echo "  Output:  ${OUT_DIR}"
echo "=============================================="

conda activate gw_assembly
mkdir -p "${OUT_DIR}"
cd "${OUT_DIR}"

# ── Guard ──────────────────────────────────────────────────────────────────────
if [[ -f "${PURGED}" ]]; then
    echo "Purged assembly already exists — skipping."
    exit 0
fi

if [[ ! -f "${ASSEMBLY}" ]]; then
    echo "ERROR: Polished assembly not found: ${ASSEMBLY}"
    echo "       Run 05_polish.sh first."
    exit 1
fi

# ── Step 1: Align reads to assembly ───────────────────────────────────────────
echo "[1/5] Aligning reads to polished assembly..."
minimap2 -ax map-ont \
    -t "${THREADS}" \
    "${ASSEMBLY}" \
    "${READS}" \
    | samtools sort -@ "${THREADS}" -o aligned.bam
samtools index aligned.bam

# ── Step 2: Compute coverage ───────────────────────────────────────────────────
echo "[2/5] Computing per-base coverage..."
pb_stat -b aligned.bam -o PB.stat

# ── Step 3: Estimate cutoffs ───────────────────────────────────────────────────
echo "[3/5] Estimating coverage cutoffs..."
# Produces PB.base.cov and cutoffs file
# Review the histogram (PB.stat) before proceeding if unsure of cutoffs
get_seqs -e "${ASSEMBLY}" PB.stat

hist_plot.py -o coverage_histogram.png PB.stat || true  # Optional, non-fatal

# ── Step 4: Purge duplicates ───────────────────────────────────────────────────
echo "[4/5] Purging haplotigs and overlaps..."
purge_dups -2 -T cutoffs -c PB.base.cov "${ASSEMBLY}" > dups.bed

# ── Step 5: Extract purged sequences ──────────────────────────────────────────
echo "[5/5] Extracting purged primary assembly..."
get_seqs -e dups.bed "${ASSEMBLY}"
cp purged.fa "${PURGED}"

echo ""
echo "Purge complete. Stats comparison:"
echo "--- Before purging ---"
seqkit stats -a "${ASSEMBLY}"
echo "--- After purging ---"
seqkit stats -a "${PURGED}" | tee "${OUT_DIR}/purged_stats.txt"

echo ""
echo "Primary output: ${PURGED}"
echo "Haplotigs:      ${OUT_DIR}/hap.fa"
echo ""
echo "IMPORTANT: Inspect coverage_histogram.png and dups.bed"
echo "to verify cutoffs were appropriate before proceeding."
