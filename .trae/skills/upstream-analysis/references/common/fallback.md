# Fallback Strategy & Error Handling

## General Principles

1. **Never silently fail** — always report the error to the user with the log tail
2. **Try 3 levels** before giving up: primary tool -> fallback tool -> manual workaround
3. **Preserve state** — don't delete intermediate files on failure; the user may want to inspect them
4. **Explain why** — tell the user what happened, not just what to do next

## Download Fallback

See `download-strategy.md` for the full decision tree.

```
Aspera (port 33001) -> ENA Aspera -> prefetch (HTTPS) -> kingfisher -> manual download
```

## QC Fallback

```
fastp (primary) -> trimmomatic (fallback) -> manual fastx_trimmer (last resort)
```

## Alignment Fallback

```
Bowtie2 (primary for ChIP/ATAC) -> BWA-mem (fallback) -> STAR (RNA-seq primary)
```

## Deduplication Fallback

```
samtools markdup -r (primary)
  -> Picard MarkDuplicates (fallback, needs extra mark BAM step)
  -> sambamba markdup (alternative)
```

**Note**: All methods require coordinate-sorted BAM. For samtools markdup specifically:
```
samtools sort -n -> samtools fixmate -m -> samtools sort -> samtools markdup -r
```

## Peak Calling Fallback (ChIP-seq)

```
MACS2 (primary, most standard)
  -> Genrich (fallback, handles replicates, different BAM sort requirement)
  -> SEACR (last resort, for broad marks, uses bigWig not BAM)
```

### Critical Differences

| Tool | BAM Sort | Input Required | Output Format |
|------|----------|----------------|---------------|
| MACS2 | coordinate | optional | narrowPeak/broadPeak |
| Genrich | queryname | recommended | narrowPeak + bedgraph |
| SEACR | bigWig | required | bed + bigWig |

**Genrich requires queryname-sorted BAM**: `samtools sort -n <BAM> -o <BAM>_qname.bam`

## Visualization Fallback

```
deepTools (primary: bamCoverage, bigwigCompare, computeMatrix, plotHeatmap)
  -> pyGenomeTracks (for IGV-style track screenshots)
  -> R ggplot2 (last resort, more customization but slower)
```

## Common Errors and Fixes

### "fewer reads in R2 than R1"

**Cause**: SRA file incomplete or fastq conversion error
**Fix**: Re-download SRA, use fastp to enforce strict pairing

### "SAM/BAM file not sorted by queryname"

**Cause**: Genrich requires queryname sort, but BAM was coordinate-sorted
**Fix**: `samtools sort -n <BAM> -o <BAM>_qname.bam`

### "unrecognized arguments" (deepTools)

**Cause**: Parameter name changed between versions
**Fix**: Check `--help` for current parameter names. Common changes:
- `--whatToShow heatmap` -> `--whatToShow "heatmap and colorbar"`
- `--operation log2ratio` -> `--operation log2`

### "A module compiled using NumPy 1.x cannot be run in NumPy 2.x"

**Cause**: NumPy 2.0 breaking change
**Fix**: `pip install "numpy<2"` then reinstall affected package

### Empty gene track in pyGenomeTracks

**Cause**: Chromosome naming mismatch (chr1 vs 1)
**Fix**: `sed 's/^chr//' genes.bed > genes_nochr.bed`

### Signal appears as flat bars in track visualization

**Cause**: Y-axis max_value too low relative to actual data range
**Fix**: Check actual data range first:
```python
import pyBigWig, numpy as np
bw = pyBigWig.open("file.bw")
vals = bw.values("1", start, end)
print(np.nanmax(vals), np.nanmin(vals))
```
Then set max_value to ~p99 of data range.

### Command not found after pip install

**Cause**: pip installed to different PATH than expected
**Fix**: `export PATH=~/.local/bin:$PATH` or use `python3 -m pip install`

## When All Fallbacks Fail

1. Report the error with full log tail
2. Explain what was tried
3. Suggest:
   - Installing the missing tool from source
   - Using a different server with the tool installed
   - Using Docker/Singularity container
   - Manual workaround steps
4. Do NOT proceed to next stage — wait for user decision
