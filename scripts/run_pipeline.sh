#!/usr/bin/env bash
# =============================================================================
# run_pipeline.sh — Submit all pipeline jobs with SLURM dependencies
#
# PARALLEL EXECUTION STRATEGY:
#
# Not all steps depend on each other. The dependency graph is:
#
#   01_qc ─────────────────────────────────────────── (reporting only)
#                                                              │
#   02_merge ──► 03_filter ──► 04_assemble ──► 05_polish ──► 06_purge ──► 07_assess
#
# QC (Step 1) reads the raw FASTQs just to report statistics — it does NOT
# produce anything the assembly chain needs. So we run it in PARALLEL with
# the merge/filter/assemble chain rather than blocking on it.
#
# This saves the QC wall-clock time (~4h) from the critical path entirely.
#
# Timeline comparison:
#   Sequential: QC(4h) → merge(4h) → filter(8h) → assembly(72h) → ... = ~100h
#   Parallel:   [QC(4h)]                                                  |
#               merge(4h) → filter(8h) → assembly(72h) → ...           = ~96h
#   (Modest gain here since assembly dominates, but principle matters for
#    future steps like running BUSCO during polishing, etc.)
#
# Usage:
#   bash scripts/run_pipeline.sh            # run all steps
#   bash scripts/run_pipeline.sh --from 4   # resume from assembly onward
#   bash scripts/run_pipeline.sh --dry-run  # print jobs without submitting
#
# Job IDs are logged to logs/pipeline_run_<timestamp>.log
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="${REPO_DIR}/scripts"
LOGS="${REPO_DIR}/logs"
mkdir -p "${LOGS}"

# ── Parse arguments ────────────────────────────────────────────────────────────
FROM_STEP=1
DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --from)    FROM_STEP="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG="${LOGS}/pipeline_run_${TIMESTAMP}.log"

echo "=============================================="
echo "  Gray Whale Assembly Pipeline"
echo "  Started:   $(date)"
echo "  From step: ${FROM_STEP}"
echo "  Dry run:   ${DRY_RUN}"
echo "  Log:       ${LOG}"
echo "=============================================="
echo ""

# ── Run preflight check ────────────────────────────────────────────────────────
echo "Running preflight check..."
bash "${SCRIPTS}/preflight.sh"
echo ""

# ── Helper: submit a SLURM job ─────────────────────────────────────────────────
# Args: script_name [dependency_job_id]
# Returns: job ID (or "DRY_RUN" if --dry-run)
submit_job() {
    local SCRIPT="$1"
    local DEPENDS="${2:-}"
    local SCRIPT_PATH="${SCRIPTS}/${SCRIPT}"

    local CMD="sbatch --parsable"
    if [[ -n "${DEPENDS}" ]]; then
        CMD="${CMD} --dependency=afterok:${DEPENDS}"
    fi
    CMD="${CMD} ${SCRIPT_PATH}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "  [DRY RUN] Would submit: ${CMD}" >&2
        echo "DRY_RUN_${SCRIPT}"
        return
    fi

    local JOB_ID
    JOB_ID=$(eval "${CMD}")
    echo "${JOB_ID}"
}

log_job() {
    local SCRIPT="$1"
    local JOB_ID="$2"
    local DEPENDS="${3:-none}"
    echo "  Submitted ${SCRIPT} → Job ${JOB_ID} (depends on: ${DEPENDS})"
    echo "${TIMESTAMP} | ${SCRIPT} | job=${JOB_ID} | depends=${DEPENDS}" >> "${LOG}"
}

# ── CHAIN A: QC only (runs in parallel with the main chain) ───────────────────
# QC reads raw FASTQs and produces a report. Nothing downstream depends on it.
QC_JOB=""
if [[ "${FROM_STEP}" -le 1 ]]; then
    echo "── Chain A: QC (parallel, non-blocking) ──────────"
    QC_JOB=$(submit_job "01_qc.sh")
    log_job "01_qc.sh" "${QC_JOB}" "none"
    echo ""
fi

# ── CHAIN B: Main assembly chain ──────────────────────────────────────────────
echo "── Chain B: Assembly chain ───────────────────────"
PREV_JOB=""

if [[ "${FROM_STEP}" -le 2 ]]; then
    # Merge does NOT depend on QC — starts immediately
    MERGE_JOB=$(submit_job "02_merge.sh")
    log_job "02_merge.sh" "${MERGE_JOB}" "none"
    PREV_JOB="${MERGE_JOB}"
fi

if [[ "${FROM_STEP}" -le 3 ]]; then
    FILTER_JOB=$(submit_job "03_filter.sh" "${PREV_JOB}")
    log_job "03_filter.sh" "${FILTER_JOB}" "${PREV_JOB:-none}"
    PREV_JOB="${FILTER_JOB}"
fi

if [[ "${FROM_STEP}" -le 4 ]]; then
    ASSEMBLE_JOB=$(submit_job "04_assemble.sh" "${PREV_JOB}")
    log_job "04_assemble.sh" "${ASSEMBLE_JOB}" "${PREV_JOB:-none}"
    PREV_JOB="${ASSEMBLE_JOB}"
fi

if [[ "${FROM_STEP}" -le 5 ]]; then
    POLISH_JOB=$(submit_job "05_polish.sh" "${PREV_JOB}")
    log_job "05_polish.sh" "${POLISH_JOB}" "${PREV_JOB:-none}"
    PREV_JOB="${POLISH_JOB}"
fi

if [[ "${FROM_STEP}" -le 6 ]]; then
    PURGE_JOB=$(submit_job "06_purge.sh" "${PREV_JOB}")
    log_job "06_purge.sh" "${PURGE_JOB}" "${PREV_JOB:-none}"
    PREV_JOB="${PURGE_JOB}"
fi

if [[ "${FROM_STEP}" -le 7 ]]; then
    ASSESS_JOB=$(submit_job "07_assess.sh" "${PREV_JOB}")
    log_job "07_assess.sh" "${ASSESS_JOB}" "${PREV_JOB:-none}"
    PREV_JOB="${ASSESS_JOB}"
fi

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "=============================================="
echo "  All jobs submitted."
echo ""
echo "  Execution graph:"
echo "    01_qc ──────────────────────────── (parallel, reporting only)"
echo "    02_merge → 03_filter → 04_assemble → 05_polish → 06_purge → 07_assess"
echo ""
echo "  Monitor:"
echo "    squeue -u \$USER"
echo "    squeue -u \$USER -p euan"
echo "    tail -f ${LOGS}/04_assembly_<jobid>.out"
echo ""
echo "  Cancel all jobs from this run:"
if [[ "${DRY_RUN}" == "false" ]]; then
    ALL_JOBS=$(grep "${TIMESTAMP}" "${LOG}" | awk -F'job=' '{print $2}' | awk -F'|' '{print $1}' | tr '\n' ',' | sed 's/,$//')
    echo "    scancel ${ALL_JOBS}"
fi
echo ""
echo "  Job log: ${LOG}"
echo "=============================================="
