# Upstream-Analysis

A TRAE skill for end-to-end sequencing **upstream analysis** — from raw data download to publication-ready visualization — running on a remote Linux server. Supports **ChIP-seq**, **ATAC-seq**, and **Hi-C**, with an RNA-seq extension path.

## Features

- **Autopilot mode**: server-side orchestrator script self-drives the whole pipeline (download → QC → align → dedup → peak calling → visualization), self-heals known failures, and survives session loss (`mission.md` + `pipeline_status.txt` + `flags/` for resume).
- **Interactive Pre-Flight**: all decisions (mode, assay, server, download strategy, data source, genome, peak caller, polling, cleanup, visualization scope) collected upfront via `AskUserQuestion` — no mid-run interruptions.
- **Test mode**: run one sample end-to-end on a user-provided SRR number to validate the whole chain, output a PASS/FAIL report.
- **Robust download**: Aspera first, automatic downgrade to `prefetch` (HTTPS), `aria2c` multi-connection with dual mirrors for reference FASTA.
- **Parallel by default**: master/worker design, all samples run in parallel with dynamic thread sizing.
- **Long-task architecture (3 layers)**: server orchestrator + main-session watcher + schedule polling, with built-in progress reporting.
- **Battle-tested pitfalls**: 30+ documented pitfalls with fixes (samtools 1.13 compat, Genrich ATAC mode, deepTools BPM normalization, watcher misfires, PATH issues, and more).

## Quick Start

1. Install the skill into `~/.trae/skills/upstream-analysis/` (or the workspace `.trae/skills/`).
2. In a TRAE session, type `/upstream-analysis`.
3. Answer the Pre-Flight questions (mode, assay, server alias, data source...).
4. Walk away — the pipeline runs autonomously and reports back.

## Supported Assays

| Assay | Pipeline Highlights |
|-------|---------------------|
| ChIP-seq | fastp → Bowtie2 → markdup → MACS2/Genrich → ChIPseeker annotation → deepTools/pyGenomeTracks visualization; input control handling |
| ATAC-seq | fastp (`--length_required 15`) → Bowtie2 (`--sensitive`, `-X 2000`) → mtDNA filter (explicit nuclear contigs, samtools 1.13-safe) → markdup → Tn5 shift (`alignmentSieve`, +4/-4) → Genrich (`-j -q 0.05`) → BPM bigwig |
| Hi-C | chromap 0.2.7 alignment → hicstuff/cooler matrix → cooltools balancing → pyGenomeTracks visualization |

## Repository Structure

```
upstream-analysis/
├── SKILL.md                       # Skill entry: trigger + interaction engine
├── README.md                      # This file
├── references/
│   ├── common/                    # Shared: server-setup, env-checklist, download-strategy,
│   │                              #   reference-genome, geo-metadata, long-task, fallback, pitfalls
│   ├── chip-seq/                  # stages, params, test-mode, visualization
│   ├── atac-seq/                  # stages, params, test-mode
│   ├── hic-seq/                   # stages, params
│   └── rna-seq/                   # Future extension
└── scripts/
    ├── orchestrator_template.sh   # Layer 1: self-driving pipeline (parallel master/worker)
    ├── check_env.sh               # Environment scanner
    ├── test_pipeline.sh           # Test-mode runner
    └── poll_job.sh                # Generic job poller
```

## Workflow Overview

```
Data download (Aspera/prefetch/aria2c)
      → fastq conversion (fasterq-dump + pigz)
      → QC + trimming (FastQC / fastp / MultiQC)
      → Alignment (Bowtie2 → sorted BAM)
      → Assay-specific steps (mtDNA filter + Tn5 shift for ATAC; input control for ChIP)
      → Deduplication (samtools markdup)
      → Peak calling (MACS2 / Genrich)
      → Annotation & enrichment (ChIPseeker / clusterProfiler)
      → Visualization (deepTools heatmaps & profiles, pyGenomeTracks tracks)
```

## Reference Docs

- `references/common/env-checklist.md` — dependency matrix per assay
- `references/common/download-strategy.md` — download fallback decision tree
- `references/common/long-task.md` — 3-layer long-task architecture + parallel sizing
- `references/common/pitfalls.md` — 30+ pitfalls and their fixes
- `references/<assay>/stages.md` — stage tree with verification points
- `references/<assay>/params.md` — parameter templates

