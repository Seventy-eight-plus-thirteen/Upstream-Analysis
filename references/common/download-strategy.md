# Data Download Fallback Decision Tree

## Download Strategy (3-Level Fallback)

```
Start: User provides SRR number
  │
  ├─ Level 1: Aspera (NCBI, port 33001)
  │    Command: ascp -i <aspera_key> -k 2 -QT -l 500M anonftp@ftp.ncbi.nlm.nih.gov:sra/sra-instant/reads/ByRun/sra/SRR/<SRR_PREFIX>/<SRR>/<SRR>.sra ./
  │    Test port: nc -z -w5 ftp.ncbi.nlm.nih.gov 33001 && echo "OPEN" || echo "BLOCKED"
  │    │
  │    ├─ Port blocked? → Level 2
  │    ├─ Auth fails? → Level 2
  │    └─ Success → proceed to integrity check
  │
  ├─ Level 2: ENA Aspera
  │    Command: ascp -QT -l 500M era-fasp@fasp.sra.ebi.ac.uk:/vol1/fastq/<SRR_PREFIX>/<SRR>/<SRR>_1.fastq.gz ./
  │    Note: ENA may not have all samples; check availability first
  │    │
  │    ├─ Auth fails / no file? → Level 3
  │    └─ Success → proceed
  │
  └─ Level 3: prefetch (HTTPS) ← MOST RELIABLE
       Command: prefetch -p <SRR> -o <SRR>.sra
       Features: supports resume, runs in background
       │
       ├─ Download too slow? → Try kingfisher as alternative
       │    Command: kingfisher get -r <SRR> -m ena-ascp ena-ftp prefetch
       └─ Success → proceed
```

## Key Lessons Learned

1. **Aspera ports are often blocked** by institutional firewalls (33001, 33002)
2. **ENA doesn't host all SRA samples** — check before trying
3. **prefetch via HTTPS is the most reliable** fallback, though slower
4. **Always download in background** with `nohup` to survive SSH disconnections
5. **Never delete intermediate files** until the next step succeeds

## Background Download Pattern

```bash
# Start download in background
nohup prefetch -p <SRR> -o <SRR>.sra > download_<SRR>.log 2>&1 &
echo "PID: $!"

# Check progress
ls -lh <SRR>.sra  # file grows over time

# Verify completion
ls -lh <SRR>.sra  # should match expected size from GEO metadata
```

## Integrity Check After Download

```bash
# 1. Check file size against GEO metadata
ls -lh <SRR>.sra

# 2. Verify SRA file integrity
vdb-validate <SRR>.sra

# 3. Quick peek at read count
fastq-dump --stdout -X 10 <SRR>.sra | head -40
```

## File Cleanup Rules

- **Never delete** the SRA file until fastq conversion is verified
- **Never delete** fastq files until alignment is verified
- **Never delete** raw BAM until deduplication is verified
- Only clean up after user explicitly confirms the step succeeded
- When cleaning, list files and sizes first, ask user to confirm deletion

## Polling for Long Downloads

For large files (>2GB), set up periodic polling:

```bash
# Poll every 30 minutes
ssh <ALIAS> 'ls -lh <SRR>.sra 2>/dev/null && echo "---" && tail -5 download_<SRR>.log'
```

Or use the Schedule tool to create a recurring check every 30 minutes. Stop polling once file size stops growing and matches expected size.
