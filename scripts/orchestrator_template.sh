#!/bin/bash
# =============================================================================
# Orchestrator Template — Parallel multi-sample pipeline (Layer 1)
# =============================================================================
# Master/worker design. ALL samples run in parallel by default (no question,
# no knob — this is the standard community behavior, Snakemake-style).
#
#   master mode: bash orchestrator.sh
#     - starts prefetch for every sample up front (parallel downloads)
#     - spawns one worker per sample (nohup, own subdir {SRR}/)
#     - monitors workers; writes FAILED to master status on FIRST failure
#       (wakes the main-agent watcher fast) then exits — surviving workers
#       keep running; agent repairs the failed sample and relaunches master
#     - when all workers done -> MultiQC aggregate -> ALL_DONE
#   worker mode: bash orchestrator.sh --worker <SRR>  (invoked by master)
#     - runs stages 0-9 inside {SRR}/ with own flags/ logs/ status
#
# Core contract (see references/common/long-task.md):
#   - Master status file (WORKDIR/pipeline_status.txt) is what the Layer-2
#     watcher greps: terminal lines FAILED / ALL_DONE only appear there
#   - Per-sample state in {SRR}/pipeline_status.txt + {SRR}/flags/
#   - Self-heals known failures; fails fast, never continues on bad data
#   - Skips stages whose flags exist (resume after repair)
#   - THREADS is PER SAMPLE: total CPU = THREADS x N samples. Check cores
#     and shared-server etiquette before cranking N high.
# =============================================================================

set -o pipefail

# ---- Agent fills these in at deployment time --------------------------------
SAMPLES=()                # e.g. ("SRR27019541" "SRR27019539")
ANALYSIS_TYPE=""          # chip-seq | atac-seq
INDEX=""                  # bowtie2 index prefix, absolute path
THREADS=16                # PER-SAMPLE threads; total = THREADS * len(SAMPLES)
WORKDIR=""                # absolute path on server
MT_CHROM=chrM             # ATAC only; Ensembl naming uses MT
# ChIP-seq specific: fill CHIP_SRR="" INPUT_SRR="" and merge-peak logic if needed

