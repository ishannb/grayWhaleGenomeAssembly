#!/usr/bin/env bash
# =============================================================================
# switch_to_streaming.sh — Remove merge step, use streaming filter
#
# Run once from repo root.
# Usage: bash switch_to_streaming.sh
# =============================================================================
set -euo pipefail

REPO="/oak/stanford/groups/euan/projects/ishannb/grayWhaleAssembly/grayWhaleGenomeAssembly"
cd "$REPO"

# ── 1. Remove step 2 (merge) from run_pipeline.sh dependency chain ────────────
echo "Updating run_pipeline.sh to skip merge step..."
python3 - <<'PYEOF'
path = "scripts/run_pipeline.sh"
content = open(path).read()

# Find and neutralize the merge submission block.
# The filter step (03) should no longer depend on merge (02).
# We make step 3 the first job in the chain (no dependency).

import re

# Different pipeline versions have slightly different blocks; handle the
# parallel-chain version present in this repo.
if "02_merge.sh" in content:
    # Remove the merge submission block entirely
    lines = content.splitlines()
    out = []
    skip = False
    for line in lines:
        if "02_merge.sh" in line and ("submit_job" in line or "Step 2" in line or "MERGE_JOB" in line):
            skip = True  # begin skipping the merge block
        # Stop skipping once we hit the filter block
        if "03_filter.sh" in line or "FILTER_JOB" in line or "Step 3" in line:
            skip = False
        if not skip:
            out.append(line)
    content = "\n".join(out)

    # Make filter no longer depend on a merge job — first in chain
    content = content.replace(
        'FILTER_JOB=$(submit_job "03_filter.sh" "${PREV_JOB}")',
        'FILTER_JOB=$(submit_job "03_filter.sh")'
    )
    content = content.replace(
        'PREV_JOB=$(submit_job "03_filter.sh" "${PREV_JOB}")',
        'PREV_JOB=$(submit_job "03_filter.sh")'
    )
    open(path, 'w').write(content)
    print("  Removed merge from pipeline chain")
else:
    print("  No merge references found (already removed?)")
PYEOF

echo ""
echo "Cleaning up any truncated intermediate files..."
rm -f /scratch/groups/euan/blue_whale_assembly/00_merged_reads/all_reads.fastq.gz
rm -f /scratch/groups/euan/blue_whale_assembly/02_filtered/filtered_reads.fastq.gz
echo "  Done."

echo ""
echo "=============================================="
echo "  Streaming filter is now active."
echo "  Merge step is bypassed — filter reads all"
echo "  FASTQ files directly in one streaming pass."
echo ""
echo "  Launch blue whale from the filter step:"
echo "    bash scripts/run_pipeline.sh --config config/blue_whale.yaml --from 3"
echo "=============================================="
