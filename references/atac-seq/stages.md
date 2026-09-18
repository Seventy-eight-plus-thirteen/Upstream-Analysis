# ATAC-seq Stage Tree & Verification Points

## Pipeline Overview

```
1. Download  →  2. Convert  →  3. QC/Trim  →  4. Align  →  5. mtDNA Filter  →  6. Dedup  →  7. Tn5 Shift  →  8. Peak Call  →  9. QC: TSS  →  10. Visualize
```

## Key Differences from ChIP-seq

- **No Input control** — ATAC-seq doesn't use Input
- **Mitochondrial filtering is MANDATORY** — Tn5 cuts mtDNA heavily
- **Tn5 offset correction** — +4/-4 bp shift for precise footprinting
- **Fragment size distribution** — diagnostic for data quality
- **TSS enrichment score** — core ATAC QC metric
- **Nextera adapter** — different from standard Illumina

## Stage Details

### Stage 1: Data Download

Same as ChIP-seq. See `common/download-strategy.md`.

### Stage 2: Format Conversion

Same as ChIP-seq. `fasterq-dump + pigz`.

### Stage 3: QC & Adapter Trimming

**Primary**: fastp with ATAC-specific parameters
**Fallback**: Trimmomatic with Nextera adapters

```bash
# ATAC-seq specific fastp
# Key: do NOT set --length_required too high (ATAC fragments can be short)
# Nextera adapter is auto-detected by fastp
fastp -i <SRR>_1.fastq.gz -I <SRR>_2.fastq.gz \
  -o <SRR>_1.clean.fq.gz -O <SRR>_2.clean.fq.gz \
  --detect_adapter_for_pe \
  --length_required 15 \
  --thread 16 \
  --html <SRR>_fastp.html \
  --json <SRR>_fastp.json
```

**CRITICAL: Do NOT use `--length_required 30`** — ATAC-seq open chromatin regions produce fragments as short as 30-50bp (nucleosome-free regions). Setting minimum to 30 will discard valid short fragments.

**Verification**:
- [ ] R1 and R2 read counts MUST be identical
- [ ] Check insert size distribution in fastp report — should show periodicity (~200bp, ~400bp)
- [ ] If insert size distribution is flat or shows single peak at very short length: poor quality

### Stage 4: Alignment

**Primary**: Bowtie2 with ATAC-specific parameters

```bash
# Key: -X 2000 allows longer fragments (ATAC can produce up to 2kb fragments)
# --no-mixed --no-discordant: strict paired-end
# --sensitive recommended over --very-sensitive (3x faster, comparable results)
# Pipe directly to samtools sort to avoid intermediate SAM
bowtie2 -x <INDEX> \
  -1 <SRR>_1.clean.fq.gz -2 <SRR>_2.clean.fq.gz \
  -p 16 --sensitive \
  -X 2000 \
  --no-mixed --no-discordant \
  2> <SRR>_bowtie2.log \
  | samtools sort -@ 16 -o <SRR>.sorted.bam -
samtools index <SRR>.sorted.bam
```

**Note on sensitivity**: `--very-sensitive` is 3x slower than `--sensitive` with minimal improvement for ATAC-seq. Use `--sensitive` by default; reserve `--very-sensitive` only for low-input or low-quality samples. On shared servers with high load (CPU>100), the speed difference is amplified.

**Verification**:
- [ ] Alignment rate > 70% (ATAC can be lower than ChIP due to mtDNA)
- [ ] Check fragment size distribution:
  ```bash
  samtools view <SRR>.sorted.bam | awk 'and($2,2)==0 {print $9}' | sort -n | uniq -c | head -20
  # Should show peaks at ~75bp (NFR), ~200bp (mononucleosome), ~400bp (dinucleosome)
  ```

### Stage 5: Mitochondrial Filtering ★ (ATAC-SPECIFIC)

**This step is MANDATORY for ATAC-seq.** Tn5 transposase cuts mitochondrial DNA extensively; mtDNA reads can account for 20-50% of total reads.

