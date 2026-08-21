#!/usr/bin/env bash
# =============================================================================
# preflight.sh — Validate config and preview computed parameters
#
# Run this BEFORE submitting the pipeline to catch config errors and
# verify that filtering parameters look sensible for your data.
#
# Usage: bash scripts/preflight.sh
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-${REPO_DIR}/config/config.yaml}"

echo "=============================================="
echo "  Pipeline Pre-flight Check"
echo "=============================================="
echo ""

# ── 1. Check config exists ─────────────────────────────────────────────────────
if [[ ! -f "${CONFIG}" ]]; then
    echo "ERROR: config.yaml not found at ${CONFIG}"
    exit 1
fi
echo "[✓] config/config.yaml found"

# ── 2. Check Python + pyyaml ──────────────────────────────────────────────────
python3 -c "import yaml" 2>/dev/null || {
    echo "ERROR: pyyaml not available. Run: pip install pyyaml"
    exit 1
}
echo "[✓] Python + pyyaml available"

# ── 3. Check input directories exist ──────────────────────────────────────────
echo ""
echo "Checking input directories..."
python3 << PYEOF
import yaml, os, sys
with open("${CONFIG}") as f:
    c = yaml.safe_load(f)
dirs = c['input'].get('fastq_dirs', [])
all_ok = True
for d in dirs:
    exists = os.path.isdir(d)
    status = "[✓]" if exists else "[✗]"
    print(f"  {status} {d}")
    if not exists:
        all_ok = False
if not all_ok:
    print("\nWARNING: Some directories not found. Check paths in config.yaml.")
else:
    print(f"\n  All {len(dirs)} FASTQ directories found.")
PYEOF

# ── 4. Show computed parameters ────────────────────────────────────────────────
echo ""
python3 "${REPO_DIR}/scripts/calculate_params.py" "${CONFIG}" --summary

# ── 5. Check output dir parent is writable ────────────────────────────────────
BASE_DIR=$(python3 -c "
import yaml
with open('${CONFIG}') as f:
    c = yaml.safe_load(f)
print(c['output']['base_dir'])
")
PARENT=$(dirname "${BASE_DIR}")
if [[ -w "${PARENT}" ]] || [[ -d "${BASE_DIR}" ]]; then
    echo "[✓] Output directory writable: ${BASE_DIR}"
else
    echo "[✗] WARNING: Cannot write to ${BASE_DIR}"
    echo "    Check that the parent directory exists and you have write permissions."
fi

echo ""
echo "=============================================="
echo "  Pre-flight complete."
echo "  If everything looks good, run:"
echo "    bash scripts/run_pipeline.sh"
echo "=============================================="
