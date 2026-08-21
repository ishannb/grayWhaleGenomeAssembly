#!/usr/bin/env bash
# =============================================================================
# make_polish_gpu.sh — Convert step 5 (Medaka) to run on GPU
#
# Medaka on CPU is far too slow for a mammalian genome (>75h). On a GPU it
# finishes in ~8-10h. The euan partition has 4 GPUs, so no shared-queue wait.
#
# Run once from repo root: bash make_polish_gpu.sh
# =============================================================================
set -euo pipefail

REPO="/oak/stanford/groups/euan/projects/ishannb/grayWhaleAssembly/grayWhaleGenomeAssembly"
cd "$REPO"

python3 - <<'PYEOF'
path = "scripts/05_polish.sh"
content = open(path).read()

# 1. Switch SBATCH resources to GPU
content = content.replace(
    "#SBATCH --partition=euan\n#SBATCH --account=euan\n#SBATCH --cpus-per-task=32\n#SBATCH --mem=128G",
    "#SBATCH --partition=euan\n#SBATCH --account=euan\n#SBATCH --gres=gpu:1\n#SBATCH --cpus-per-task=16\n#SBATCH --mem=128G"
)

# 2. Use the GPU medaka environment
content = content.replace(
    "conda activate gw_medaka",
    "conda activate gw_medaka_gpu"
)

# 3. medaka_consensus auto-detects GPU; no flag change needed, but reduce
#    batch size to avoid GPU OOM on large genomes (safe default)
content = content.replace(
    "        -m \"${MEDAKA_MODEL}\" \\\n        -t \"${THREADS}\"",
    "        -m \"${MEDAKA_MODEL}\" \\\n        -b 100 \\\n        -t \"${THREADS}\""
)

open(path, 'w').write(content)
print("Updated 05_polish.sh for GPU")
PYEOF

echo ""
echo "Verifying changes:"
grep -n "gres\|gpu\|partition\|conda activate\|-b 100" scripts/05_polish.sh | head

echo ""
echo "Done. Clean the incomplete CPU polish output, then resubmit:"
echo "  rm -rf /scratch/groups/euan/blue_whale_assembly/04_polished/round_1"
echo "  bash scripts/run_pipeline.sh --config config/blue_whale.yaml --from 5"