## Reference Genome Preparation

All assays require reference genome files. If you don't already have them on your server, here's how to obtain and build each one.

### 1. hg38 FASTA (required for all assays — alignment & chromap index)

```bash
# Download from UCSC (use aria2c for speed, dual mirrors for redundancy)
aria2c -x 16 -s 16 -k 4M -c \
  "https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz" \
  "https://hgdownload2.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz"

# Decompress (pigz is multi-threaded, much faster than gunzip)
pigz -d hg38.fa.gz
# Or: gunzip hg38.fa.gz

# Verify
grep -c ">" hg38.fa   # should be ~455 (chr1-22, X, Y, MT, scaffolds)
```

### 2. Bowtie2 Index (required for ChIP-seq & ATAC-seq)

```bash
# Build index (takes ~30-40 min with 16 threads)
bowtie2-build --threads 16 hg38.fa hg38

# Output: hg38.1.bt2, hg38.2.bt2, hg38.3.bt2, hg38.4.bt2,
#          hg38.rev.1.bt2, hg38.rev.2.bt2
```

### 3. chromap Index (required for Hi-C)

```bash
# chromap 0.2.7 binary (download if not installed)
# Repo: github.com/haowenz/chromap — use v0.2.7 release asset
~/.local/bin/chromap -i -r hg38.fa -o hg38.chromap.idx -t 16
```

### 4. Gene Annotation BED (for visualization tracks)

```bash
# Option A: From GENCODE GTF (recommended — has gene symbols)
# Download GTF:
wget https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_26/gencode.v26.annotation.gtf.gz
gunzip gencode.v26.annotation.gtf.gz

# Extract gene-level BED (symbol as name, strip chr prefix if needed):
awk -v OFS='\t' '$3=="gene" {
  match($0, /gene_name "([^"]+)"/, m);
  match($0, /gene_type "([^"]+)"/, t);
  if (m[1] != "" && t[1] == "protein_coding") {
    chr=$1; sub(/^chr/,"",chr); start=$4-1; end=$5; print chr,start,end,m[1]
  }
}' gencode.v26.annotation.gtf > hg38_genes_symbol.nochr.bed

# Option B: From NCBI Gene Info (simpler, less precise)
wget https://ftp.ncbi.nlm.nih.gov/gene/DATA/GENE_INFO/Mammalia/Homo_sapiens.gene.gz
# Filter by chr and convert to BED (left as exercise)

# Note: For Hi-C visualization with gghic, add chr prefix back:
awk -v OFS='\t' '{print "chr"$1, $2, $3, $4}' hg38_genes_symbol.nochr.bed > hg38_genes_symbol.bed
```

### 5. chrom.sizes (for cooler matrix building — Hi-C)

```bash
# Generate from FASTA:
grep ">" hg38.fa | sed 's/>//' | awk -v OFS='\t' '{print $1, length}' > chrom.sizes
# Or fetch from UCSC:
wget http://hgdownload.cse.ucsc.edu/goldenpath/hg38/bigZips/hg38.chrom.sizes
```

### Quick Checklist

| File | ChIP-seq | ATAC-seq | Hi-C |
|------|:-------:|:--------:|:----:|
| hg38 FASTA | needed (for index build) | needed (for index build) | needed (for chromap index) |
| Bowtie2 index | needed | needed | not needed |
| chromap index | not needed | not needed | needed |
| Gene BED | for tracks | for tracks | for tracks |
| chrom.sizes | not needed | not needed | needed (cooler cload) |

## Privacy

- The skill **never hardcodes credentials**. Server IP/port/username/password are provided by the user at runtime.
- Connection aliases live in the user's `~/.ssh/config`, not in skill files.
- All examples use placeholders like `<SERVER_IP>`, `<USERNAME>`.

## Changelog

- **2026-09-17**: Hi-C full pipeline validated on 2 samples; gghic R visualization added (triangle heatmap + compartment + genes); pitfalls #31-#39 documented. Reference genome preparation tutorial added to README.
