# ATAC-seq Test Mode

## Purpose

Verify the ATAC-seq pipeline has no breakpoints. Uses real SRA data from GEO.

## Recommended Test SRRs

| SRR | Source | Type | Cell | Genome | Size | 
|-----|--------|------|------|--------|------|
| SRR27019541 | GSE249164 | ATAC-seq H3WT | NSC-iPSC | hg38 | ~4.6GB |
| SRR27019539 | GSE249164 | ATAC-seq K27M | NSC-iPSC | hg38 | ~7.8GB |

These are currently being downloaded (as of 2026-09-16).

## PASS/FAIL Criteria

| Step | PASS Criteria |
|------|---------------|
| Environment | bowtie2, samtools, Genrich/alignmentSieve, deepTools available |
| Download | File exists, size matches metadata |
| Conversion | R1 and R2 fastq files exist |
| QC | R1 read count == R2 read count; insert size shows periodicity |
| Alignment | Rate > 60% (lower than ChIP due to mtDNA) |
| mtDNA filter | mtDNA fraction 5-50% (normal range) |
| Dedup | Completes without error |
| Tn5 shift | BAM created, indexable |
| Peak calling | > 1,000 peaks (ATAC has many more peaks than ChIP) |
| TSS enrichment | Score > 3 |
| Visualization | At least 1 image generated |

## Differences from ChIP-seq Test Mode

| Aspect | ChIP-seq | ATAC-seq |
|--------|----------|----------|
| Samples needed | 2 (ChIP + Input) | 1 (no Input) |
| Extra steps | 0 | mtDNA filter + Tn5 shift |
| Expected peaks | ~81 (TF) | ~50,000-200,000 |
| Alignment rate expectation | > 80% | > 60% (pre-mtDNA filter) |
| QC metric | N/A | TSS enrichment + fragment distribution |
