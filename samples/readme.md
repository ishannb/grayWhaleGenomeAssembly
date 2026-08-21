# Sample Metadata
 
One file per assembled sample. Each documents the input sequencing data,
coverage, exact paths, pipeline settings, and final assembly results — so every
assembly is reproducible and citable.
 
## Samples
 
| Sample | Species | Genome | Coverage | Status |
|--------|---------|--------|----------|--------|
| [gray_whale.md](gray_whale.md) | *Eschrichtius robustus* | ~2.4 Gb | ~24x eff. | ✅ Complete (98.3% BUSCO) |
| [blue_whale.md](blue_whale.md) | *Balaenoptera musculus* | ~2.4 Gb | ~79x | ⏳ Queued |
| fin_whale.md | *Balaenoptera physalus* | ~2.6 Gb | TBD | ⏳ Planned |
| shrew.md | TBD | TBD | TBD | ⏳ Planned |
 
## Adding a new sample
 
1. Copy `TEMPLATE.md` to `<species>.md`
2. Get exact base counts from the ONT `sequencing_summary.txt`:
```bash
   awk -F'\t' 'NR>1 {sum+=$15} END {printf "%.1f Gb, %d reads\n", sum/1e9, NR-1}' \
       sequencing_summary.txt
```
3. Get the basecall model from a BAM header:
```bash
   samtools view -H one_file.bam | grep -i "basecall_model"
```
4. Fill in the table, create the matching `config/<species>.yaml`, and run the pipeline.
5. After completion, fill in the Assembly Results section.
## Note on the shrew
 
The shrew is not a cetacean, so it needs a **different BUSCO lineage** —
likely `eulipotyphla_odb10` or `mammalia_odb10` instead of
`cetartiodactyla_odb10`. Genome size and Flye settings will also differ.
 
