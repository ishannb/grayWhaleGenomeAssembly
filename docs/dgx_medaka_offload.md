# Offloading Medaka Polishing to the DGX H100 Cluster

Step 5 (Medaka) is the only GPU-bound step in this pipeline, and Sherlock's
`gpu` partition is heavily contended — 418 GPU jobs were queued at one point
during the blue whale run, and the partition's only uncontended GPUs (in the
`euan` partition) are 12 GB TITAN Xp cards that are **too small for a mammalian
genome**. Offloading inference to a local DGX H100 removes that bottleneck.

Nothing else should move. Flye (step 4) is CPU-only — no long-read assembler
has a GPU path — so it stays on Sherlock's `bigmem`, which offers up to 256
cores and 4 TB per node. See [Why only Medaka](#why-only-medaka) below.

---

## Division of labour

| Stage | Where | Why |
|---|---|---|
| 3. Filter | Sherlock | CPU, and shrinks the data before anything moves |
| 4. Assemble (Flye) | Sherlock `bigmem` | CPU + high RAM; no GPU benefit |
| **5a. Align reads → BAM** | **Sherlock** | CPU-bound (minimap2); no GPU benefit |
| **5b. Medaka inference** | **DGX H100** | The only genuinely GPU-bound work |
| **5c. Stitch → consensus** | **DGX H100** | Cheap, but keeps the huge HDF from crossing the wire |
| 6–7. Purge, assess | Sherlock | CPU |

### Transfer the BAM, not the FASTQ

This is counterintuitive but measured: **the filtered FASTQ is larger than the
BAM it produces.**

| Sample | filtered_reads.fastq.gz | calls_to_draft.bam |
|---|---|---|
| Blue whale | 155.61 GB | **87.28 GB** |
| Gray whale | 53.84 GB | **49.43 GB** |

So aligning on Sherlock and shipping the BAM is both less network traffic and
less remote disk than shipping reads and aligning remotely. It also puts the
CPU work where CPU is free and the GPU work where GPUs are free.

---

## Sizing

Two scaling rules, derived from two independent completed runs (they agree to
within 1%):

```
calls_to_draft.bam    ~= 0.73 GB per Gb of filtered bases
consensus_probs.hdf   ~= 0.87 GB per Gb of filtered bases  (~1.21x the BAM)
```

The HDF is **larger than the BAM** — it is the per-base class-probability
tensor medaka writes during inference, and it is the single biggest file in the
run. Budgeting off the BAM alone will run you out of disk mid-inference.

Per-sample working set on the DGX (`BAM + draft + HDF + output`):

| Sample | Filtered | BAM | HDF | **Peak disk** |
|---|---|---|---|---|
| Blue whale | 120 Gb | 87 GB | 105 GB | **~197 GB** |
| Fin whale (est.) | ~156 Gb | 114 GB | 136 GB | **~256 GB** |
| Brady_MUS_4A (est.) | ~90 Gb | 66 GB | 78 GB | ~149 GB |
| Fin_mus_67A (est.) | ~65 Gb | 47 GB | 57 GB | ~109 GB |
| humpback_mus_01A (est.) | ~48 Gb | 35 GB | 42 GB | ~82 GB |
| Shrew (per sample, est.) | ~37 Gb | 27 GB | 32 GB | ~65 GB |

**Allocate ~1 TB, not 300 GB.** With 8 GPUs you can polish 8 samples at once,
but only if disk allows it — at 300 GB you can hold roughly one large sample and
would serialise eight ~90 GB round trips instead.

---

## How many GPUs

**One GPU per sample. Do not shard a single sample across 8.**

`medaka inference` is single-GPU by default; it logs `Model device: cuda:0` and
has no built-in data-parallel mode. Measured on one H100 SXM5 (80 GB), the main
inference pass over the blue whale genome (2,390 Mb) took **56 minutes**. Even
a perfect 8-way split would save under an hour — while the 90 GB transfer takes
considerably longer. GPU time is not the bottleneck.

The right way to use 8 GPUs is **8 samples in parallel**, one per GPU.

Resource envelope per concurrent sample, and what actually limits you:

| Resource | Available | Per sample | Concurrent limit |
|---|---|---|---|
| GPUs | 8 × H100 80 GB | 1 | **8** |
| GPU memory | 80 GB/card | ~13 GB @ `--batch_size 100` | not limiting |
| System RAM | 2 TB | ~160 GB peak | ~12 |
| Disk | 1.7 TB free | ~200 GB | **~8** |

All three converge around 8. GPU memory is not a constraint — 80 GB against a
~13 GB peak is ~6x headroom, so you can raise `--batch_size` to 400–600 to use
the hardware better. Medaka runs half precision by default, which suits H100
tensor cores.

If you ever do want to shard one sample, it is supported: `medaka inference
--regions <bed>` per GPU, then pass every HDF to `medaka sequence`, which
accepts multiple inputs positionally.

---

## ⚠️ The two-pass gotcha — read this before running

Medaka inference runs in **two passes**:

1. A **main batched pass** over most of the genome (`Processing N long region(s)
   with batching`) — works fine on GPU.
2. A **remainder pass** over deferred short regions (`Processing N short
   region(s)`) — **crashes on GPU.**

On blue whale the remainder pass aborted with:

```
RuntimeError: cuDNN error: CUDNN_STATUS_NOT_SUPPORTED.
```

This is a genuine cuDNN GRU kernel failure on degenerate short-region shapes,
**not** a memory or precision problem. It was reproduced identically at
`fp16/batch_size 100` and at `fp32/batch_size 50`, with peak RSS of only 4 GB.
The affected regions are dominated by very short contigs (on blue whale, 15,252
contigs had zero coverage in the main pass), and their pileups come back shorter
than requested.

**Expect this on the DGX too — it is a medaka/cuDNN interaction, not a Sherlock
problem.**

The fix is to run the remainder pass on CPU with `--cpu`, which bypasses cuDNN.
It is a small fraction of the genome (42.7 Mb of 2,433 Mb — 1.8% — on blue
whale) and takes well under an hour, so the lost GPU acceleration is irrelevant.

`scripts/05b_polish_resume.sh` automates exactly this recovery and is safe to
run against a crashed inference: it derives what is already in the HDF, computes
the complement, reprocesses only that on CPU, and stitches everything together.

---

## Procedure

### 1. Align on Sherlock (produces the BAM to ship)

Run step 5 normally on Sherlock but stop after alignment, or simply let
`05_polish.sh` run — it writes `calls_to_draft.bam` before inference and the BAM
survives a later crash. Alignment took ~9 h for blue whale.

Outputs, under `${OUTPUT_BASE_DIR}/04_polished/round_1/`:

```
calls_to_draft.bam        # the big one
calls_to_draft.bam.bai
```

### 2. Transfer to the DGX

Always use the DTN, never the login node. Pull from the DGX so the long-running
process lives there, and use `--partial` so a dropped 90 GB transfer resumes
rather than restarting.

```bash
mkdir -p ~/blue_whale && cd ~/blue_whale

rsync -avP --partial \
  ishannb@dtn.sherlock.stanford.edu:/scratch/groups/euan/blue_whale_assembly/04_polished/round_1/calls_to_draft.bam{,.bai} \
  ishannb@dtn.sherlock.stanford.edu:/scratch/groups/euan/blue_whale_assembly/03_assembly/assembly.fasta \
  .
```

Verify before spending GPU hours on a truncated file:

```bash
samtools quickcheck -v calls_to_draft.bam && echo "BAM OK"
```

**Measure your link first.** Time a 5 GB slice before committing: at 1 Gbps,
90 GB is ~20 h and the Sherlock queue may well beat it; at 10 Gbps it is ~2 h
and the DGX wins clearly.

### 3. Medaka on the DGX

Match **version 2.1.0** — that is what is validated here, including that the
`r1041_e82_400bps_sup_v5.2.0` model works against plain FASTQ-derived BAMs.

```bash
docker run --gpus all -v ~/blue_whale:/data -w /data \
  ontresearch/medaka:v2.1.0 medaka --version
# or: apptainer exec --nv docker://ontresearch/medaka:v2.1.0 medaka --version
```

Main pass, on **one** GPU:

```bash
medaka inference \
  calls_to_draft.bam \
  consensus_probs.hdf \
  --model r1041_e82_400bps_sup_v5.2.0 \
  --batch_size 400 \
  --threads 16 \
  --bam_workers 8
```

`--batch_size 400` rather than the default 100: peak was ~13 GB at 100, so 400
lands near ~50 GB — comfortably inside 80 GB. Watch `nvidia-smi` on the first
batches.

Expect it to end with `All done, N remainder regions` and then crash. That is
the known cuDNN issue. Recover the remainder on CPU:

```bash
medaka tools hdf_to_bed consensus_probs.hdf covered.bed
# subtract covered.bed from the draft .fai to get missing.bed
#   (scripts/05b_polish_resume.sh does this for you)

medaka inference \
  calls_to_draft.bam \
  consensus_probs_remainder.hdf \
  --regions missing.bed \
  --model r1041_e82_400bps_sup_v5.2.0 \
  --cpu --threads 32
```

### 4. Stitch — both HDFs, on the DGX

Do this remotely so the ~105 GB HDF never crosses the wire.

```bash
medaka sequence \
  consensus_probs.hdf consensus_probs_remainder.hdf \
  assembly.fasta \
  consensus.fasta \
  --threads 16
```

Unpolished regions are backfilled from the draft, so contig count and total
length always match the input.

### 5. Verify

```bash
ls -l consensus.fasta            # ~= draft size
grep -c '^>' consensus.fasta     # must equal the draft's contig count
```

### 6. Return it to the path the pipeline expects

`06_purge.sh` reads `04_polished/consensus.fasta`:

```bash
rsync -avP consensus.fasta \
  ishannb@dtn.sherlock.stanford.edu:/scratch/groups/euan/blue_whale_assembly/04_polished/consensus.fasta
```

Useful side effect: `05_polish.sh`'s guard checks that exact path, so any
still-queued Sherlock polish job will see it, skip, and exit 0 cleanly. Then:

```bash
bash scripts/run_pipeline.sh --config config/blue_whale.yaml --from 6
```

### 7. Reclaim space — only after verifying on Sherlock

```bash
rm calls_to_draft.bam calls_to_draft.bam.bai consensus_probs*.hdf
```

The HDFs are purely transient once stitched; nothing downstream reads them.

---

## Model selection

The medaka model must match the **basecalling** model, not the flow cell.
Check it per run before configuring:

```bash
# MinKNOW live basecalling
python3 -c "import json;print(json.load(open('report_*.json'))['acquisitions'][-1]['acquisition_run_info']['config_summary']['basecalling_model_version'])"
# Dorado post-hoc
grep -oE 'dna_r10[^\"]*' basecalling/sequencing_telemetry.js | head -1
```

| Run | Basecall model | Medaka model |
|---|---|---|
| Gray whale | MinKNOW SUP | `r1041_e82_400bps_sup_v4.3.0` |
| Blue whale | `..._sup@v5.2.0` (Dorado) | `r1041_e82_400bps_sup_v5.2.0` |
| Fin whale (June) | `..._sup@v5.2.0` (Dorado) | `r1041_e82_400bps_sup_v5.2.0` |
| Aug 2026 whale runs | `..._hac@v5.2.0` | `r1041_e82_400bps_hac_v5.2.0` |
| Shrew | `..._hac@v5.2.0` | `r1041_e82_400bps_hac_v5.2.0` |

**Trap:** `r1041_e82_400bps_sup_v5.2.0_rl_lstm384_no_dwells` *requires* dwell
information despite its name, and fails on plain FASTQ-derived BAMs. Use the
bare `r1041_e82_400bps_sup_v5.2.0`.

---

## Why only Medaka

Flye is CPU-only, as are Canu, hifiasm and Raven — there is no production GPU
de novo long-read assembler. Running assembly on a DGX leaves all 8 H100s idle.

Measured Flye profile (blue whale, 2.4 Gb draft): **312.7 GiB peak RAM**,
~37.7 h at 32 cores. On a DGX that caps concurrency at ~6 assemblies (2 TB /
313 GB), each then getting only ~18 cores — *slower per assembly* than Sherlock
at 32. Sherlock's `bigmem` has 824 cores across 11 nodes and up to 4 TB per
node, which is strictly more aggregate capacity.

Better levers for assembly speed, both on Sherlock:

- Request more cores. The current `04_assemble.sh` asks for 32; `bigmem` allows
  up to 256.
- Fix the walltime. `bigmem` caps at 1 day, which is why blue whale hit TIMEOUT
  and needed `--resume`. Peak RSS was 312.7 GiB — under the 384 GB `normal`
  floor — so it is worth testing whether `--qos=long` extends bigmem to 7 days.
