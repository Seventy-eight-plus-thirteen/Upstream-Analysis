# ATAC-seq Parameter Templates

## fastp QC Parameters

### ATAC-seq Standard (CRITICAL: keep short fragments)
```bash
# Do NOT set --length_required to 30 (default)
# ATAC fragments can be as short as 30bp (nucleosome-free regions)
fastp -i <R1>.fastq.gz -I <R2>.fastq.gz \
  -o <R1>.clean.fq.gz -O <R2>.clean.fq.gz \
  --detect_adapter_for_pe \
  --length_required 15 \
  --thread 16 \
  --html <SAMPLE>_fastp.html \
  --json <SAMPLE>_fastp.json
```

### ATAC-seq with Quality Filtering (for lower quality data)
```bash
fastp -i <R1>.fastq.gz -I <R2>.fastq.gz \
  -o <R1>.clean.fq.gz -O <R2>.clean.fq.gz \
  --detect_adapter_for_pe \
  --length_required 15 \
  --qualified_quality_phred 20 \
  --thread 16 \
  --html <SAMPLE>_fastp.html \
  --json <SAMPLE>_fastp.json
```

### Trimmomatic Fallback (with Nextera adapters)
```bash
java -jar trimmomatic-0.39.jar PE \
  <R1>.fastq.gz <R2>.fastq.gz \
  <R1>_paired.fq.gz <R1>_unpaired.fq.gz \
  <R2>_paired.fq.gz <R2>_unpaired.fq.gz \
  ILLUMINACLIP:NexteraPE-PE.fa:2:30:10 \
  MINLEN:15 \
  SLIDINGWINDOW:4:20 \
  -threads 16
```

## Bowtie2 Alignment Parameters

### ATAC-seq (Extended fragment support)
```bash
# Key differences from ChIP-seq:
# -X 2000: allow fragments up to 2kb (ATAC can produce long fragments)
# --no-mixed --no-discordant: strict paired-end only
bowtie2 -x <INDEX> \
  -1 <R1>.clean.fq.gz -2 <R2>.clean.fq.gz \
  -p 16 \
  --very-sensitive \
  -X 2000 \
  --no-mixed \
  --no-discordant \
  -S <SAMPLE>.sam
```

## Mitochondrial Filtering Parameters

### Standard (chrM chromosome)
```bash
samtools view -@ 16 -b -v chrM <SAMPLE>.sorted.bam -o <SAMPLE>.nochrM.bam
samtools sort -@ 16 <SAMPLE>.nochrM.bam -o <SAMPLE>.nochrM.sorted.bam
samtools index <SAMPLE>.nochrM.sorted.bam
```

### With chrM variants (e.g., chrM_1, chrM_2)
```bash
samtools view -@ 16 -h <SAMPLE>.sorted.bam | \
  grep -v -E "chrM" | \
  samtools view -@ 16 -bS - -o <SAMPLE>.nochrM.bam
```

## Tn5 Offset Correction Parameters

### deepTools alignmentSieve (recommended)
```bash
alignmentSieve \
  -b <SAMPLE>.dedup.bam \
  --shift 4 -4 \
  -o <SAMPLE>.shifted.bam \
  -p 16 \
  --ATAC
```

### Manual shift (if alignmentSieve unavailable)
```bash
# Using bedtools: shift + strand reads +4, - strand reads -5
bedtools bamtobed -i <SAMPLE>.dedup.bam | \
  awk 'BEGIN{OFS="\t"} $6=="+" {$2=$2+4; $3=$3+4} $6=="-" {$2=$2-5; $3=$3-5} {print}' | \
  sort -k1,1 -k2,2n > <SAMPLE>.shifted.bed
```

## Deduplication Parameters

Same as ChIP-seq (samtools markdup). See `chip-seq/params.md`.

## Peak Calling Parameters

