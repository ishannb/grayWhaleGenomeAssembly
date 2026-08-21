[Species Common Name] (Genus species) — Sample Metadata

Copy this file to <species>.md and fill in for each new assembly. Get exact base counts with: awk -F'\t' 'NR>1 {sum+=$15} END {printf "%.1f Gb, %d reads\n", sum/1e9, NR-1}' sequencing_summary.txt (column 15 = sequence_length_template; verify the column number for your files)

Sequencing Summary
Field	Value
Species	Genus species
Estimated genome size	~X.X Gb
Sequencing platform	Oxford Nanopore PromethION
Flow cell	FLO-PRO114M (R10.4.1)
Kit	SQK-LSK114
Chemistry	E8.2, 400 bps
Basecaller	(MinKNOW / Dorado + version)
Basecall model	dna_r10.4.1_e8.2_400bps_sup@vX.X.X
Basecalling mode	SUP
Data Volume
Library	Bases (Gb)	Reads	FASTQ files
lib_1			
lib_2			
Total			
Coverage
Metric	Value
Total bases	X Gb
Genome size	X.X Gb
Raw coverage	~Xx
Data Paths (Sherlock Oak)
Base: /oak/stanford/groups/euan/projects/promethion_wet_lab/whale_data/..._Seq_LR/
  (list each library's fastq_pass / basecalling/pass path)
Pipeline Settings
Parameter	Value
Medaka model	r1041_e82_400bps_sup_v4.3.0
Flye read type	nano-hq
BUSCO lineage	cetartiodactyla_odb10 (whales) / see below for shrew
Assembly Results

Fill in after pipeline completion.

Metric	Value
Total length	
Contigs	
N50	
Largest contig	
BUSCO complete	
Mean coverage