```bash
# CRITICAL: samtools 1.13+ removed the -v (exclude region) flag.
# Safe cross-version approach: explicitly pass all nuclear contigs as regions.

# Step 1: Detect MT chromosome name (could be "chrM", "MT", etc.)
MT=$(samtools view -H <SRR>.sorted.bam | awk '$1=="@SQ"{sub(/^SN:/,"",$2); if($2 ~ /chrM$|^MT$|chrM_/) print $2}' | head -1)
echo "MT chromosome name: $MT"

# Step 2: Extract all nuclear contig names (everything except MT)
REGIONS=$(samtools view -H <SRR>.sorted.bam | awk -v mt="$MT" '$1=="@SQ"{sub(/^SN:/,"",$2); if($2!=mt) print $2}')

# Step 3: Filter by keeping only nuclear contigs
samtools view -@ 16 -b <SRR>.sorted.bam $REGIONS > <SRR>.nochrM.bam
samtools sort -@ 16 <SRR>.nochrM.bam -o <SRR>.nochrM.sorted.bam
samtools index <SRR>.nochrM.sorted.bam
rm -f <SRR>.nochrM.bam
```

**DO NOT use `samtools view -v chrM`** — the `-v` flag was removed in samtools 1.13. The explicit region approach above works on all versions.

**Verification**:
- [ ] Count reads before and after:
  ```bash
  echo "Before:" && samtools view -c <SRR>.sorted.bam
  echo "After:" && samtools view -c <SRR>.nochrM.sorted.bam
  ```
- [ ] mtDNA fraction = (before - after) / before
- [ ] If mtDNA fraction > 50%: warn user (very high contamination)
- [ ] If mtDNA fraction < 5%: unusual, check if chrM naming is correct

### Stage 6: Deduplication

Same as ChIP-seq (samtools markdup). See `chip-seq/params.md` for command.

**Note**: ATAC-seq deduplication rate is often lower than ChIP-seq because each cell produces unique insertion sites. High duplication (>30%) may indicate low cell number or over-amplification.

### Stage 7: Tn5 Offset Correction ★ (ATAC-SPECIFIC)

Tn5 transposase creates a 9bp duplication during integration. Reads on the + strand need +4 shift, reads on the - strand need -5 shift (or -4 depending on convention).

```bash
# Using deepTools alignmentSieve (recommended)
alignmentSieve \
  -b <SRR>.dedup.bam \
  --shift 4 -4 \
  -o <SRR>.shifted.bam \
  -p 16 \
  --ATAC

# Verify
samtools view <SRR>.shifted.bam | head -1000 | awk '{print $2, $4}' | head -20
```

**What it does**: Shifts + strand reads +4bp and - strand reads -5bp, centering reads at the Tn5 cut site. The `--ATAC` flag also filters out reads with large insert sizes (nucleosome-bound fragments), so the shifted.bam will be significantly smaller than the dedup.bam (typically 20-30% of dedup size). This is expected behavior — only short nucleosome-free fragments are retained for peak calling and visualization.

**Verification**:
- [ ] BAM file created and indexable
- [ ] File size should be 20-30% of dedup.bam (not a 1:1 copy — filtering occurs)
- [ ] If shifted.bam is similar size to dedup.bam: check if `--ATAC` flag was passed

### Stage 8: Peak Calling

**Primary**: Genrich with ATAC mode (recommended, already on server)
**Fallback**: MACS2 with ATAC-specific parameters (if MACS2 installed)

#### Genrich (ATAC mode, recommended)
```bash
# CRITICAL: Genrich requires queryname-sorted BAM
# ATAC mode is `-j` (NOT `--atacpair`, which does not exist in 0.6.2).
# `-q` (FDR q-value) must be within (0,1]; use 0.05, never 2.0.
# `-e` needs an argument and will swallow `-v` if empty — omit it (mtDNA already removed).
samtools sort -n -@ 16 <SRR>.shifted.bam -o <SRR>.shifted.qname.bam

Genrich \
  -t <SRR>.shifted.qname.bam \
  -r -v -j \
  -q 0.05 \
  -o peaks/genrich_atac_peaks.narrowPeak
```

#### MACS2 (ATAC mode)
```bash
macs2 callpeak \
  -t <SRR>.shifted.bam \
  -f BAMPE \
  --nomodel \
  --shift -75 \
  --extsize 150 \
  -g hs \
  -q 0.05 \
  -n <SAMPLE> \
  --outdir peaks/
```

