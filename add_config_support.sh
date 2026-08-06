#!/usr/bin/env bash
# =============================================================================
# add_config_support.sh — One-time migration: make scripts accept CONFIG env var
#
# Run this ONCE from the repo root to update all step scripts + run_pipeline.sh
# so they can run different samples via different config files.
#
# After running this:
#   bash scripts/run_pipeline.sh --config config/blue_whale.yaml
#
# Usage: bash add_config_support.sh
# =============================================================================
set -euo pipefail

REPO="/oak/stanford/groups/euan/projects/ishannb/grayWhaleAssembly/grayWhaleGenomeAssembly"
cd "$REPO"

echo "Updating step scripts to honor CONFIG environment variable..."

# ── Step scripts: make CONFIG default to env var, fall back to config.yaml ────
for script in scripts/01_qc.sh scripts/02_merge.sh scripts/03_filter.sh \
              scripts/04_assemble.sh scripts/05_polish.sh scripts/06_purge.sh \
              scripts/07_assess.sh; do

    # Replace the hardcoded CONFIG line with one that honors an env var
    python3 - "$script" <<'PYEOF'
import sys
path = sys.argv[1]
content = open(path).read()

old = 'CONFIG="${REPO_DIR}/config/config.yaml"'
new = 'CONFIG="${CONFIG:-${REPO_DIR}/config/config.yaml}"'

if old in content:
    content = content.replace(old, new)
    open(path, 'w').write(content)
    print(f"  Updated: {path}")
else:
    if new in content:
        print(f"  Already updated: {path}")
    else:
        print(f"  WARNING: CONFIG line not found in {path}")
PYEOF
done

echo ""
echo "Updating run_pipeline.sh to accept --config and pass it through..."

python3 - <<'PYEOF'
path = "scripts/run_pipeline.sh"
content = open(path).read()

# 1. Add --config parsing next to --from
if "--config" not in content:
    old_from = '''FROM_STEP=1
if [[ "${1:-}" == "--from" && -n "${2:-}" ]]; then
    FROM_STEP="${2}"
    echo "Resuming from step ${FROM_STEP}"
fi'''

    new_from = '''FROM_STEP=1
CONFIG_ARG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --from)   FROM_STEP="$2"; shift 2 ;;
        --config) CONFIG_ARG="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# Resolve config path (absolute) and export so all step scripts inherit it
if [[ -n "${CONFIG_ARG}" ]]; then
    export CONFIG="$(cd "$(dirname "${CONFIG_ARG}")" && pwd)/$(basename "${CONFIG_ARG}")"
    echo "Using config: ${CONFIG}"
fi
[[ "${FROM_STEP}" != "1" ]] && echo "Resuming from step ${FROM_STEP}"'''

    if old_from in content:
        content = content.replace(old_from, new_from)
        print("  Added --config parsing")
    else:
        print("  WARNING: could not find --from block to replace")

# 2. Make submit_job pass CONFIG through to sbatch via --export
if "--export=ALL,CONFIG" not in content:
    content = content.replace(
        'JOB_ID=$(sbatch --dependency=afterok:"${DEPENDS}" \\\n                        --parsable "${SCRIPTS}/${SCRIPT}")',
        'JOB_ID=$(sbatch --dependency=afterok:"${DEPENDS}" \\\n                        --export=ALL,CONFIG="${CONFIG:-}" \\\n                        --parsable "${SCRIPTS}/${SCRIPT}")'
    )
    content = content.replace(
        'JOB_ID=$(sbatch --parsable "${SCRIPTS}/${SCRIPT}")',
        'JOB_ID=$(sbatch --export=ALL,CONFIG="${CONFIG:-}" --parsable "${SCRIPTS}/${SCRIPT}")'
    )
    print("  Made submit_job pass CONFIG to sbatch")

open(path, 'w').write(content)
PYEOF

echo ""
echo "Done. Now you can run:"
echo "  bash scripts/run_pipeline.sh --config config/blue_whale.yaml"
