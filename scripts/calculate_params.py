#!/usr/bin/env python3
"""
calculate_params.py — Estimates coverage and computes filtering parameters.

Reads config.yaml and estimates gigabases of sequence from the on-disk
storage size of the .fastq.gz files, using a compression factor.

WHY ESTIMATE RATHER THAN COUNT EXACTLY:
  Counting exact gigabases requires decompressing and reading every FASTQ
  file, which takes hours on 150+ GB datasets. Instead, we use:

    gigabases ≈ fastq_storage_gb × fastq_compression_factor

  For ONT SUP .fastq.gz, the compression factor is typically 3.0-3.5x
  (the FASTQ format stores 4 lines per read including headers and quality
  scores, which compress very well with gzip). A factor of 3.2 is a
  conservative midpoint that errs slightly toward underestimating coverage,
  which is the safer direction (we keep more data, not less).

  If you have a seqkit stats result from a previous run, you can compute
  the exact factor and set it in config.yaml:
    fastq_compression_factor = (total_bases / 1e9) / fastq_storage_gb

FILTERING STRATEGY BY COVERAGE:
  >80x  → subsample to 60x, min_length 5000 bp
  40-80x → subsample to 50x if >60x, min_length 3000 bp
  <40x  → keep everything, min_length 1000 bp, warn user

Usage:
    python3 scripts/calculate_params.py config/config.yaml --summary
    python3 scripts/calculate_params.py config/config.yaml --export
"""

import sys
import yaml
import argparse
import math
import os


# ── Coverage thresholds ────────────────────────────────────────────────────────
HIGH_COV_THRESHOLD = 80
MED_COV_THRESHOLD  = 40
TARGET_HIGH_COV    = 60
TARGET_MED_COV     = 50
FLYE_MIN_COV       = 40


def estimate_gigabases(config):
    """
    Estimate total gigabases from storage size and compression factor.
    Returns (estimated_gb, method_description).
    """
    sample = config['sample']

    storage_gb = float(sample['fastq_storage_gb'])
    factor     = float(sample.get('fastq_compression_factor', 3.2))
    estimated  = storage_gb * factor

    method = (
        f"{storage_gb:.0f} GB storage × {factor} compression factor "
        f"= {estimated:.0f} Gb estimated"
    )
    return estimated, method


def calculate(config):
    """
    Compute filtlong parameters based on estimated coverage.
    Returns a dict of parameters and metadata.
    """
    total_gb, estimation_method = estimate_gigabases(config)
    genome_gb    = float(config['genome']['estimated_size_gb'])
    raw_coverage = total_gb / genome_gb

    # ── Manual override ────────────────────────────────────────────────────────
    filtlong_cfg = config.get('filtlong', {})
    if filtlong_cfg.get('override', False):
        return {
            'mode':               'manual override',
            'estimation_method':  estimation_method,
            'estimated_bases_gb': total_gb,
            'raw_coverage':       raw_coverage,
            'min_length':         filtlong_cfg.get('min_length', 1000),
            'keep_percent':       filtlong_cfg.get('keep_percent', 100),
            'target_bases':       str(filtlong_cfg.get('target_bases', '')),
            'effective_cov':      raw_coverage,
            'warnings':           [],
        }

    warnings = []
    target_bases = ''

    # ── HIGH coverage ──────────────────────────────────────────────────────────
    if raw_coverage > HIGH_COV_THRESHOLD:
        min_length   = 5000
        target_bytes = int(TARGET_HIGH_COV * genome_gb * 1e9)
        target_bases = str(target_bytes)
        keep_percent = min(100, math.ceil((TARGET_HIGH_COV / raw_coverage) * 100) + 10)
        effective_cov = TARGET_HIGH_COV
        mode = (f"high coverage ({raw_coverage:.0f}x) — "
                f"subsampling to {TARGET_HIGH_COV}x")

    # ── MEDIUM coverage ────────────────────────────────────────────────────────
    elif raw_coverage > MED_COV_THRESHOLD:
        min_length = 3000
        if raw_coverage > TARGET_MED_COV:
            target_bytes = int(TARGET_MED_COV * genome_gb * 1e9)
            target_bases = str(target_bytes)
            keep_percent = min(100, math.ceil((TARGET_MED_COV / raw_coverage) * 100) + 10)
            effective_cov = TARGET_MED_COV
            mode = (f"medium coverage ({raw_coverage:.0f}x) — "
                    f"subsampling to {TARGET_MED_COV}x")
        else:
            keep_percent  = 100
            target_bases  = ''
            effective_cov = raw_coverage * 0.95
            mode = (f"medium coverage ({raw_coverage:.0f}x) — "
                    f"keeping all reads")

    # ── LOW coverage ───────────────────────────────────────────────────────────
    else:
        min_length    = 1000
        keep_percent  = 100
        target_bases  = ''
        effective_cov = raw_coverage * 0.98
        mode = (f"low coverage ({raw_coverage:.0f}x) — "
                f"keeping all reads")
        if raw_coverage < FLYE_MIN_COV:
            warnings.append(
                f"Raw coverage estimate is {raw_coverage:.1f}x, below the "
                f"recommended minimum of {FLYE_MIN_COV}x for Flye. Assembly "
                f"quality may be reduced. Consider sequencing more data, or "
                f"adjust fastq_compression_factor in config.yaml if your "
                f"estimate seems off."
            )

    # ── Coverage uncertainty note ──────────────────────────────────────────────
    # Coverage is estimated; flag if it's close to a threshold boundary
    factor = float(config['sample'].get('fastq_compression_factor', 3.2))
    low_estimate  = (float(config['sample']['fastq_storage_gb']) * (factor - 0.4)) / genome_gb
    high_estimate = (float(config['sample']['fastq_storage_gb']) * (factor + 0.4)) / genome_gb
    if (low_estimate < HIGH_COV_THRESHOLD < high_estimate or
        low_estimate < MED_COV_THRESHOLD  < high_estimate):
        warnings.append(
            f"Coverage estimate ({raw_coverage:.0f}x) is near a strategy "
            f"threshold. Plausible range given compression uncertainty: "
            f"{low_estimate:.0f}x–{high_estimate:.0f}x. "
            f"If you want to verify, run: seqkit stats -a <one_fastq_file> "
            f"and update fastq_compression_factor in config.yaml."
        )

    return {
        'mode':               mode,
        'estimation_method':  estimation_method,
        'estimated_bases_gb': total_gb,
        'raw_coverage':       raw_coverage,
        'min_length':         min_length,
        'keep_percent':       keep_percent,
        'target_bases':       target_bases,
        'effective_cov':      effective_cov,
        'warnings':           warnings,
    }


