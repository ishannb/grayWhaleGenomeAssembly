#!/usr/bin/env bash
# =============================================================================
# 05b_polish_resume.sh — Finish a partially-completed Medaka inference
#
# Medaka runs inference in two passes: a main batched pass over most of the
# genome, then a "remainder" pass over regions it deferred (predominantly
# short contigs). If the job dies during the remainder pass, the main pass
# results are already durable in consensus_probs.hdf and must not be thrown
# away -- on blue whale that was 2,390 Mb of 2,433 Mb, ~56 min of H100 time.
#
# This script resumes by:
#   1. Deriving the regions already present in the HDF   (medaka tools hdf_to_bed)
#   2. Subtracting them from the draft to get what's left (missing.bed)
#   3. Running inference on ONLY those regions           -> a second HDF
#   4. Stitching both HDFs together                      (medaka sequence)
#
# Because only the leftover fraction is reprocessed, memory demand is a small
# fraction of the original run -- no need to raise --mem.
#
# Submit: sbatch --export=ALL,CONFIG=$(pwd)/config/blue_whale.yaml \
#                scripts/05b_polish_resume.sh
# =============================================================================
#SBATCH --job-name=gw_05b_resume
#SBATCH --output=logs/05b_resume_%j.out
#SBATCH --error=logs/05b_resume_%j.err
# No GPU. The remainder regions crash cuDNN's GRU kernel with
# CUDNN_STATUS_NOT_SUPPORTED regardless of precision or batch size (confirmed
# at fp16/batch100 and fp32/batch50). They are short regions on a separate
# medaka code path, and the pileups come back shorter than requested. Running
# them on CPU sidesteps cuDNN entirely, and at ~43 Mb -- 1.8% of the genome --
# the GPU bought nothing. This also keeps the job off the contended gpu queue.
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

DRAFT="${OUTPUT_BASE_DIR}/03_assembly/assembly.fasta"
OUT_DIR="${OUTPUT_BASE_DIR}/04_polished"
ROUND_DIR="${OUT_DIR}/round_1"
BAM="${ROUND_DIR}/calls_to_draft.bam"
MAIN_HDF="${ROUND_DIR}/consensus_probs.hdf"
REST_HDF="${ROUND_DIR}/consensus_probs_remainder.hdf"
COVERED="${ROUND_DIR}/covered.bed"
MISSING="${ROUND_DIR}/missing.bed"
POLISHED="${OUT_DIR}/consensus.fasta"

ml biology py-medaka/2.1.0_py312 samtools/1.16.1 bcftools/1.16 htslib/1.16 minimap2/2.30

echo "=============================================="
echo "  Step 5b: Resume Medaka inference"
echo "  Model:   ${MEDAKA_MODEL}"
echo "  Threads: ${THREADS}"
echo "=============================================="

# ── Guard ──────────────────────────────────────────────────────────────────────
if [[ -f "${POLISHED}" ]]; then
    echo "Polished assembly already exists — nothing to do."
    exit 0
fi
for f in "${DRAFT}" "${BAM}" "${MAIN_HDF}"; do
    [[ -f "$f" ]] || { echo "ERROR: missing required input: $f"; exit 1; }
done

# ── 1. Regions already inferred ───────────────────────────────────────────────
echo "[1/4] Deriving regions already present in the HDF..."
medaka tools hdf_to_bed "${MAIN_HDF}" "${COVERED}"
awk '{s+=$3-$2} END {printf "      covered: %.1f Mb over %d intervals\n", s/1e6, NR}' "${COVERED}"

# ── 2. Complement -> what still needs inference ───────────────────────────────
echo "[2/4] Computing outstanding regions..."
python3 - "${DRAFT}.fai" "${COVERED}" "${MISSING}" <<'PY'
import sys
from collections import defaultdict
fai, cov, out = sys.argv[1], sys.argv[2], sys.argv[3]

lens = {}
for line in open(fai):
    f = line.split("\t")
    lens[f[0]] = int(f[1])

covered = defaultdict(list)
for line in open(cov):
    f = line.split("\t")
    covered[f[0]].append((int(f[1]), int(f[2])))

total = 0
n = 0
with open(out, "w") as o:
    for c, L in lens.items():
        merged = []
        for s, e in sorted(covered.get(c, [])):
            if merged and s <= merged[-1][1]:
                merged[-1] = (merged[-1][0], max(merged[-1][1], e))
            else:
                merged.append((s, e))
        pos = 0
        gaps = []
        for s, e in merged:
            if s > pos:
                gaps.append((pos, s))
            pos = max(pos, e)
        if pos < L:
            gaps.append((pos, L))
        for s, e in gaps:
            o.write("%s\t%d\t%d\n" % (c, s, e))
            total += e - s
            n += 1
print("      outstanding: %.1f Mb over %d intervals" % (total / 1e6, n))
if n == 0:
    print("      nothing outstanding — main HDF is already complete")
PY

# ── 3. Inference on the outstanding regions only ──────────────────────────────
if [[ -s "${MISSING}" ]]; then
    if [[ -f "${REST_HDF}" ]]; then
        echo "[3/4] Remainder HDF already exists — reusing."
    else
        echo "[3/4] Running inference on outstanding regions (CPU) at $(date)..."
        # --cpu: see the SBATCH note above. cuDNN's GRU kernel aborts on these
        # short regions on any GPU path; the CPU implementation handles them.
        # Expect roughly 15-45 min for ~43 Mb.
        medaka inference \
            "${BAM}" \
            "${REST_HDF}.tmp" \
            --regions "${MISSING}" \
            --model "${MEDAKA_MODEL}" \
            --cpu \
            --threads "${THREADS}"
        mv "${REST_HDF}.tmp" "${REST_HDF}"
        echo "      inference finished at $(date)."
    fi
    STITCH_INPUTS=("${MAIN_HDF}" "${REST_HDF}")
else
    echo "[3/4] No outstanding regions — skipping inference."
    STITCH_INPUTS=("${MAIN_HDF}")
fi

# ── 4. Stitch all HDFs into the final consensus ───────────────────────────────
# Any region still unpolished is backfilled with draft sequence, so contig
# count and total length always match the draft.
echo "[4/4] Stitching ${#STITCH_INPUTS[@]} HDF file(s) at $(date)..."
medaka sequence \
    "${STITCH_INPUTS[@]}" \
    "${DRAFT}" \
    "${ROUND_DIR}/consensus.fasta" \
    --threads "${THREADS}"

cp "${ROUND_DIR}/consensus.fasta" "${POLISHED}"

echo ""
echo "Polishing complete."
seqkit stats -a "${POLISHED}" | tee "${OUT_DIR}/polished_stats.txt" 2>/dev/null \
    || echo "(seqkit unavailable — skipping stats)"
echo ""
echo "  draft contigs:     $(wc -l < "${DRAFT}.fai")"
echo "  consensus contigs: $(grep -c '^>' "${POLISHED}")"
echo "  Output: ${POLISHED}"
