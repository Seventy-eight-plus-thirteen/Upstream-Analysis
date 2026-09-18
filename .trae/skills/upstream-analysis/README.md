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

## Privacy

- The skill **never hardcodes credentials**. Server IP/port/username/password are provided by the user at runtime.
- Connection aliases live in the user's `~/.ssh/config`, not in skill files.
- All examples use placeholders like `<SERVER_IP>`, `<USERNAME>`.

## Changelog

- **2026-09-17**: ATAC-seq full pipeline validated on 2 real samples (H3WT/K27M); docs updated for samtools 1.13 mtDNA filter, Genrich `-j` mode, BPM normalization, `--sensitive` alignment.