**Key parameters explained**:
- `--nomodel`: don't build shifting model (ATAC is not ChIP)
- `--shift -75 --extsize 150`: extends 75bp each direction from cut site, capturing ~150bp nucleosome-free regions
- `-f BAMPE`: use paired-end information

#### Genrich (ATAC fallback, server has this)
```bash
# CRITICAL: Genrich requires queryname-sorted BAM
samtools sort -n -@ 16 <SRR>.shifted.bam -o <SRR>.shifted.qname.bam

Genrich \
  -t <SRR>.shifted.qname.bam \
  -r -e -v \
  --atacpair \
  -q 2.0 \
  -o peaks/genrich_atac_peaks.narrowPeak
```

**Verification**:
- [ ] Peak count reasonable: ATAC typically 50,000-500,000 peaks
- [ ] If < 10,000: threshold too stringent or data quality issue
- [ ] If > 1,000,000: threshold too loose or artifact (check blacklist regions)

### Stage 9: QC Metrics ★ (ATAC-SPECIFIC)

#### TSS Enrichment Score

```bash
# Compute signal around TSS
computeMatrix reference-point \
  -S <SRR>_BPM.bw \
  -R <GENES_BED> \
  --referencePoint TSS \
  -a 1000 -b 1000 \
  --binSize 10 \
  -o matrix_TSS_atac.gz

# The TSS enrichment = (signal at TSS) / (signal at flanks)
# Can be extracted from the matrix
```

**TSS enrichment interpretation**:
- > 10: excellent quality
- 6-10: good quality
- 3-6: acceptable
- < 3: poor quality, may need re-sequencing

#### Fragment Size Distribution

```bash
# Extract fragment sizes from BAM
samtools view <SRR>.dedup.bam | \
  awk 'and($2,2)==0 {len=$9; if(len<0) len=-len; print len}' | \
  sort -n | uniq -c | \
  awk '{print $2, $1}' > fragment_distribution.txt

# Expected: peaks at ~75bp (NFR), ~200bp (mono-nucleosome), ~400bp (di-nucleosome)
```

### Stage 10: Visualization

ATAC-seq visualization (single-sample, no Input comparison):

#### deepTools: TSS heatmap + signal profile
```bash
# computeMatrix for TSS (2kb upstream/downstream)
computeMatrix reference-point \
  -S <SRR1>_BPM.bw <SRR2>_BPM.bw \
  -R hg38_genes.nochr.bed \
  --referencePoint TSS \
  -a 2000 -b 2000 \
  --binSize 10 \
  -p 16 \
  -o matrix_TSS.gz

plotHeatmap -m matrix_TSS.gz -o atac_TSS_heatmap.png --colorMap RdBu_r --dpi 200
plotProfile -m matrix_TSS.gz -o atac_TSS_profile.png --plotType lines --dpi 200
```

#### pyGenomeTracks: IGV-style genome tracks
```ini
# tracks.ini
[bigwig sample1]
file = <SRR1>_BPM.bw
title = <Label1>
height = 4
min_value = 0
max_value = 80
type = fill
color = #27D2BF

[bigwig sample2]
file = <SRR2>_BPM.bw
title = <Label2>
height = 4
min_value = 0
max_value = 80
type = fill
color = #F87454

[narrowPeak peaks1]
file = peaks_<SRR1>.narrowPeak
title = Peaks <Label1>
height = 2
color = #27D2BF

[narrowPeak peaks2]
file = peaks_<SRR2>.narrowPeak
title = Peaks <Label2>
height = 2
color = #F87454

[bed genes]
file = hg38_genes.nochr.bed
title = Genes
height = 2
style = UCSC
fontsize = 8
```

```bash
# Find top-signal regions from normal chromosomes for track visualization
grep -E "^[0-9]+\s|^X\s|^Y\s" peaks_<SRR>.narrowPeak | sort -k7 -n -r | head -3

# Generate tracks for a region
pyGenomeTracks --tracks tracks.ini --region "chr:start-end" -o track.png --dpi 200
```

**Note**: No log2(ChIP/Input) ratio (no Input control in ATAC-seq). Use BPM-normalized bigwig for single-sample visualization. For multi-sample comparison, use bigwigCompare with `--operation ratio` or `--operation log2`.
