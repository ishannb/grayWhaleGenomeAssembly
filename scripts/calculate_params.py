#!/usr/bin/env python3
"""
calculate_params.py — Estimates coverage and computes filtering parameters.

Two ways to determine total sequenced bases (in priority order):

1. EXACT (preferred) — set sample.total_bases_gb in the config.
   Get it from the ONT sequencing_summary.txt:
     awk -F'\\t' 'NR>1 {sum+=$15} END {printf "%.1f\\n", sum/1e9}' sequencing_summary.txt
   (column 15 = sequence_length_template; verify for your files)

2. ESTIMATE (fallback) — if total_bases_gb is 0 or missing, estimate from
   storage size:  gigabases ≈ fastq_storage_gb × fastq_compression_factor
   ONT SUP .fastq.gz compresses at roughly 1.1–1.5x (observed 1.14 for gray whale).

FILTERING STRATEGY BY COVERAGE:
  >80x  → subsample to 60x, min_length 5000 bp
  40-80x → subsample to 50x if >60x, min_length 3000 bp
  <40x  → keep everything, min_length 1000 bp, warn user

Usage:
    python3 scripts/calculate_params.py config/blue_whale.yaml --summary
    python3 scripts/calculate_params.py config/blue_whale.yaml --export
"""

import sys
import yaml
import argparse
import math


HIGH_COV_THRESHOLD = 80
MED_COV_THRESHOLD  = 40
TARGET_HIGH_COV    = 60
TARGET_MED_COV     = 50
FLYE_MIN_COV       = 40


def estimate_gigabases(config):
    """
    Return (estimated_gb, method_description).
    Uses exact total_bases_gb if provided (>0), else storage×factor estimate.
    """
    sample = config['sample']

    # Priority 1: exact base count
    total_bases_gb = float(sample.get('total_bases_gb', 0) or 0)
    if total_bases_gb > 0:
        method = f"{total_bases_gb:.1f} Gb (exact, from sequencing_summary.txt)"
        return total_bases_gb, method

    # Priority 2: storage estimate
    storage_gb = float(sample.get('fastq_storage_gb', 0) or 0)
    factor     = float(sample.get('fastq_compression_factor', 1.14))
    estimated  = storage_gb * factor
    method = (f"{storage_gb:.0f} GB storage × {factor} compression factor "
              f"= {estimated:.0f} Gb estimated")
    return estimated, method


def calculate(config):
    total_gb, estimation_method = estimate_gigabases(config)
    genome_gb    = float(config['genome']['estimated_size_gb'])
    raw_coverage = total_gb / genome_gb

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

    if raw_coverage > HIGH_COV_THRESHOLD:
        min_length   = 5000
        target_bytes = int(TARGET_HIGH_COV * genome_gb * 1e9)
        target_bases = str(target_bytes)
        keep_percent = min(100, math.ceil((TARGET_HIGH_COV / raw_coverage) * 100) + 10)
        effective_cov = TARGET_HIGH_COV
        mode = f"high coverage ({raw_coverage:.0f}x) — subsampling to {TARGET_HIGH_COV}x"

    elif raw_coverage > MED_COV_THRESHOLD:
        min_length = 3000
        if raw_coverage > TARGET_MED_COV:
            target_bytes = int(TARGET_MED_COV * genome_gb * 1e9)
            target_bases = str(target_bytes)
            keep_percent = min(100, math.ceil((TARGET_MED_COV / raw_coverage) * 100) + 10)
            effective_cov = TARGET_MED_COV
            mode = f"medium coverage ({raw_coverage:.0f}x) — subsampling to {TARGET_MED_COV}x"
        else:
            keep_percent  = 100
            target_bases  = ''
            effective_cov = raw_coverage * 0.95
            mode = f"medium coverage ({raw_coverage:.0f}x) — keeping all reads"

    else:
        min_length    = 1000
        keep_percent  = 100
        target_bases  = ''
        effective_cov = raw_coverage * 0.98
        mode = f"low coverage ({raw_coverage:.0f}x) — keeping all reads"
        if raw_coverage < FLYE_MIN_COV:
            warnings.append(
                f"Raw coverage {raw_coverage:.1f}x is below the recommended "
                f"minimum of {FLYE_MIN_COV}x for Flye. Assembly quality may be "
                f"reduced. Consider sequencing more data."
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
    print(f"  Coverage:")
    print(f"    {params['estimation_method']}")
    print(f"    Genome size:     {genome['estimated_size_gb']} Gb")
    print(f"    Raw coverage:    ~{params['raw_coverage']:.0f}x")
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
        print(f"  !  {w}")
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
    parser.add_argument('config', help='Path to config yaml')
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
