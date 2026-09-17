# ChIP-seq Visualization Guide

## Prerequisites Checklist

Before starting any visualization:
- [ ] NumPy version < 2.0 (`python3 -c "import numpy; print(numpy.__version__)"`)
- [ ] deepTools installed (`bamCoverage --version`)
- [ ] pyGenomeTracks installed (if doing IGV-style tracks)
- [ ] pyBigWig installed (`python3 -c "import pyBigWig"`)
- [ ] Chromosome naming consistency checked across all files

## Step 1: Generate bigWig Signal Tracks

### RPM-normalized bigWig (per sample)
```bash
bamCoverage \
  -b <SAMPLE>.dedup.bam \
  -o <SAMPLE>_RPM.bw \
  --binSize 10 \
  --normalizeUsing RPM \
  --effectiveGenomeSize 2913022398 \
  --numberOfProcessors 16
```

### log2(ChIP/Input) Ratio bigWig
```bash
bigwigCompare \
  -b1 <CHIP>_RPM.bw \
  -b2 <INPUT>_RPM.bw \
  --operation log2 \
  --binSize 10 \
  --numberOfProcessors 16 \
  -o <CHIP>_vs_input_log2.bw
```

**IMPORTANT**: Use `log2` not `log2ratio`. The parameter name is `--operation log2`.

## Step 2: Prepare Reference BED

### Gene BED file (for TSS-centered visualization)

Check chromosome naming FIRST:
```python
import pyBigWig
bw = pyBigWig.open("<SAMPLE>_RPM.bw")
chroms = list(bw.chroms().keys())
print("bigWig chroms:", chroms[:5])
bw.close()
```

If bigWig uses `1` but gene BED uses `chr1`, unify:
```bash
sed 's/^chr//' genes.bed > genes_nochr.bed
# Or reverse: sed 's/^/chr/' to add prefix
```

## Step 3: TSS Heatmaps

### ChIP vs Input (Separate)
```bash
computeMatrix reference-point \
  -S <CHIP>_RPM.bw <INPUT>_RPM.bw \
  -R genes_nochr.bed \
  --referencePoint TSS \
  -a 3000 -b 3000 \
  --binSize 50 \
  --numberOfProcessors 16 \
  -o matrix_TSS.gz

plotHeatmap \
  -m matrix_TSS.gz \
  -out vis_tss_heatmap_deeptools.png \
  --colorMap RdBu_r \
  --whatToShow "heatmap and colorbar" \
  --dpi 150 \
  --sortUsing mean
```

**IMPORTANT**: `--whatToShow` value must be `"heatmap and colorbar"` (quoted), not just `"heatmap"`.

### log2(ChIP/Input) Ratio Heatmap
```bash
computeMatrix reference-point \
  -S <CHIP>_vs_input_log2.bw \
  -R genes_nochr.bed \
  --referencePoint TSS \
  -a 3000 -b 3000 \
  --binSize 50 \
  --numberOfProcessors 16 \
  -o matrix_TSS_log2.gz

plotHeatmap \
  -m matrix_TSS_log2.gz \
  -out vis_tss_heatmap_log2.png \
  --colorMap RdBu_r \
  --whatToShow "heatmap and colorbar" \
  --dpi 150 \
  --sortUsing mean \
  --zMin -2 --zMax 2
```

**IMPORTANT**: Do NOT use `--samplesLabels` with parentheses — it causes argparse errors. Omit or use simple labels.

## Step 4: Peak Center Heatmaps

```bash
computeMatrix reference-point \
  -S <CHIP>_vs_input_log2.bw \
  -R genrich_peaks.narrowPeak \
  --referencePoint center \
  -a 2000 -b 2000 \
  --binSize 25 \
  --numberOfProcessors 16 \
  -o matrix_peak_log2.gz

plotHeatmap \
  -m matrix_peak_log2.gz \
  -out vis_peak_heatmap_log2.png \
  --colorMap RdBu_r \
  --whatToShow "heatmap and colorbar" \
  --dpi 150 \
  --sortUsing mean \
  --zMin -2 --zMax 2
```

## Step 5: TSS Signal Profile

```bash
plotProfile \
  -m matrix_TSS_log2.gz \
  -out vis_tss_profile_log2.png \
  --dpi 150 \
  --colors darkred \
  --plotTitle "log2(ChIP/Input) at TSS"
```

## Step 6: IGV-Style Track Screenshots

### pyGenomeTracks Configuration

Create `tracks.ini`:
```ini
[spacer]
height = 0.5

[genes]
file = genes_nochr.bed
title = Genes (<GENOME>)
height = 2
style = UCSC
fontsize = 8

[spacer]
height = 0.3

[narrow_peak]
file = genrich_peaks.narrowPeak
title = Peaks (<CALLER>)
height = 1.5
fontsize = 8

[spacer]
height = 0.3

[bigwig]
file = <CHIP>_RPM.bw
title = ChIP RPM
height = 3
color = #CC0000
min_value = 0
max_value = <DATA_P99>
type = fill
nans_to_zeros = true
fontsize = 8
number_of_bins = 2000

[spacer]
height = 0.3

[bigwig]
file = <INPUT>_RPM.bw
title = Input RPM
height = 3
color = #0000CC
min_value = 0
max_value = <DATA_P99>
type = fill
nans_to_zeros = true
fontsize = 8
number_of_bins = 2000

[spacer]
height = 0.3

[bigwig]
file = <CHIP>_vs_input_log2.bw
title = log2(ChIP/Input)
height = 3
color = #008800
min_value = -2
max_value = 2
type = fill
nans_to_zeros = true
fontsize = 8
number_of_bins = 2000
```

### Generate Track Images

**IMPORTANT**: Use `--region` not `-r` (some versions don't recognize `-r`).

```bash
pyGenomeTracks --tracks tracks.ini \
  --region <CHROM>:<START>-<END> \
  -o igv_<REGION>.png \
  --dpi 150
```

### Selecting Regions for Display

Choose top peaks by signal value:
```bash
sort -k7,7 -nr genrich_peaks.narrowPeak | head -5
```

Pick 3 diverse regions (different chromosomes, different distances to genes).

### Y-axis Data Range Check

**BEFORE setting max_value**, always check actual data range:
```python
import pyBigWig, numpy as np
bw = pyBigWig.open("<CHIP>_RPM.bw")
vals = bw.values("<CHROM>", start, end)
arr = np.array(vals)
print(f"min={np.nanmin(arr):.1f}, max={np.nanmax(arr):.1f}, p99={np.nanpercentile(arr,99):.1f}")
```

Set `max_value` to approximately the p99 value. **Never guess — always check.**

## Common Visualization Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Y-axis too low | Signal appears as flat bars | Check data range, set max to p99 |
| Line breaks at zero | Discontinuous signal | Use `type = fill` not `type = line` |
| Empty gene track | No genes visible | Check chr naming, create nochr BED |
| NumPy crash | pyGenomeTracks won't start | `pip install "numpy<2"` |
| argparse error | plotHeatmap fails | Remove `--samplesLabels` with parentheses |
| Command not found | bigwigCompare fails | Check spelling: `bigwigCompare` not `bigwCompare` |
