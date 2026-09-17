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

# Load at base resolution (SINGLE COLON binspec!)
cooler cload pairs -c1 2 -p1 3 -c2 4 -p2 5 \
  <GENOME>.chrom.sizes:1000 <SRR>.pairs.gz <SRR>.1kb.cool

# Multi-resolution pyramid
cooler zoomify <SRR>.1kb.cool -o <SRR>.mcool

# Balance (MANDATORY, per resolution used)
cooler balance <SRR>.mcool::resolutions/10000 --cis-only -p 16
cooler balance <SRR>.mcool::resolutions/25000 --cis-only -p 16
cooler balance <SRR>.mcool::resolutions/100000 --cis-only -p 16
```

## cooltools: structure analysis

```bash
# Compartments (A/B) — 100kb, output bigWig eigen track
cooltools eigs-cis -I <SRR>.mcool::resolutions/100000 -o eigs_<SRR> --bigwig

# TADs — insulation score at 25kb, boundary = valley
cooltools insulation <SRR>.mcool::resolutions/25000 \
  -o insul_<SRR>.tsv --windows 50000 100000 200000

# Loops — 10kb, ONLY if deep (>=300M valid pairs)
cooltools dots -I <SRR>.mcool::resolutions/10000 -o dots_<SRR>

# P(s) contact probability
cooltools expected-cis -o exp_<SRR> <SRR>.mcool::resolutions/25000
```

## pyGenomeTracks: contact map

```ini
[hic]
file = <SRR>.mcool::resolutions/25000
title = <SAMPLE> 25kb
colormap = RdBu_r
depth = 1000000
transform = log1p
height = 5

[insulation]
file = insul_<SRR>.tsv
title = insulation (TAD boundaries = valleys)
height = 1.5
type = line

[genes]
file = <GENOME>_genes.bed
title = genes
height = 2
```

```bash
pyGenomeTracks --tracks tracks.ini --region chr1:50,000,000-55,000,000 -o hic_region.png
```

## Resolution Decision Table

| Analysis | Resolution | Min valid pairs needed |
|----------|-----------|----------------------|
| Loops (APA/dots) | 1-10kb | 300M+ (deep data only) |
| TAD boundaries (insulation) | 5-10kb | 150M |
| TAD domains | 25kb | 50M |
| Compartments (A/B) | 100kb | 10M |
| Whole-genome overview | 250kb-1Mb | any |

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