# =============================================================================
# WORKER MODE — one sample, all stages (cwd = WORKDIR/{SRR})
# =============================================================================
if [ "$1" = "--worker" ]; then
  SRR="$2"
  cd "$WORKDIR/$SRR" || { echo "FAILED init cannot cd $WORKDIR/$SRR" > pipeline_status.txt; exit 1; }
  mkdir -p flags logs

  STATUS_FILE=pipeline_status.txt
  log()  { echo "$(date '+%F %T') $1 $2 $3" >> "$STATUS_FILE"; }
  done_flag() { touch "flags/$1.done"; }
  have_flag() { [ -f "flags/$1.done" ]; }
  fail() { log FAILED "$1" "$2 (log: logs/$1.log)"; exit 1; }

  check_disk() {
    local need_gb=$1
    local free_kb
    free_kb=$(df -k "$WORKDIR" | awk 'NR==2 {print $4}')
    if [ "$free_kb" -lt $((need_gb * 1024 * 1024)) ]; then
      log FAILED "$2" "disk low: ${free_kb}KB free, need ${need_gb}GB"
      exit 1
    fi
  }

  log RUNNING init "SRR=$SRR type=$ANALYSIS_TYPE index=$INDEX threads=$THREADS"

  # ---------------------------------------------------------------------------
  # Stage 0: WAIT-FOR-DOWNLOAD (self-healing: restarts prefetch up to 3x)
  # ---------------------------------------------------------------------------
  if ! have_flag download; then
    log RUNNING download "waiting for $SRR.sra"
    retries=0
    while [ $retries -lt 3 ]; do
      while true; do
        [ -f "${SRR}.sra" ] && break
        [ -f "${SRR}.sra.tmp" ] && break
        sleep 60
      done
      while true; do
        if [ -f "${SRR}.sra" ] && [ ! -f "${SRR}.sra.tmp" ]; then
          if vdb-validate "${SRR}.sra" >logs/download_validate.log 2>&1; then
            break 2
          else
            log RUNNING download "sra exists but invalid, redownloading"
            rm -f "${SRR}.sra" "${SRR}.sra.tmp"
          fi
        fi
        cur=$(du -sm "${SRR}.sra.tmp" 2>/dev/null | awk '{print $1}')
        sleep 60
        new=$(du -sm "${SRR}.sra.tmp" 2>/dev/null | awk '{print $1}')
        [ "$cur" = "$new" ] && [ "$cur" != "" ] && break
      done
      retries=$((retries + 1))
      log RUNNING download "restart attempt $retries"
      pkill -f "prefetch.*$SRR" 2>/dev/null
      sleep 5
      rm -f "${SRR}.sra.tmp" "${SRR}.sra.lock" "${SRR}.sra.prf"
      nohup prefetch "$SRR" --max-size 100G -o "$WORKDIR/$SRR/${SRR}.sra" > "logs/download_retry${retries}.log" 2>&1 &
    done
    [ $retries -ge 3 ] && fail download "prefetch failed after 3 retries"
    sz=$(du -h "${SRR}.sra" | awk '{print $1}')
    log DONE download "$SRR.sra $sz"
    done_flag download
  fi

  # ---------------------------------------------------------------------------
  # Stage 1: SRA -> FASTQ (fasterq-dump + pigz)
  # ---------------------------------------------------------------------------
  if ! have_flag convert; then
    check_disk 40 convert
    log RUNNING convert fasterq-dump
    if fasterq-dump "${SRR}.sra" -O . -e "$THREADS" --include-technical \
         > logs/convert.log 2>&1; then
      for f in "${SRR}"_1.fastq "${SRR}"_2.fastq; do pigz -p "$THREADS" "$f" 2>>logs/convert.log; done
      r1=$(zcat "${SRR}"_1.fastq.gz | head -40000000 | wc -l)
      r2=$(zcat "${SRR}"_2.fastq.gz | head -40000000 | wc -l)
      [ "$r1" != "$r2" ] && fail convert "R1/R2 line count mismatch ($r1 vs $r2)"
      log DONE convert "fastq gz done R1L~$r1"
      done_flag convert
    else
      fail convert "fasterq-dump exit non-zero"
    fi
  fi

  # ---------------------------------------------------------------------------
  # Stage 2: FastQC on raw reads
  # ---------------------------------------------------------------------------
  if ! have_flag fastqc_raw; then
    log RUNNING fastqc_raw "fastqc"
    fastqc -t "$THREADS" -q "${SRR}"_1.fastq.gz "${SRR}"_2.fastq.gz \
      > logs/fastqc_raw.log 2>&1 || fail fastqc_raw "fastqc exit non-zero"
    log DONE fastqc_raw "raw reads"
    done_flag fastqc_raw
  fi

  # ---------------------------------------------------------------------------
  # Stage 3: Adapter trimming (fastp) — ATAC: length_required 15
  # ---------------------------------------------------------------------------
  if ! have_flag fastp; then
    log RUNNING fastp "trimming"
    # ATAC-seq MUST use --length_required 15 (short NFR fragments are real signal)
    if fastp -i "${SRR}"_1.fastq.gz -I "${SRR}"_2.fastq.gz \
         -o "${SRR}"_1.clean.fq.gz -O "${SRR}"_2.clean.fq.gz \
         --detect_adapter_for_pe --length_required 15 --thread "$THREADS" \
         --html "${SRR}"_fastp.html --json "${SRR}"_fastp.json \
         > logs/fastp.log 2>&1; then
      r1=$(zcat "${SRR}"_1.clean.fq.gz | head -40000000 | wc -l)
      r2=$(zcat "${SRR}"_2.clean.fq.gz | head -40000000 | wc -l)
      [ "$r1" != "$r2" ] && fail fastp "clean R1/R2 count mismatch ($r1 vs $r2)"
      log DONE fastp "clean R1L~$r1"
      done_flag fastp
    else
      fail fastp "fastp exit non-zero"
    fi
  fi

  # ---------------------------------------------------------------------------
  # Stage 4: Alignment (Bowtie2) — ATAC: -X 2000 --no-mixed --no-discordant
  # ---------------------------------------------------------------------------
  if ! have_flag align; then
    check_disk 60 align
    log RUNNING align "bowtie2 -> sorted bam"
    if bowtie2 -x "$INDEX" \
         -1 "${SRR}"_1.clean.fq.gz -2 "${SRR}"_2.clean.fq.gz \
         -p "$THREADS" --very-sensitive -X 2000 --no-mixed --no-discordant \
         2> logs/bowtie2.log \
         | samtools sort -@ "$THREADS" -o "${SRR}".sorted.bam -; then
      samtools index "${SRR}".sorted.bam
      rate=$(grep "overall alignment rate" logs/bowtie2.log | awk '{print $1}')
      log DONE align "rate $rate"
      done_flag align
    else
      fail align "bowtie2 exit non-zero"
    fi
  fi

  # ---------------------------------------------------------------------------
  # Stage 5: Mitochondrial filtering (ATAC-specific, MANDATORY)
  # ---------------------------------------------------------------------------
  if ! have_flag mtfilter; then
    log RUNNING mtfilter "removing $MT_CHROM"
    before=$(samtools view -c "${SRR}".sorted.bam)
    samtools view -@ "$THREADS" -b -v "$MT_CHROM" "${SRR}".sorted.bam \
      > "${SRR}".nochrM.bam 2> logs/mtfilter.log || fail mtfilter "samtools view exit non-zero"
    after=$(samtools view -c "${SRR}".nochrM.bam)
    samtools sort -@ "$THREADS" "${SRR}".nochrM.bam -o "${SRR}".nochrM.sorted.bam
    samtools index "${SRR}".nochrM.sorted.bam
    rm -f "${SRR}".nochrM.bam
    mt_pct=$(awk "BEGIN{printf \"%.1f\", ($before-$after)*100/$before}")
    log DONE mtfilter "mtDNA ${mt_pct}% ($before -> $after)"
    done_flag mtfilter
  fi

  # ---------------------------------------------------------------------------
  # Stage 6: Deduplication (samtools markdup pipeline)
  # ---------------------------------------------------------------------------
  if ! have_flag dedup; then
    log RUNNING dedup "markdup"
    samtools sort -n -@ "$THREADS" "${SRR}".nochrM.sorted.bam -o "${SRR}".nsort.bam
    samtools fixmate -m -@ "$THREADS" "${SRR}".nsort.bam "${SRR}".fixmate.bam
    samtools sort -@ "$THREADS" "${SRR}".fixmate.bam -o "${SRR}".csort.bam
    if samtools markdup -@ "$THREADS" -r "${SRR}".csort.bam "${SRR}".dedup.bam \
         2> logs/dedup.log; then
      rm -f "${SRR}".nsort.bam "${SRR}".fixmate.bam "${SRR}".csort.bam
      n=$(samtools view -c "${SRR}".dedup.bam)
      log DONE dedup "$n reads after dedup"
      done_flag dedup
    else
      fail dedup "markdup exit non-zero"
    fi
  fi

  # ---------------------------------------------------------------------------
  # Stage 7: Tn5 offset correction (ATAC-specific)
  # ---------------------------------------------------------------------------
  if ! have_flag tn5shift; then
    log RUNNING tn5shift "alignmentSieve --ATAC"
    if alignmentSieve -b "${SRR}".dedup.bam --shift 4 -4 -o "${SRR}".shifted.bam \
         -p "$THREADS" --ATAC > logs/tn5shift.log 2>&1; then
      samtools index "${SRR}".shifted.bam
      log DONE tn5shift "shifted bam"
      done_flag tn5shift
    else
      fail tn5shift "alignmentSieve exit non-zero"
    fi
  fi

  # ---------------------------------------------------------------------------
  # Stage 8: Peak calling (Genrich --atacpair) — output has SRR prefix
  # ---------------------------------------------------------------------------
  if ! have_flag peaks; then
    log RUNNING peaks "Genrich --atacpair"
    samtools sort -n -@ "$THREADS" "${SRR}".shifted.bam -o "${SRR}".shifted.qname.bam
    if Genrich -t "${SRR}".shifted.qname.bam -r -e -v --atacpair -q 2.0 \
         -o "${SRR}_peaks.narrowPeak" > logs/peaks.log 2>&1; then
      npeaks=$(wc -l < "${SRR}_peaks.narrowPeak")
      log DONE peaks "$npeaks peaks"
      done_flag peaks
    else
      fail peaks "Genrich exit non-zero (check logs/peaks.log)"
    fi
  fi

  # ---------------------------------------------------------------------------
  # Stage 9: Signal track (MultiQC runs in master after ALL samples)
  # ---------------------------------------------------------------------------
  if ! have_flag tracks; then
    log RUNNING tracks "bamCoverage RPM"
    bamCoverage -b "${SRR}".dedup.bam -o "${SRR}"_RPM.bw \
      --binSize 10 --normalizeUsing RPM \
      --effectiveGenomeSize 2913022398 -p "$THREADS" \
      > logs/tracks.log 2>&1 || fail tracks "bamCoverage exit non-zero"
    log DONE tracks "${SRR}_RPM.bw"
    done_flag tracks
  fi

  # worker terminal state
  touch flags/all.done
  log ALL_DONE worker "$SRR complete"
  echo "WORKER ALL DONE — $SRR at $(date '+%F %T')"
  exit 0
