# Test Mode Definition

## Purpose

Verify the entire pipeline has no breakpoints before running formal analysis. Uses real SRA data — downloads from scratch, not pre-built test files.

## How to Run

### Step 1: Get SRR Number

Ask user:
> Provide an SRR number to test, or use recommended `SRR37221781` (MYOD1 ChIP-seq)?
>
> You can also provide an Input control SRR (optional — if skipped, log2 ratio step will be omitted).

### Step 2: Confirm Server

> Server connection alias? (default: use saved alias)

### Step 3: Run Fully Automated

No pauses between steps. Auto-advance through all stages.

### Step 4: Output PASS/FAIL Report

```
═══ Test Mode Report ═══
<SRR> | <SERVER> | <GENOME>

[1/8] Environment check .... PASS/FAIL
      bowtie2 ✓, samtools ✓, Genrich ✓, deepTools ✓
[2/8] Data download ......... PASS/FAIL (<method>, <size>, <time>)
[3/8] Format conversion ...... PASS/FAIL (fasterq-dump, 2× <size> fastq)
[4/8] QC & trimming .......... PASS/FAIL (fastp, R1=R2=<count>)
[5/8] Bowtie2 alignment ...... PASS/FAIL (<rate>% alignment)
[6/8] Deduplication .......... PASS/FAIL (<count> reads, <rate>% dup)
[7/8] Peak calling .......... PASS/FAIL (<count> peaks, <tool>)
[8/8] Visualization .......... PASS/FAIL (TSS heatmap generated)

Summary: X/8 PASS — Pipeline ready for formal analysis
        (or: Y steps FAILED — see details below)
```

## PASS/FAIL Criteria

| Step | PASS Criteria |
|------|---------------|
| Environment | All critical tools available (bowtie2, samtools, peak caller, deepTools) |
| Download | File exists, size > 1GB, vdb-validate passes |
| Conversion | R1 and R2 fastq files exist, both > 0 bytes |
| QC | R1 read count == R2 read count |
| Alignment | Alignment rate > 50% (lower bar for test mode) |
| Dedup | Deduplication completes without error; dup rate < 50% |
| Peak calling | Produces a peak file (even 1 peak is PASS) |
| Visualization | At least 1 image file generated |

## Differences from Formal Mode

| Aspect | Test Mode | Formal Mode |
|--------|-----------|-------------|
| Samples | 1 (ChIP only or ChIP + 1 Input) | All samples |
| Step interaction | Auto-advance, no pause | Pause after each step |
| QC strictness | Default params | User confirms params |
| Peak threshold | Default (verify it runs) | User confirms threshold |
| Visualization | 1 TSS heatmap | Full suite (8+ images) |
| Failure handling | Immediately stop, report | Offer fallback options |
| Output | PASS/FAIL report | Complete analysis results |

## Recommended Test SRRs

| SRR | Type | TF/Mark | Cell | Genome | Size | Expected Peaks |
|-----|------|---------|------|--------|------|----------------|
| SRR37221781 | ChIP-seq | MYOD1 | LHCN-M2 | hg38 | ~5.2GB | ~81 (Genrich, q>2.0) |
| SRR37221777 | Input | - | LHCN-M2 | hg38 | ~5.5GB | - (control) |

## When Test Mode Fails

If a step fails during test mode:
1. Stop immediately
2. Report which step failed and the error
3. Show the log tail
4. Suggest fix based on `common/fallback.md` and `common/pitfalls.md`
5. Ask user: fix and retry, or skip to formal mode?

Test mode failure is useful — it reveals problems before committing to a full formal run.
