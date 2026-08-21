# Gray Whale (*Eschrichtius robustus*) — Sample Metadata
 
## Sequencing Summary
 
| Field | Value |
|-------|-------|
| Species | *Eschrichtius robustus* |
| Estimated genome size | ~2.4 Gb |
| Sequencing platform | Oxford Nanopore PromethION |
| Flow cell | R10.4.1 |
| Chemistry | E8.2, 400 bps |
| Basecaller | MinKNOW |
| Basecall model | dna_r10.4.1_e8.2_400bps_sup (v4.x) |
| Basecalling mode | SUP (super-accuracy) |
 
## Data Volume
 
| Metric | Value |
|--------|-------|
| Storage size | ~150 GB (.fastq.gz) |
| Actual bases (post-filter input) | ~171 Gb |
| Reads | ~49,992,597 |
| Run directories | 4 (2 individuals × 2 runs) |
 
## Coverage
 
| Metric | Value |
|--------|-------|
| Raw coverage | ~71x (from 171 Gb) |
| Effective after filtering | ~24x (over-filtered — see notes) |
 
## Data Paths (Sherlock Oak)
 
```
Base: /oak/stanford/groups/euan/projects/promethion_wet_lab/whale_data/Grey_Whale_Seq_LR/
 
Grey_Whale_1_LR:
  20260602_1325_2B_PBK95899_61c0d2c5/{fastq_pass,bam_pass}
  20260603_1420_3B_PAY42091_97df8277/{fastq_pass,bam_pass}
Grey_Whale_2_LR:
  20260602_1325_2D_PBK95362_4721b8ab/{fastq_pass,bam_pass}
  20260603_1420_3D_PAY41483_d4c102d6/{fastq_pass,bam_pass}
```
 
## Pipeline Settings Used
 
| Parameter | Value |
|-----------|-------|
| Medaka model | r1041_e82_400bps_sup_v4.3.0 |
| Flye read type | nano-hq |
| BUSCO lineage | cetartiodactyla_odb10 |
| Filtlong min_length | 5000 |
| Filtlong keep_percent | 40 |
| Target bases | 144 Gb |
 
## Assembly Results
 
| Metric | Value | Benchmark (Toren et al. 2025) |
|--------|-------|-------------------------------|
| Total length | 2.49 Gb | 2.4 Gb |
| Contigs | 7,042 | 2,689 |
| N50 | 1.6 Mb | 15 Mb |
| Largest contig | 7.9 Mb | — |
| Mean coverage | 24x | — |
| **BUSCO complete** | **98.3%** | 94.6% |
| BUSCO single-copy | 96.4% | — |
| BUSCO duplicated | 1.9% | — |
| BUSCO fragmented | 0.8% | — |
| BUSCO missing | 0.9% | — |
 
## Notes / Lessons Learned
 
- **Coverage estimate was wrong.** We assumed a compression factor of 3.2
  (GB storage → Gb bases), but the actual factor was ~1.14. This caused Filtlong
  to subsample far more aggressively than intended, dropping effective coverage
  from a possible ~60x down to ~24x.
- The lower coverage produced a more fragmented assembly (N50 1.6 Mb vs the
  15 Mb benchmark), though BUSCO completeness (98.3%) actually exceeded the benchmark.
- **For future whales:** use exact base counts from `sequencing_summary.txt`
  (column `sequence_length_template`) rather than estimating from storage size.
- Assembly is fully de novo — Medaka self-polished using the same ONT reads,
  no external reference. Matches methodology of McGrath et al. 2025.