def print_summary(config, params):
    sample = config['sample']
    genome = config['genome']
    seq    = config['sequencing']
    medaka = config['medaka']

    print("=" * 60)
    print("  Assembly Parameter Summary")
    print("=" * 60)
    print(f"  Sample:            {sample['name']} ({sample['species']})")
    print(f"  Flow cell:         {seq['flow_cell']} / {seq['calling_mode']}")
    print(f"  Medaka model:      {medaka['model']}")
    print()
    print(f"  Coverage estimate:")
    print(f"    {params['estimation_method']}")
    print(f"    Genome size:     {genome['estimated_size_gb']} Gb")
    print(f"    Raw coverage:    ~{params['raw_coverage']:.0f}x")
    print(f"    (Note: coverage is estimated from storage size, not exact)")
    print()
    print(f"  Strategy:          {params['mode']}")
    print()
    print(f"  Filtlong settings (computed):")
    print(f"    min_length:      {params['min_length']} bp")
    print(f"    keep_percent:    {params['keep_percent']}%")
    tb = params['target_bases']
    if tb:
        print(f"    target_bases:    {int(tb):,} bp  "
              f"({int(tb)/1e9:.0f} Gb, ~{params['effective_cov']:.0f}x)")
    else:
        print(f"    target_bases:    disabled (keep all reads)")
    print()
    for w in params['warnings']:
        print(f"  ⚠  {w}")
        print()
    print("=" * 60)


def print_exports(params):
    print(f"export COMPUTED_MIN_LENGTH=\"{params['min_length']}\"")
    print(f"export COMPUTED_KEEP_PERCENT=\"{params['keep_percent']}\"")
    print(f"export COMPUTED_TARGET_BASES=\"{params['target_bases']}\"")
    print(f"export COMPUTED_RAW_COVERAGE=\"{params['raw_coverage']:.1f}\"")
    print(f"export COMPUTED_EFF_COVERAGE=\"{params['effective_cov']:.1f}\"")
    if params['warnings']:
        joined = ' | '.join(params['warnings'])
        print(f"export COMPUTED_WARNINGS=\"{joined}\"")
    else:
        print(f"export COMPUTED_WARNINGS=\"\"")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('config', help='Path to config.yaml')
    parser.add_argument('--summary', action='store_true')
    parser.add_argument('--export',  action='store_true')
    args = parser.parse_args()

    with open(args.config) as f:
        config = yaml.safe_load(f)

    params = calculate(config)

    if args.summary:
        print_summary(config, params)
    if args.export:
        print_exports(params)
    if not args.summary and not args.export:
        print_summary(config, params)
        print()
        print_exports(params)


if __name__ == '__main__':
    main()
