# Long-Task Execution: 3-Layer Architecture

## The Problem This Solves

Agent sessions are ephemeral. A sequencing pipeline runs for hours. If execution depends on the agent session staying alive (or the user relaying messages), the pipeline stalls the moment either goes away.

**Anti-pattern** (do NOT use): agent sends one command per stage, waits for user to relay polling reports between stages. The workflow dies whenever the user walks away.

## The 3-Layer Architecture

```
Layer 1: Server-side Orchestrator (self-driving + self-healing)
Layer 2: Main-session Watcher (bridge back to the agent's context)
Layer 3: Schedule Polling (human-facing progress reports only)
```

### Layer 1: Server-side Orchestrator

A single bash script deployed to the server via `nohup`. The script is the executor; the agent only deploys and monitors it. **Multi-sample runs are parallel by default (all samples start together, Snakemake-style). No parallelism question in Pre-Flight — it's the standard behavior.**

**Master/worker design** (`scripts/orchestrator_template.sh`):

```
master (bash orchestrator.sh)
  ├─ starts prefetch for ALL samples up front        # parallel downloads
  ├─ spawns one worker per sample (nohup + pid file)
  │    each worker: cd {SRR}/ with own flags/ logs/ pipeline_status.txt
  ├─ monitors every 30s:
  │    first FAILED   -> write FAILED to master status, exit 1  (fast wake)
  │    worker stalled -> same                                        (fast wake)
  │    all all.done   -> MultiQC aggregate -> ALL_DONE, exit 0
  └─ relaunching master is safe & idempotent:
       completed samples skip via flags/all.done
       running workers detected via worker.pid (no double-spawn)
```

**Two status files, one watcher.** The Layer-2 watcher greps the MASTER `pipeline_status.txt` (in WORKDIR root). Per-sample detail lives in `{SRR}/pipeline_status.txt`. On FAILED: surviving workers keep running server-side; the agent repairs the failed sample (its flags preserve progress) and relaunches master, which resumes cleanly.

**Core mechanics:**

1. **Status file** (`pipeline_status.txt`): every stage transition appends a line:
   ```
   2026-09-17 09:15:32 DONE    download      SRR27019539 7.8GB
   2026-09-17 09:42:10 RUNNING fasterq-dump
   2026-09-17 10:01:55 DONE    fastp         R1=R2=94.2M
   2026-09-17 10:05:12 FAILED  bowtie2       see bowtie2.err
   ```
   Terminal states: `ALL_DONE` line on full success, `FAILED` line on any unrecoverable error.

2. **Flag files**: one flag per completed stage (`flags/stageN.done`). Enables resume: on restart, the orchestrator skips stages whose flags exist.

3. **Built-in self-healing** (extracted from `pitfalls.md`):
   - Download stalled/interrupted → restart prefetch automatically (up to 3 retries)
   - Genrich "not sorted by queryname" → re-run `samtools sort -n` then retry
   - Disk space check before each stage; abort with FAILED if < 20GB free
   - R1/R2 count mismatch after fastp → abort with FAILED (data corruption, needs re-download; do NOT proceed)

4. **Fail fast, no garbage**: on any validation failure, write FAILED and exit. Never continue a pipeline on bad data.

5. **Mission file** (`mission.md`): written at deployment time. Contains goal, all parameters, expected outputs, and takeover instructions. Enables ANY new agent session (even after full session loss) to resume: read mission.md → read pipeline_status.txt → check flags → resume or repair.

### Layer 2: Main-session Watcher

The bridge that returns control to the agent's full context automatically.

The main session launches ONE background Shell job:

```bash
ssh <ALIAS> 'cd <WORKDIR> && while true; do
  grep -q "FAILED"   pipeline_status.txt 2>/dev/null && exit 1
  grep -q "ALL_DONE" pipeline_status.txt 2>/dev/null && exit 0
  sleep 60
done'
```

