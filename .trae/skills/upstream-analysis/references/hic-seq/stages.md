# Hi-C Stage Tree & Verification Points

## Pipeline Overview

```
1. Download → 2. Convert → 3. QC/Trim → 4. chromap Index (one-time) → 5. Map (Hi-C preset)
→ 6. Pair Classification → 7. Matrix Build → 8. Balance → 9. Library QC → 10. Structure Analysis → 11. Visualize
```

## Key Differences from ChIP-seq / ATAC-seq

- **Data is a pairwise contact matrix, not a linear track** — output unit is `.cool/.mcool`, not bigWig
- **Chimeric reads**: Hi-C reads can span the ligation junction; the aligner MUST support split alignment (chromap handles this natively)
- **No peak calling / no Input / no mtDNA filter / no Tn5 shift** — none of the ATAC-specific stages apply
- **Multi-resolution matrices**: 1kb–1Mb built once via `cooler zoomify`; each analysis uses its own resolution
- **Matrix balancing (ICE) is MANDATORY** — unbalanced heatmaps are garbage
- **Downstream = 3D structure**: compartments (A/B), TADs, loops, P(s) — not peaks
- **Needs genome FASTA** (not just bt2 index) to build the chromap index once per genome

## Toolchain (verified on server 2026-09-17)

| Tool | Version | Role | Status |
|------|---------|------|--------|
| chromap | 0.2.7-r494 | align + chimeric split + pair classify | `~/.local/bin/chromap` ✓ functional-tested |
| hicstuff | 3.2.5 | fallback aligner (bowtie2 iterative) | ✓ installed |
| cooler | 0.10.4 | pairs → matrix, balance | ✓ functional-tested |
| cooltools | 0.7.1 | compartments / TAD / loop / P(s) | ✓ installed (numba fixed) |
| pyGenomeTracks | 3.9 | .cool track rendering | ✓ functional-tested |

## Stage Details

### Stage 1-3: Download / Convert / QC

Same as ChIP-seq. See `common/download-strategy.md`.

fastp: NO aggressive trimming — keep reads intact for split alignment. Use `--length_required 30` default.

### Stage 4: chromap Index ★ (HiC-SPECIFIC, one-time per genome)

```bash
# Requires genome FASTA (NOT the bt2 index!)
chromap -i -r hg38.fa -o hg38.chromap.idx
# ~15 min for hg38 with default threads; do once, reuse forever
```

**Server state**: hg38 FASTA is NOT on the server (only the bt2 index). Before first Hi-C run: download hg38.fa (UCSC ~3GB) then build index. Cache it next to the bt2 index.

### Stage 5: Alignment (chromap Hi-C preset) ★

```bash
chromap --preset hic \
  -x hg38.chromap.idx -r hg38.fa \
  -1 <SRR>_1.clean.fq.gz -2 <SRR>_2.clean.fq.gz \
  --pairs -o <SRR>.pairs.gz \
  -t 16
```

The `--preset hic` automatically enables: split alignment (chimeric reads), MAPQ-aware output, pair typing (UU/NU/MU...), bulk-level PCR dedup. Output is standard **4DN pairs format** with `pair_type` column.

**Fallback** (if chromap fails): hicstuff pipeline (pip-installed, uses bowtie2 iterative mapping):
```bash
hicstuff pipeline --bowtie2 -g hg38.fa -e DpnII -1 r1.fq.gz -2 r2.fq.gz -o out_dir -p 16
```

### Stage 6: Pair Classification QC ★

```bash
# Pair type distribution (UU = unique-unique, best quality)
zcat <SRR>.pairs.gz | grep -v "^#" | cut -f8 | sort | uniq -c
```

**Verification (library quality gates)**:
- [ ] valid pair rate (UU+NU): **60-80% good; <40% warn user**
- [ ] cis/trans ratio: cis 40-60% typical; <30% suggests random ligation
- [ ] religation/intrachromosomal short-range excess: check P(s) shape

### Stage 7: Matrix Construction ★

```bash
# chrom.sizes from FASTA index (tab-separated, no header!)
samtools faidx hg38.fa && cut -f1,2 hg38.fa.fai > hg38.chrom.sizes

# Load pairs at base resolution, then build pyramid
cooler cload pairs -c1 2 -p1 3 -c2 4 -p2 5 hg38.chrom.sizes:1000 <SRR>.pairs.gz <SRR>.1kb.cool
cooler zoomify <SRR>.1kb.cool -o <SRR>.mcool
```

**PITFALL (see pitfalls.md #23)**: binspec uses SINGLE colon `chrom.sizes:1000`, NOT `::` (that's cooler URI syntax).

### Stage 8: Matrix Balancing ★ (MANDATORY)

```bash
# Balance each resolution; --cis-only avoids trans noise
cooler balance <SRR>.mcool::resolutions/10000 --cis-only -p 16
# Do all resolutions used downstream (typically 10kb, 25kb, 100kb)
```

**Verification**: `cooler info` shows weights present; balanced dump shows non-NaN values.

### Stage 9: Library QC

```bash
# cis/trans + P(s) decay
cooltools eigs-cis ... (also produces eigen tracks)
# Simple stats:
cooler dump --table pixels <SRR>.mcool::resolutions/25000 | awk 'NR>1{...}'
```

Report to user: total contacts, cis%, trans%, valid-pair rate, dedup rate.

### Stage 10: Structure Analysis ★

```bash
# Compartments (A/B): eigenvector per chrom, 100kb res
cooltools eigs-cis -I <SRR>.mcool::resolutions/100000 -o eigs --bigwig

# TAD boundaries: insulation score valleys, 10-25kb res
cooltools insulation <SRR>.mcool::resolutions/25000 -o insulation.tsv --windows 50kb 100kb

# Loops (needs deep data, >=300-500M valid pairs; skip if shallow)
cooltools dots -I <SRR>.mcool::resolutions/10000 -o dots

# P(s) contact law
cooltools expected-cis -o expected <SRR>.mcool::resolutions/25000
```

Resolution guide: 1kb loops (deep data only) / 5-10kb insulation / 25kb TADs / 100kb compartments. Rule: aim ≥1,000 contacts per bin — if less, coarsen.

### Stage 11: Visualization

pyGenomeTracks with `.cool`/`.mcool` track (functionally verified):

```ini
[hic]
file = <SRR>.mcool::resolutions/25000
title = <SAMPLE> contact map
colormap = RdBu_r
depth = 1000000
transform = log1p

[insulation track]
file = insulation.tsv
...

[genes]
file = hg38_genes.bed
```

Plus: saddle plot (compartment strength), P(s) curve, APA plot if loops called.

## Test Mode (small-scale validation)

Use any small published Hi-C SRR (~1-2GB fastq). PASS criteria:
- chromap index builds + maps without error
- valid pair rate > 40%
- `.mcool` builds, balance completes
- pyGenomeTracks renders a contact map with visible diagonal decay structure
- Expected time: ~30-60 min total

## Known Pitfalls Specific to Hi-C (full list in common/pitfalls.md #20-24)

1. chromap repo = `haowenz/chromap`; v0.3.x has NO prebuilt binaries — use v0.2.7 asset, scp to server
2. github.com blocked even locally — download via api.github.com with `Accept: application/octet-stream`
3. cooltools needs working numba; system numba may be broken → `pip install --user numba`
4. cooler binspec = single colon
5. hg38 FASTA needed for chromap index (bt2 index insufficient)
