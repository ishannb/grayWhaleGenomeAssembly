# Blue Whale (*Balaenoptera musculus*) — Sample Metadata

## Sequencing Summary

| Field | Value |
|-------|-------|
| Species | *Balaenoptera musculus* |
| Estimated genome size | ~2.4 Gb |
| Sequencing platform | Oxford Nanopore PromethION |
| Flow cell | FLO-PRO114M (R10.4.1) |
| Kit | SQK-LSK114 |
| Chemistry | E8.2, 400 bps |
| Basecaller | Dorado (ont_basecall_client v7.13.6) |
| Basecall model | dna_r10.4.1_e8.2_400bps_sup@v5.2.0 |
| Modified bases | 5mCG_5hmCG@v2 (methylation called) |
| Basecalling mode | SUP (super-accuracy) |
| Min qscore filter | 10 |
| Basecalling hardware | NVIDIA A100 80GB PCIe |

## Data Volume

| Library | Bases (Gb) | Reads | FASTQ files |
|---------|-----------|-------|-------------|
| Blue_whale_lib_1 (PBM05572) | 96.8 | 32,456,119 | 7,611 |
| Blue_whaleLib_2 (PBK93830) | 92.7 | 30,968,955 | 7,066 |
| **Total** | **189.5** | **63,425,074** | **14,677** |

## Coverage

| Metric | Value |
|--------|-------|
| Total bases | 189.5 Gb |
| Genome size | 2.4 Gb |
| **Raw coverage** | **~79x** |
| Target after filtering | 60x (subsample to 144 Gb) |

## Data Paths (Sherlock Oak)

```
Base: /oak/stanford/groups/euan/projects/promethion_wet_lab/whale_data/Blue_Whale_Seq_LR/

Library 1 (PBM05572):
  Run:   Blue_whale_lib_1/20260609_1617_6D_PBM05572_1e7dd387/
  FASTQ: Blue_whale_lib_1/basecalling/pass/
  POD5:  Blue_whale_lib_1/20260609_1617_6D_PBM05572_1e7dd387/pod5/ (1.2 TB raw signal)

Library 2 (PBK93830):
  Run:   Blue_whaleLib_2/20260609_1617_6E_PBK93830_0d76690f/
  FASTQ: Blue_whaleLib_2/basecalling/pass/
  POD5:  Blue_whaleLib_2/20260609_1617_6E_PBK93830_0d76690f/pod5/ (1.1 TB raw signal)
```

## Pipeline Settings

| Parameter | Value | Notes |
|-----------|-------|-------|
| Medaka model | r1041_e82_400bps_sup_v4.3.0 | Closest available to basecall v5.2.0 |
| Flye read type | nano-hq | R10.4.1 / Q20+ SUP data |
| BUSCO lineage | cetartiodactyla_odb10 | Same as all baleen whales |
| Filtlong min_length | 5000 | High coverage, can be selective |
| Target coverage | 60x | Subsample from 79x |

## Notes

- Data was **not** basecalled live by MinKNOW (`basecalling_enabled=0` in run summary).
  Basecalling was performed post-hoc with Dorado on an A100 GPU, output in
  `basecalling/pass/` for each library.
- Methylation (5mCG/5hmCG) was called during basecalling and is stored in the BAM
  files — available for future epigenetic analysis.
- Coverage (~79x) is substantially better than the gray whale run (~24x effective),
  so a more contiguous assembly is expected.

## Assembly Results

_To be filled in after pipeline completion:_

| Metric | Value |
|--------|-------|
| Total length | TBD |
| Contigs | TBD |
| N50 | TBD |
| Largest contig | TBD |
| BUSCO complete | TBD |
| Mean coverage | TBD |