fi

# =============================================================================
# MASTER MODE — spawn workers, monitor, aggregate
# =============================================================================
cd "$WORKDIR" || { echo "FAILED init cannot cd $WORKDIR" > pipeline_status.txt; exit 1; }
mkdir -p flags logs

STATUS=pipeline_status.txt
mlog() { echo "$(date '+%F %T') $1 $2 $3" >> "$STATUS"; }

mlog RUNNING init "parallel pipeline samples=[${SAMPLES[*]}] type=$ANALYSIS_TYPE threads/sample=$THREADS"

# --- start all downloads up front (parallel), if not already present/p-running
for SRR in "${SAMPLES[@]}"; do
  mkdir -p "$SRR"/flags "$SRR"/logs
  if [ ! -f "$SRR/${SRR}.sra" ] && ! pgrep -f "prefetch.*$SRR" >/dev/null 2>&1; then
    nohup prefetch "$SRR" --max-size 100G -o "$WORKDIR/$SRR/${SRR}.sra" \
      > "$SRR/logs/download.log" 2>&1 &
    mlog RUNNING download "$SRR prefetch started"
  fi
done

# --- spawn one worker per sample (skip if already running or fully done)
for SRR in "${SAMPLES[@]}"; do
  if [ -f "$SRR/flags/all.done" ]; then
    mlog DONE sample "$SRR already complete (flags)"
    continue
  fi
  pid=""
  [ -f "$SRR/worker.pid" ] && pid=$(cat "$SRR/worker.pid" 2>/dev/null)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    mlog RUNNING worker "$SRR already running (pid $pid)"
    continue
  fi
  nohup bash "$0" --worker "$SRR" > "$SRR/worker.log" 2>&1 &
  echo $! > "$SRR/worker.pid"
  mlog RUNNING worker "$SRR spawned (pid $!)"
