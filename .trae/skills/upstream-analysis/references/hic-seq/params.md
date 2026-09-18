# Hi-C Parameter Templates

## chromap Index (one-time per genome)

```bash
# Input: genome FASTA (NOT bt2 index)
chromap -i -r <GENOME>.fa -o <GENOME>.chromap.idx
# hg38: ~15 min, ~5GB index; cache alongside bt2 index
```

## chromap Mapping (Hi-C preset)

```bash
chromap --preset hic \
  -x <GENOME>.chromap.idx \
  -r <GENOME>.fa \
  -1 <SRR>_1.clean.fq.gz -2 <SRR>_2.clean.fq.gz \
  --pairs -o <SRR>.pairs.gz \
  -t 16
```

| Param | Value | Why |
|-------|-------|-----|
| `--preset hic` | (fixed) | split alignment for chimeric reads + pair typing + bulk dedup |
| `--pairs` | (fixed) | 4DN pairs format output (readID chrom1 pos1 chrom2 pos2 strand1 strand2 pair_type) |
| `-q` | preset default (1) | keeps pairs with type labels; filter downstream by pair_type |

Pair type codes: UU (unique-unique, best) / NU / MU / DE (dangling end) / SC (self-circle) / RL (religation) / ...

## hicstuff Fallback Pipeline

```bash
hicstuff pipeline --bowtie2 -g <GENOME>.fa -e <enzyme, e.g. DpnII or HindIII> \
  -1 <SRR>_1.clean.fq.gz -2 <SRR>_2.clean.fq.gz \
  -o hicstuff_<SRR>/ -p 16
# Enzyme must match the experiment's restriction enzyme (check GEO metadata)
```

## cooler: pairs → matrix

```bash
# chrom.sizes: tab-separated, no header, from faidx
samtools faidx <GENOME>.fa && cut -f1,2 <GENOME>.fa.fai > <GENOME>.chrom.sizes

# CRITICAL: chromap outputs PLAIN-TEXT pairs (not gzip).
# cooler cload expects .pairs.gz — gzip the file first:
gzip <SRR>.pairs
# (or use --input-buffer 0 to handle plain text, but gzip is safer)

# Load at base resolution (SINGLE COLON binspec!)
cooler cload pairs -c1 2 -p1 3 -c2 4 -p2 5 \
  <GENOME>.chrom.sizes:1000 <SRR>.pairs.gz <SRR>.1kb.cool

# Multi-resolution pyramid (zoomify DOUBLES base: 1000→2000→4000→…→64000→128000)
# Available resolutions are powers-of-2 × base, NOT arbitrary values.
cooler zoomify <SRR>.1kb.cool -o <SRR>.mcool
# Verify available resolutions:
cooler ls <SRR>.mcool

# Balance (MANDATORY, per resolution used)
# Use zoomify's actual resolutions (e.g. 64000, 128000), not 10000/25000/100000
cooler balance <SRR>.mcool::resolutions/64000 --cis-only -p 16
cooler balance <SRR>.mcool::resolutions/128000 --cis-only -p 16
# Skip 32000 if data is sparse (variance won't converge)
```

## cooltools 0.7.1: structure analysis

```bash
# Compartments (A/B) — 128kb
# cooltools 0.7.1 API: COOL_PATH is positional (NOT -I); NO --bigwig (needs UCSC bedGraphToBigWig)
cooltools eigs-cis <SRR>.mcool::resolutions/128000 -o eigs_<SRR>

# TADs — insulation score at 128kb, boundary = valley
# cooltools 0.7.1: uses --window-pixels (NOT --windows bp); NO --bigwig; NO -p (causes IndexError on sparse data)
# NOTE: may fail with IndexError on sparse bins (cooler 0.10.4 / cooltools 0.7.1 incompatibility) — non-fatal
cooltools insulation <SRR>.mcool::resolutions/128000 \
  -o insul_<SRR>.tsv --window-pixels 5 10

# P(s) contact probability
# cooltools 0.7.1: COOL_PATH is positional + -o (NOT -I)
cooltools expected-cis <SRR>.mcool::resolutions/128000 -o exp_<SRR>

# Convert eigenvector TSV to bedgraph for pyGenomeTracks:
awk -F"\t" 'NR>1 {print $1"\t"$2"\t"$3"\t"$5}' eigs_<SRR>.cis.vecs.tsv > <SRR>_EV1.bedgraph
```

## pyGenomeTracks: contact map

```ini
[hic]
file = <SRR>.mcool::resolutions/128000
title = <SAMPLE> 128kb
file_type = hic_matrix
colormap = YlOrRd
depth = 1000000
transform = log1p
height = 5

[EV1]
file = <SRR>_EV1.bedgraph
title = EV1 (A/B compartment)
file_type = bedgraph
color = darkblue
min_value = -1
max_value = 1
height = 1.5

[genes]
file = <GENOME>_genes.bed
title = genes
height = 2
```

```bash
pyGenomeTracks --tracks tracks.ini --region chr1:50,000,000-55,000,000 -o hic_region.png
```

## Resolution Decision Table

| Analysis | Resolution (zoomify) | Min valid pairs needed |
|----------|-----------|----------------------|
| Loops (APA/dots) | 2000-8000 | 300M+ (deep data only) |
| TAD boundaries (insulation) | 32000-64000 | 150M |
| TAD domains | 64000 | 50M |
| Compartments (A/B) | 128000 | 10M |
| Whole-genome overview | 256000-512000 | any |

Note: zoomify resolutions are powers-of-2 × base (1000). Common: 8000, 16000, 32000, 64000, 128000, 256000.
Rule of thumb: ≥1,000 contacts per bin at chosen resolution; otherwise coarsen.

## QC Thresholds

| Metric | Good | Warn |
|--------|------|------|
| Valid pair rate (UU) | 60-80% | <40% |
| cis fraction | 40-60% | <30% (random ligation) |
| Religation rate | <20% | >30% |
| Dedup rate | <20% | >30% (over-amplification) |
| P(s) shape | smooth power-law decay | flat or spiky |

## Memory Sizing

| Resolution | cooler balance peak RAM |
|-----------|------------------------|
| 1kb (per large chrom) | ~10-20GB |
| 10kb genome-wide | ~2-5GB |
| zoomify all resolutions | ~30-60GB transient |

Server has 92GB usable — safe for single-sample processing; for many parallel samples, stagger the balance stages.
