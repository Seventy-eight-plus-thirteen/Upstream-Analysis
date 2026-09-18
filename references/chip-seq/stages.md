# ChIP-seq Stage Tree & Verification Points

## Pipeline Overview

```
1. Download      →  2. Convert  →  3. QC/Trim  →  4. Align  →  5. Dedup  →  6. Peak Call  →  7. Annotate  →  8. Visualize
```

## Stage Details

### Stage 1: Data Download

**Primary**: Aspera (port 33001)
**Fallback**: ENA Aspera → prefetch (HTTPS) → kingfisher

**Command (prefetch)**:
```bash
prefetch -p <SRR> -o <SRR>.sra
```

**Verification**:
- [ ] File size matches GEO metadata
- [ ] `vdb-validate <SRR>.sra` passes
- [ ] Run in background with nohup for files >2GB

**On failure**: See `common/download-strategy.md`

---

### Stage 2: Format Conversion

**Primary**: fasterq-dump + pigz
**Fallback**: fastq-dump (slower, single-threaded)

```bash
fasterq-dump <SRR>.sra -p -e 16 --split-files
pigz -p 16 <SRR>_*.fastq
```

**Verification**:
- [ ] Paired-end: `<SRR>_1.fastq.gz` and `<SRR>_2.fastq.gz` both exist
- [ ] File sizes > 0
- [ ] Quick read count: `zcat <SRR>_1.fastq.gz | wc -l` (should be 4x read count)

---

### Stage 3: QC & Adapter Trimming

**Primary**: fastp (all-in-one)
**Fallback**: FastQC + Trimmomatic

```bash
fastp -i <SRR>_1.fastq.gz -I <SRR>_2.fastq.gz \
  -o <SRR>_1.clean.fq.gz -O <SRR>_2.clean.fq.gz \
  --html <SRR>_fastp.html --json <SRR>_fastp.json \
  --detect_adapter_for_pe --thread 16
```

**CRITICAL Verification**:
- [ ] R1 and R2 read counts MUST be identical
- [ ] Check fastp JSON: `python3 -c "import json; d=json.load(open('<SRR>_fastp.json')); print('R1:', d['summary']['before_filtering']['total_reads'], 'R2:', d['summary']['before_filtering']['total_reads'])"`
- [ ] If R1 != R2: STOP, re-download SRA

**User interaction point**: Confirm if fastp report is sufficient (skip FastQC?)

---

### Stage 4: Alignment

**Primary**: Bowtie2 (ChIP/ATAC)
**Fallback**: BWA-mem → STAR (RNA-seq)

```bash
bowtie2 -x <GENOME_INDEX> \
  -1 <SRR>_1.clean.fq.gz -2 <SRR>_2.clean.fq.gz \
  -p 16 --very-sensitive \
  -S <SRR>.sam 2> <SRR>_bowtie2.log

# Convert to BAM
samtools view -@ 16 -bS <SRR>.sam -o <SRR>.bam
samtools sort -@ 16 <SRR>.bam -o <SRR>.sorted.bam
samtools index <SRR>.sorted.bam
```

**Verification**:
- [ ] Alignment rate > 80% (check bowtie2 log)
- [ ] `samtools flagstat <SRR>.sorted.bam` — report total reads, mapped reads
- [ ] BAM file size reasonable (~5-8GB per 100M reads)

**On low alignment rate**: Check reference genome, adapter contamination, read quality

---

### Stage 5: Deduplication

**Primary**: samtools markdup
**Fallback**: Picard MarkDuplicates

```bash
# samtools markdup requires: sort by name -> fixmate -> sort by coord -> markdup
samtools sort -n -@ 16 <SRR>.sorted.bam -o <SRR>.qname.bam
samtools fixmate -m -@ 16 <SRR>.qname.bam <SRR>.fixmate.bam
samtools sort -@ 16 <SRR>.fixmate.bam -o <SRR>.fixed.bam
samtools markdup -r -@ 16 <SRR>.fixed.bam <SRR>.dedup.bam
samtools index <SRR>.dedup.bam
```

**Verification**:
- [ ] `samtools flagstat <SRR>.dedup.bam` — duplicates should be 0 (removed by -r)
- [ ] Dedup rate = (raw - dedup) / raw; should be < 30%
- [ ] If > 50% duplication: warn user (possible PCR over-amplification)

**Report to user**: Total reads, deduped reads, duplication rate

---

### Stage 6: Peak Calling

**Primary**: MACS2
**Fallback**: Genrich → SEACR

#### MACS2 (Transcription Factor)
```bash
macs2 callpeak \
  -t <CHIP>.dedup.bam \
  -c <INPUT>.dedup.bam \
  -f BAMPE \
  -g hs \
  -n <CHIP> \
  --outdir peaks/ \
  -q 0.01
```

#### MACS2 (Histone Mark)
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

#### Genrich (Fallback)
```bash
# CRITICAL: Genrich requires queryname-sorted BAM
samtools sort -n -@ 16 <CHIP>.dedup.bam -o <CHIP>.qname.bam
samtools sort -n -@ 16 <INPUT>.dedup.bam -o <INPUT>.qname.bam

Genrich -t <CHIP>.qname.bam -c <INPUT>.qname.bam \
  -r -e -v \
  -q 2.0 \
  -o peaks/genrich_peaks.narrowPeak
```

**Verification**:
- [ ] Peak count in reasonable range:
  - TF: 50 - 10,000 peaks
  - Histone: 1,000 - 50,000 peaks
- [ ] If < 10 peaks: threshold too stringent or data quality issue
- [ ] If > 50,000 peaks: Input control may not be working

**User interaction point**: Report peak count, ask to adjust threshold if needed

---

### Stage 7: Annotation & Enrichment

```R
# ChIPseeker annotation
library(ChIPseeker)
library(TxDb.Hsapiens.UCSC.hg38.knownGene)
peaks <- readPeakFile('peaks/genrich_peaks.narrowPeak')
peakAnno <- annotatePeak(peaks, TxDb=TxDb.Hsapiens.UCSC.hg38.knownGene)
write.csv(as.data.frame(peakAnno), 'peak_gene_annotation.csv')

# GO enrichment
library(clusterProfiler)
library(org.Hs.eg.db)
genes <- unique(peakAnno@anno$geneId)
ego <- enrichGO(gene=genes, OrgDb=org.Hs.eg.db, pAdjustMethod='BH')
write.csv(as.data.frame(ego), 'go_enrichment_results.csv')
```

**Verification**:
- [ ] Most peaks annotated to genomic features
- [ ] GO terms relevant to the biological system

---

### Stage 8: Visualization

See `chip-seq/visualization.md` for full details.

**Outputs to generate**:
1. Chromosome distribution plot
2. Peak width distribution
3. Peak annotation pie/bar chart
4. GO enrichment dot plot
5. TSS signal heatmap (ChIP vs Input)
6. TSS signal heatmap (log2 ChIP/Input ratio)
7. Peak center heatmap (log2 ratio)
8. TSS signal profile curve
9. IGV-style track screenshots (for top peaks)

**Before visualization, check**:
- [ ] bigWig data range (set Y-axis to p99 of actual values)
- [ ] Chromosome naming consistency across all files
- [ ] NumPy version < 2.0 (for pyGenomeTracks)