### MACS2 — ATAC mode (primary)
```bash
macs2 callpeak \
  -t <SAMPLE>.shifted.bam \
  -f BAMPE \
  --nomodel \
  --shift -75 \
  --extsize 150 \
  -g hs \
  -q 0.05 \
  -n <SAMPLE> \
  --outdir peaks/
```

### Genrich — ATAC mode (fallback, server has this)
```bash
# CRITICAL: Genrich requires queryname-sorted BAM
# ATAC mode is `-j` (NOT `--atacpair`, which does not exist in 0.6.2).
# `-q` (FDR q-value) must be within (0,1]; use 0.05, never 2.0.
# `-e` needs an argument (chromosomes to exclude) and will swallow `-v` if empty — omit it (mtDNA already removed upstream).
samtools sort -n -@ 16 <SAMPLE>.shifted.bam -o <SAMPLE>.shifted.qname.bam

Genrich \
  -t <SAMPLE>.shifted.qname.bam \
  -r -v -j \
  -q 0.05 \
  -o peaks/genrich_atac_peaks.narrowPeak
```

### Genrich — Multiple replicates
```bash
# Combine replicates of same condition
# Use comma-separated BAM files
Genrich \
  -t <REP1>.qname.bam,<REP2>.qname.bam,<REP3>.qname.bam \
  -r -v -j \
  -q 0.05 \
  -o peaks/genrich_atac_<CONDITION>_peaks.narrowPeak
```

## bigWig Generation (ATAC-seq)

### BPM normalized (single sample, no Input comparison)
```bash
# NOTE: newer deepTools removed `--normalizeUsing RPM`; use BPM (bins per million)
# which is the per-million-reads equivalent (counts per bin / total reads per million).
bamCoverage \
  -b <SAMPLE>.dedup.bam \
  -o <SAMPLE>_BPM.bw \
  --binSize 10 \
  --normalizeUsing BPM \
  --effectiveGenomeSize 2913022398 \
  --numberOfProcessors 16
```

### Note: No bigwigCompare log2 ratio (ATAC has no Input control)

## QC-Specific Parameters

### Fragment size distribution
```bash
samtools view <SAMPLE>.dedup.bam | \
  awk 'and($2,2)==0 {len=$9; if(len<0) len=-len; print len}' | \
  sort -n | \
  awk 'BEGIN{bin=0} {while($1>bin*10) bin++; count[bin]++} END{for(b=0;b<=500;b++) if(count[b]>0) print b*10, count[b]}' \
  > fragment_distribution.txt
```

### TSS enrichment
```bash
computeMatrix reference-point \
  -S <SAMPLE>_RPM.bw \
  -R <GENES_BED> \
  --referencePoint TSS \
  -a 1000 -b 1000 \
  --binSize 10 \
  --numberOfProcessors 16 \
  -o matrix_TSS_atac.gz

plotProfile \
  -m matrix_TSS_atac.gz \
  -out vis_tss_profile_atac.png \
  --dpi 150
```

## Effective Genome Size

| Species | Genome | Effective Size |
|---------|--------|----------------|
| Human | hg38/GRCh38 | 2,913,022,398 |
| Human | hg19/GRCh37 | 2,701,564,221 |
| Mouse | mm10/GRCm38 | 2,304,978,827 |

## ATAC-seq vs ChIP-seq Parameter Comparison

| Parameter | ChIP-seq | ATAC-seq | Why |
|-----------|----------|----------|-----|
| fastp --length_required | 30 | 15 | ATAC short fragments are valid |
| Bowtie2 -X | default (500) | 2000 | ATAC fragments up to 2kb |
| Bowtie2 --no-mixed | optional | yes | ATAC needs strict PE |
| chrM filtering | no | yes (mandatory) | Tn5 cuts mtDNA |
| Tn5 shift | no | +4/-4 | Tn5 9bp duplication |
| MACS2 --nomodel | optional | yes | ATAC isn't ChIP |
| MACS2 --shift/-extsize | not set | -75/150 | Capture NFR |
| Input control | required | not needed | ATAC is open chromatin |
| Dedup | mandatory | recommended | ATAC low dup is normal |
