# ChIP-seq Parameter Templates

## fastp QC Parameters

### Standard Paired-End
```bash
fastp -i <R1>.fastq.gz -I <R2>.fastq.gz \
  -o <R1>.clean.fq.gz -O <R2>.clean.fq.gz \
  --detect_adapter_for_pe \
  --thread 16 \
  --html <SAMPLE>_fastp.html \
  --json <SAMPLE>_fastp.json
```

### With Quality Filtering (for low quality data)
```bash
fastp -i <R1>.fastq.gz -I <R2>.fastq.gz \
  -o <R1>.clean.fq.gz -O <R2>.clean.fq.gz \
  --detect_adapter_for_pe \
  --qualified_quality_phred 20 \
  --length_required 30 \
  --thread 16 \
  --html <SAMPLE>_fastp.html \
  --json <SAMPLE>_fastp.json
```

## Bowtie2 Alignment Parameters

### Transcription Factor (Sensitive Mode)
```bash
bowtie2 -x <INDEX> \
  -1 <R1>.clean.fq.gz -2 <R2>.clean.fq.gz \
  -p 16 \
  --very-sensitive \
  --no-mixed \
  --no-discordant \
  -S <SAMPLE>.sam
```

### Histone Mark (Default)
```bash
bowtie2 -x <INDEX> \
  -1 <R1>.clean.fq.gz -2 <R2>.clean.fq.gz \
  -p 16 \
  --very-sensitive \
  -S <SAMPLE>.sam
```

### Single-End
```bash
bowtie2 -x <INDEX> \
  -U <R1>.clean.fq.gz \
  -p 16 --very-sensitive \
  -S <SAMPLE>.sam
```

## samtools Dedup Parameters

### Standard Pipeline (Paired-End)
```bash
samtools sort -n -@ 16 <INPUT>.bam -o <INPUT>.qname.bam
samtools fixmate -m -@ 16 <INPUT>.qname.bam <INPUT>.fixmate.bam
samtools sort -@ 16 <INPUT>.fixmate.bam -o <INPUT>.fixed.bam
samtools markdup -r -@ 16 <INPUT>.fixed.bam <INPUT>.dedup.bam
samtools index <INPUT>.dedup.bam
```

## Peak Calling Parameters

### MACS2 — Transcription Factor (Narrow Peaks)
```bash
macs2 callpeak \
  -t <CHIP>.dedup.bam \
  -c <INPUT>.dedup.bam \
  -f BAMPE \
  -g hs \
  -q 0.01 \
  --nomodel \
  --extsize 150 \
  -n <CHIP> \
  --outdir peaks/
```

### MACS2 — Histone Mark (Broad Peaks)
```bash
macs2 callpeak \
  -t <CHIP>.dedup.bam \
  -c <INPUT>.dedup.bam \
  -f BAMPE \
  -g hs \
  --broad \
  --broad-cutoff 0.1 \
  -n <CHIP> \
  --outdir peaks/
```

### Genrich — Fallback (TF, Narrow Peaks)
```bash
# Requires queryname-sorted BAM
samtools sort -n -@ 16 <CHIP>.dedup.bam -o <CHIP>.qname.bam
samtools sort -n -@ 16 <INPUT>.dedup.bam -o <INPUT>.qname.bam

Genrich \
  -t <CHIP>.qname.bam \
  -c <INPUT>.qname.bam \
  -r -v \
  -q 0.05 \
  -o peaks/genrich_peaks.narrowPeak
```

### Genrich — Histone Mark (Broad Peaks)
```bash
Genrich \
  -t <CHIP>.qname.bam \
  -c <INPUT>.qname.bam \
  -r -e -v \
  -q 1.0 \
  --broad \
  -o peaks/genrich_peaks.broadPeak
```

## SEACR — Last Resort Fallback

### SEACR (uses bigWig, not BAM)
```bash
# First generate bigWig from BAM
bamCoverage -b <CHIP>.dedup.bam -o <CHIP>.bw --binSize 10 --normalizeUsing RPM
bamCoverage -b <INPUT>.dedup.bam -o <INPUT>.bw --binSize 10 --normalizeUsing RPM

# SEACR call peaks
SEACR_1.3.sh <CHIP>.bw <INPUT>.bw \
  peaks/seacr_peaks.bed \
  norm stringent \
  <CHROM_SIZES_FILE>
```

## Effective Genome Size Reference

| Species | Genome | Effective Size |
|---------|--------|----------------|
| Human | hg38/GRCh38 | 2,913,022,398 |
| Human | hg19/GRCh37 | 2,701,564,221 |
| Mouse | mm10/GRCm38 | 2,304,978,827 |
| Mouse | mm39/GRCm39 | 2,455,993,370 |

Use `-g <value>` for MACS2 or `--effectiveGenomeSize <value>` for deepTools.

## Threads/Cores

- Always check available cores: `nproc`
- Default: use 50-75% of available cores
- `bowtie2 -p 16`, `samtools -@ 16`, `fastp --thread 16`
- For 72-core servers: use 16-32 cores for most tasks
