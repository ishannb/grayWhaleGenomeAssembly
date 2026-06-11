# Gray Whale (*Eschrichtius robustus*) De Novo Genome Assembly

ONT long-read de novo assembly pipeline for ~200 Gb of gray whale PromethION data.
Designed for Stanford's Sherlock HPC cluster (Oak storage, euan partition).

**Sequencing:** R10.4.1 flow cell · SUP basecalling · MinKNOW  
**Expected genome size:** ~2.4 Gb · **Coverage:** ~83x raw, ~62x after filtering

---

## Repository Structure

```
gray-whale-genome/
├── config/
│   └── config.yaml          # All parameters — edit this, not the scripts
├── envs/
│   ├── qc.yml               # Conda env for QC tools
│   └── assembly.yml         # Conda env for assembly tools
├── scripts/
│   ├── parse_config.py      # Config parser used by all scripts
│   ├── 00_setup.sh          # One-time environment setup
│   ├── 01_qc.sh             # Read QC (NanoPlot)
│   ├── 02_merge.sh          # Merge reads from both run directories
│   ├── 03_filter.sh         # Read filtering (Filtlong)
│   ├── 04_assemble.sh       # De novo assembly (Flye)
│   ├── 05_polish.sh         # Consensus polishing (Medaka)
│   ├── 06_purge.sh          # Haplotig purging (purge_dups)
│   ├── 07_assess.sh         # Assembly QC (BUSCO + QUAST)
│   └── run_pipeline.sh      # Master submission script
└── logs/                    # SLURM logs and job ID records
```

---

## Reproducibility

All file paths, tool parameters, and SLURM resource requests live in
**`config/config.yaml`**. To adapt this pipeline to a different dataset or
cluster, only that file needs to be changed — no script internals need editing.

---

## Quick Start

### 1. Clone the repo on Sherlock

```bash
git clone https://github.com/ishannb/gray-whale-genome.git
cd gray-whale-genome
```

### 2. Load conda and run setup (once)

```bash
module load anaconda
bash scripts/00_setup.sh
```

### 3. Submit all jobs

```bash
bash scripts/run_pipeline.sh
```

Jobs are submitted with SLURM `afterok` dependencies — each step starts
automatically once the previous one succeeds.

### Resuming from a specific step

```bash
# Re-run from assembly onward (e.g. after changing Flye parameters)
bash scripts/run_pipeline.sh --from 4
```

### Monitor progress

```bash
squeue -u $USER
tail -f logs/04_assembly_<jobid>.out
```

---

## Pipeline Steps

| Step | Script | Tool | Purpose |
|------|--------|------|---------|
| 0 | `00_setup.sh` | conda | Create environments and directories |
| 1 | `01_qc.sh` | NanoPlot | Read quality assessment |
| 2 | `02_merge.sh` | cat / seqkit | Merge both run directories |
| 3 | `03_filter.sh` | Filtlong | Remove short/low-quality reads |
| 4 | `04_assemble.sh` | Flye | De novo genome assembly |
| 5 | `05_polish.sh` | Medaka | Consensus error correction |
| 6 | `06_purge.sh` | purge_dups | Remove haplotig duplicates |
| 7 | `07_assess.sh` | BUSCO + QUAST | Assembly completeness and stats |

---

## Input Data (Sherlock Paths)

All four run directories are listed in `config/config.yaml` and merged automatically.

```
Base: /oak/stanford/groups/euan/projects/promethion_wet_lab/whale_data/Grey_Whale_Seq_LR/

# Grey_Whale_1_LR — Run 1 (PBK95899)
Grey_Whale_1_LR/20260602_1325_2B_PBK95899_61c0d2c5/fastq_pass
Grey_Whale_1_LR/20260602_1325_2B_PBK95899_61c0d2c5/bam_pass

# Grey_Whale_1_LR — Run 2 (PAY42091)
Grey_Whale_1_LR/20260603_1420_3B_PAY42091_97df8277/fastq_pass
Grey_Whale_1_LR/20260603_1420_3B_PAY42091_97df8277/bam_pass

# Grey_Whale_2_LR — Run 3 (PBK95362)
Grey_Whale_2_LR/20260602_1325_2D_PBK95362_4721b8ab/fastq_pass
Grey_Whale_2_LR/20260602_1325_2D_PBK95362_4721b8ab/bam_pass

# Grey_Whale_2_LR — Run 4 (PAY41483)
Grey_Whale_2_LR/20260603_1420_3D_PAY41483_d4c102d6/fastq_pass
Grey_Whale_2_LR/20260603_1420_3D_PAY41483_d4c102d6/bam_pass
```

---

## Software Versions

| Tool | Version | Purpose |
|------|---------|---------|
| Flye | 2.9.4 | De novo assembly |
| Medaka | 2.0.1 | ONT polishing (model: r1041_e82_400bps_sup_v5.0.0) |
| purge_dups | 1.2.6 | Haplotig removal |
| NanoPlot | 1.42.0 | Read QC |
| Filtlong | 0.2.1 | Read filtering |
| BUSCO | 5.7.1 | Assembly completeness |
| QUAST | 5.2.0 | Assembly statistics |
| minimap2 | 2.28 | Read alignment (Medaka + purge_dups) |
| samtools | 1.19 | BAM handling |
| seqkit | 2.7.0 | FASTQ stats |

---

## Expected Outputs

| Metric | Expected | Benchmark (Toren et al. 2025) |
|--------|----------|-------------------------------|
| Assembly size | ~2.4 Gb | 2.4 Gb |
| Contig N50 | >10 Mb | 15 Mb |
| BUSCO completeness | >90% | 94.6% (cetartiodactyla_odb10) |

---

## References

**Gray whale genome:**
1. Toren D, et al. (2025). An improved gray whale assembly highlights how allospecific reference-genome choice can affect genomic diversity estimates. *bioRxiv*. doi:10.1101/2025.01.23.634050
2. Moskalev EA, et al. (2017). De novo assembling and primary analysis of genome and transcriptome of gray whale *Eschrichtius robustus*. *BMC Ecology and Evolution*, 17, 258.

**Closest methodological analog (cetacean ONT assembly):**
3. McGrath N, et al. (2025). A high-quality Oxford Nanopore assembly of the hourglass dolphin (*Lagenorhynchus cruciger*) genome. *G3: Genes, Genomes, Genetics*, 15(5), jkaf044.

**Assembly:**
4. Kolmogorov M, Yuan J, Lin Y, Pevzner PA (2019). Assembly of long, error-prone reads using repeat graphs. *Nature Biotechnology*, 37, 540-546.

**Polishing:**
5. Oxford Nanopore Technologies (2024). Medaka v2.0. github.com/nanoporetech/medaka

**Haplotig purging:**
6. Guan D, et al. (2020). Identifying and removing haplotypic duplication in primary genome assemblies. *Bioinformatics*, 36(9), 2896-2898.

**Read QC:**
7. De Coster W, Rademakers R (2023). NanoPack2: population-scale evaluation of long-read sequencing data. *Bioinformatics*, 39(5), btad311.

**Assembly assessment:**
8. Simao FA, et al. (2015). BUSCO: assessing genome assembly and annotation completeness with single-copy orthologs. *Bioinformatics*, 31(19), 3210-3212.
9. Gurevich A, et al. (2013). QUAST: quality assessment tool for genome assemblies. *Bioinformatics*, 29(8), 1072-1075.