When this job exits, the harness delivers a `task_notification` that **wakes the main session**:

- exit code 0 → pipeline complete: fetch results, generate final report for user
- exit code 1 → pipeline failed: read status file, locate failed stage, repair in-context, relaunch orchestrator (flags make it resume from failure point)
- network drop → ssh dies → job exits (non-zero) → wake → verify actual server state → relaunch watcher (do NOT assume failure; the orchestrator keeps running server-side regardless)

**Key invariant**: the watcher is only a tripwire, never an executor. All real work lives in Layer 1. Watcher death never affects pipeline progress.

### Layer 3: Schedule Polling

A cron task that runs every 30 min and only REPORTS progress to the user (reads status file, shows current stage + key metrics). It has no control authority. If it detects FAILED, it tells the user "main session will handle / already handled by Layer 2" — because Layer 2 handles it automatically.

## Deployment Procedure (Autopilot Mode)

1. Pre-flight checklist collects ALL decisions upfront (see SKILL.md). Parallelism is NOT asked — all samples run in parallel by default.
2. Size threads: `THREADS` is PER SAMPLE, total = `THREADS × N samples`. E.g. 72-core server, 6 samples → set THREADS=8 (48 cores total, leaves headroom). On a shared server check `uptime`/`top` first and stay conservative; disk I/O (not CPU) is usually the real bottleneck for fasterq-dump/pigz/bowtie2.
3. Agent generates a customized orchestrator from `scripts/orchestrator_template.sh` + the analysis-type `params.md` (fills `SAMPLES`, `INDEX`, `THREADS`, `WORKDIR`, `MT_CHROM`).
4. Write `mission.md` alongside the script.
5. Deploy: `scp orchestrator.sh mission.md <ALIAS>:<WORKDIR>/`
6. Launch: `ssh <ALIAS> 'cd <WORKDIR> && nohup bash orchestrator.sh > orchestrator.log 2>&1 &'`
7. Launch watcher as background job in the main session (command above) — it greps the MASTER status file.
8. Update/create the Schedule polling task to read the master `pipeline_status.txt` (plus per-sample lines for detail).
9. Report to user: what's running, how progress will arrive, that they can walk away.

## Takeover Protocol (for any new session)

When resuming a pipeline with no prior context:

```
1. Read <WORKDIR>/mission.md          # what, params, expected results
2. Read <WORKDIR>/pipeline_status.txt # master status: overall state
3. For detail: cat <WORKDIR>/<SRR>/pipeline_status.txt (per-sample stage)
4. ls <WORKDIR>/<SRR>/flags/          # which stages are provably done per sample
5. If FAILED: read the failing stage's log → repair root cause → relaunch master
      (surviving workers unaffected; completed samples skip via flags)
6. If RUNNING: launch a watcher (Layer 2) and report status
7. If ALL_DONE: fetch results and report
```

## Sizing the Layers

| Task duration | Layer 1 | Layer 2 watcher | Layer 3 polling |
|---------------|---------|-----------------|-----------------|
| < 10 min | direct execution, no orchestrator | n/a | n/a |
| 10 min – 2 h | orchestrator | watcher | optional |
| > 2 h (downloads, full pipelines) | orchestrator | watcher | every 30 min |

## Parallel Sizing Cheat Sheet

All samples run in parallel — the agent's only sizing decision is `THREADS` per sample:

| Server cores | 2 samples | 4 samples | 6 samples | 8+ samples |
|--------------|-----------|-----------|-----------|------------|
| 32 | 12 | 6 | 4 | use a queue/serial batches |
| 72 | 16 | 14 | 10 | 8 |
| 128 | 16 | 16 | 16 | 14 |

Rules of thumb: cap total at ~80% of cores on a dedicated server, ~50% on a shared one; on HDD-backed storage 4+ concurrent fasterq-dump/pigz stages will thrash — if observed, halve THREADS rather than sample count (flags make re-runs cheap).