done

# --- monitor: fail fast on first failure, wait for full completion otherwise
while true; do
  failed=""
  complete=0
  for SRR in "${SAMPLES[@]}"; do
    if grep -q FAILED "$SRR/pipeline_status.txt" 2>/dev/null; then
      stage=$(grep FAILED "$SRR/pipeline_status.txt" | tail -1 | awk '{print $3, $4}')
      mlog FAILED sample "$SRR at: $stage (detail: $SRR/pipeline_status.txt)"
      failed=1
      break
    fi
    [ -f "$SRR/flags/all.done" ] && complete=$((complete + 1))
  done
  if [ -n "$failed" ]; then
    # surviving workers keep running server-side; repair + relaunch master to resume
    echo "MASTER EXIT 1 — at least one sample FAILED at $(date '+%F %T')"
    exit 1
  fi
  [ "$complete" -eq "${#SAMPLES[@]}" ] && break

  # stall detection: worker pid dead, no terminal state, no FAILED line
  for SRR in "${SAMPLES[@]}"; do
    if [ ! -f "$SRR/flags/all.done" ] && [ -f "$SRR/worker.pid" ]; then
      wpid=$(cat "$SRR/worker.pid" 2>/dev/null)
      if [ -n "$wpid" ] && ! kill -0 "$wpid" 2>/dev/null \
         && ! grep -q FAILED "$SRR/pipeline_status.txt" 2>/dev/null \
         && ! grep -q "ALL_DONE" "$SRR/pipeline_status.txt" 2>/dev/null; then
        mlog FAILED sample "$SRR worker died without terminal state (see $SRR/worker.log)"
        echo "MASTER EXIT 1 — $SRR worker stalled at $(date '+%F %T')"
        exit 1
      fi
    fi
  done
  sleep 30
done

# --- aggregate QC across all samples
if [ ! -f flags/multiqc.done ]; then
  mlog RUNNING multiqc "aggregating ${#SAMPLES[@]} samples"
  export PATH="$HOME/.local/bin:$PATH"
  multiqc . -o multiqc_out --force > logs/multiqc.log 2>&1 \
    || { mlog FAILED multiqc "exit non-zero"; exit 1; }
  mlog DONE multiqc "multiqc_out/"
  touch flags/multiqc.done
fi

for SRR in "${SAMPLES[@]}"; do
  n=$(wc -l < "$SRR/${SRR}_peaks.narrowPeak" 2>/dev/null || echo 0)
  mlog DONE sample "$SRR peaks=$n"
done
mlog ALL_DONE pipeline "all ${#SAMPLES[@]} samples complete"
echo "ALL DONE — ${SAMPLES[*]} at $(date '+%F %T')"
