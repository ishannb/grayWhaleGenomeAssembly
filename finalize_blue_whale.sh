#!/usr/bin/env bash
# =============================================================================
# finalize_blue_whale.sh — Add --config to preflight, verify blue whale paths
#
# Run once from repo root.
# Usage: bash finalize_blue_whale.sh
# =============================================================================
set -euo pipefail

REPO="/oak/stanford/groups/euan/projects/ishannb/grayWhaleAssembly/grayWhaleGenomeAssembly"
cd "$REPO"

# ── 1. Make preflight.sh honor CONFIG env var ─────────────────────────────────
echo "Updating preflight.sh..."
python3 - <<'PYEOF'
path = "scripts/preflight.sh"
content = open(path).read()
old = 'CONFIG="${REPO_DIR}/config/config.yaml"'
new = 'CONFIG="${CONFIG:-${REPO_DIR}/config/config.yaml}"'
if old in content:
    content = content.replace(old, new)
    open(path, 'w').write(content)
    print("  preflight.sh updated")
elif new in content:
    print("  preflight.sh already updated")
else:
    print("  WARNING: CONFIG line not found in preflight.sh")
PYEOF

# ── 2. Verify blue whale input paths + file counts ────────────────────────────
echo ""
echo "Verifying blue whale input directories..."
LIB1="/oak/stanford/groups/euan/projects/promethion_wet_lab/whale_data/Blue_Whale_Seq_LR/Blue_whale_lib_1/basecalling/pass"
LIB2="/oak/stanford/groups/euan/projects/promethion_wet_lab/whale_data/Blue_Whale_Seq_LR/Blue_whaleLib_2/basecalling/pass"

for DIR in "$LIB1" "$LIB2"; do
    if [[ -d "$DIR" ]]; then
        COUNT=$(ls "$DIR"/*.fastq.gz 2>/dev/null | wc -l)
        echo "  [OK] $DIR"
        echo "       $COUNT fastq.gz files"
    else
        echo "  [MISSING] $DIR"
    fi
done

echo ""
echo "Done. To launch blue whale:"
echo "  CONFIG=\$(pwd)/config/blue_whale.yaml bash scripts/preflight.sh"
echo "  bash scripts/run_pipeline.sh --config config/blue_whale.yaml"
