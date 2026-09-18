---
name: "upstream-analysis"
description: "Sequencing upstream analysis pipeline (ChIP-seq/RNA-seq/ATAC-seq). Invoke when user types /upstream-analysis, wants to run sequencing data analysis from download to visualization on a remote server."
---

# Upstream Analysis Pipeline

## Trigger

User types `/upstream-analysis`.

## Interaction Engine

**CRITICAL: At EVERY step marked with [ASK], you MUST use the `AskUserQuestion` tool to present clickable options to the user. Never output plain text options and wait for the user to type back. Always use `AskUserQuestion` with properly formatted questions and options.**

**CRITICAL: Use the "Pre-Flight Checklist" pattern (see below) to batch ALL questions upfront before starting any execution. This minimizes interruptions during long-running tasks. Only pause during execution for unrecoverable errors or unexpected decisions.**

## Pre-Flight Checklist (ONE-TIME BATCH QUESTIONS)

Before ANY execution starts, collect ALL decisions in a single batch of `AskUserQuestion` calls. Ask up to 4 questions at once, then ask the next batch if more remain. DO NOT start any download, alignment, or processing until all questions are answered.

### Batch 1 (Core Setup — ask simultaneously)

[ASK 1] Mode selection:
- question: "你想用哪种模式运行？"
- header: "运行模式"
- options:
  - "自动驾驶模式 (推荐)" / "逐步确认模式" / "测试模式" / "仅环境检查"

**自动驾驶模式 (Autopilot)** — the default for pipelines expected to run > 30 min:
- After Pre-Flight, generate a server-side orchestrator script from `scripts/orchestrator_template.sh`, deploy via scp, launch via nohup
- **All samples run in parallel by default** (master/worker design, Snakemake-style). Do NOT ask the user about parallelism — it is the fixed default. The agent only sizes `THREADS` per sample (see the Parallel Sizing Cheat Sheet in `references/common/long-task.md`)
- The script self-drives ALL stages server-side and self-heals known failures (see `references/common/long-task.md`)
- Main session launches a background watcher: `ssh <ALIAS> 'while true; do grep -q FAILED <STATUS> && exit 1; grep -q ALL_DONE <STATUS> && exit 0; sleep 60; done'` — when it exits, the task_notification wakes the main session to handle failure or report completion
- Schedule polling is ONLY for human-facing progress reports
- User can walk away; even if the TRAE session is lost, any new session resumes via mission.md + pipeline_status.txt + flags/

**逐步确认模式** — for teaching/first-time runs: report after each stage, wait for confirmation.

[ASK 2] Analysis type:
- question: "你想做什么类型的分析？"
- header: "分析类型"
- options:
  - "ChIP-seq" / "ATAC-seq" / "Hi-C" / "RNA-seq" / "自定义"

[ASK 3] Server connection:
- question: "如何连接服务器？"
- header: "服务器"
- options:
  - "使用已保存别名" / "新服务器"

[ASK 4] Download strategy preference:
- question: "下载方式偏好？（Aspera端口被封时自动降级）"
- header: "下载方式"
- options:
  - "Aspera优先→prefetch降级 (推荐)" / "直接用prefetch" / "aria2c多线程"

### Batch 2 (Data & Parameters — ask simultaneously, after Batch 1)

[ASK 5] Data source:
- question: "数据来源是哪里？"
- header: "数据来源"
- options:
  - "GEO/SRA (提供metadata)" / "本地文件" / "测试数据"

[ASK 6] Reference genome (populate from server scan):
- question: "选择参考基因组？"
- header: "基因组"
- options: (dynamic from scan)

[ASK 7] Peak calling tool (if applicable):
- question: "Peak calling 工具偏好？"
- header: "Peak caller"
- options:
  - "MACS2 (如果已装)" / "Genrich (已有)" / "自动选择"

[ASK 8] Polling preference:
- question: "长任务是否设置30分钟轮询？"
- header: "轮询"
- options:
  - "是，每30分钟检查 (推荐)" / "否，我手动查看"

### Batch 3 (Optional — only for formal mode)

[ASK 9] File cleanup preference:
- question: "中间文件何时清理？"
- header: "清理策略"
- options:
  - "每步验证后自动清理 (推荐)" / "全部完成后再清理" / "不清理，保留所有文件"

[ASK 10] Visualization scope:
- question: "可视化范围？"
- header: "可视化"
- options:
  - "全套 (热图+曲线+轨道截图)" / "仅热图和曲线" / "仅基础图表"

### After Pre-Flight Checklist

Once ALL questions are answered:
1. Summarize the complete configuration to the user in a single message
2. Start execution immediately
3. During execution: only pause for unrecoverable errors or unexpected decisions
4. Report progress at each stage completion (but do NOT wait for confirmation in test mode)
5. In formal mode: only pause if something unexpected happens (error, abnormal result)

#### Test Mode

- User provides an SRR number (or use recommended `SRR37221781` — MYOD1 ChIP-seq)
- **Fully automated**: download -> convert -> QC -> align -> dedup -> peak calling -> visualization
- No pause between steps; output brief status after each
- If any step fails: immediately pause and report
- Final output: PASS/FAIL report with per-step status table

#### Formal Mode

- Step-by-step, but only pause for: errors, abnormal results, or user-specified checkpoints
- Input control required for ChIP-seq
- Strict QC and parameter validation

#### Environment Check Only

- Scan server for installed tools, conda envs, disk space
- Report missing tools with install/fix suggestions

---

## Execution Phase (After Pre-Flight Checklist)

### Phase 1: Environment Self-Check

Scan server for all required dependencies. Read `references/common/env-checklist.md`.
- Run `scripts/check_env.sh` on server
- Report missing tools; attempt auto-install for critical ones (with user's prior consent from Pre-Flight)
- Scan for existing reference genome indexes

### Phase 2: Data Collection

If GEO/SRA: parse user-provided metadata table, confirm sample grouping.
If local: verify file paths and integrity.
Download using chosen strategy (from Pre-Flight Batch 1, Question 4).

### Phase 3: Pipeline Execution

Read `references/<type>/stages.md` for the stage tree.

**Each stage:**
1. Execute with appropriate parameters
2. Report key metrics
3. **Formal mode:** auto-advance to next step (only pause on errors/abnormal results)
4. **Test mode:** auto-advance, only pause on failure
5. On error: read `references/common/fallback.md`, apply downgrade, continue
6. Long tasks: nohup + flag + polling (interval from Pre-Flight Batch 2, Question 8)
7. File cleanup according to Pre-Flight Batch 3, Question 9

### Phase 4: Visualization

Generate visualizations according to Pre-Flight Batch 3, Question 10 scope.
Read `references/<type>/visualization.md` for configuration.

---

## Stage Progression

### ChIP-seq Stage Tree

| # | Stage | Tool (primary) | Fallback | Verification Point |
|---|-------|-----------------|----------|-------------------|
| 1 | Data download | Aspera (port 33001) | ENA Aspera -> prefetch (HTTPS) | File size matches GEO metadata |
| 2 | Format conversion | fasterq-dump + pigz | fastq-dump | R1/R2 file pairs exist |
| 3 | QC + adapter trimming | fastp | FastQC + Trimmomatic | R1/R2 read counts MUST match |
| 4 | Alignment | Bowtie2 | BWA-mem -> STAR | Alignment rate > 80% |
| 5 | Deduplication | samtools markdup | Picard MarkDuplicates | Duplication rate < 30% |
| 6 | Peak calling | MACS2 | Genrich -> SEACR | Peak count reasonable (TF: 50-10000) |
| 7 | Annotation + enrichment | R ChIPseeker + clusterProfiler | — | — |
| 8 | Visualization | deepTools + pyGenomeTracks | R ggplot | Check data range before setting Y-axis |

### Common Verification Points (All Types)

- R1/R2 read count consistency (paired-end)
- Alignment rate > 80%
- Duplication rate reasonable
- Peak/feature count in expected range
- Chromosome naming consistency across all files

---

## Interaction Checkpoints

**ALL checkpoints marked [ASK] MUST use the `AskUserQuestion` tool — never plain text.**

| Checkpoint | When to Pause | [ASK] Options |
|------------|---------------|---------------|
| Mode selection | Start | 正式分析 / 测试模式 / 仅环境检查 |
| Analysis type | After mode | ChIP-seq / RNA-seq / ATAC-seq / 自定义 |
| Server connection | After type | 使用已保存别名 / 新服务器 |
| Data source | After connection | GEO/SRA / 本地文件 / 测试数据 |
| Reference genome | After data confirm | (动态) 已有基因组列表 / 构建新基因组 |
| Each stage complete | Formal: end of stage | 继续下一步 / 调整参数 / 暂停 |
| Download failure | Aspera fails | 切换 prefetch / 尝试 ENA / 换 SRR |
| Dependency missing | Tool not found | 自动安装 / 用降级工具 / 跳过 |
| Alignment error | R1/R2 mismatch | 重新下载 / 重新质控 / 换比对工具 |
| Abnormal peak count | <10 or >50000 | 调阈值 / 换工具 / 继续 |
| Test mode complete | Final report | 开始正式分析 / 调整后重试 / 结束 |

---

## Long Task Management (3-Layer Architecture)

Read `references/common/long-task.md` for the full architecture. Summary:

1. **Layer 1 — Server-side orchestrator**: one nohup'd bash script self-drives the whole pipeline on the server, writes `pipeline_status.txt` + `flags/`, self-heals known failures (download restart, queryname re-sort, disk checks), fails fast on data corruption. A `mission.md` alongside enables any fresh session to take over.
2. **Layer 2 — Main-session watcher**: one background SSH job exits when status shows FAILED or ALL_DONE; the resulting task_notification wakes the main session with full context to repair or report. This is the bridge that returns control to the conversation WITHOUT user relay.
3. **Layer 3 — Schedule polling**: every 30 min, reads pipeline_status.txt and reports progress to the user. Reporting only, no control authority.

Sizing: tasks < 10 min run directly; 10 min–2 h use orchestrator + watcher; > 2 h use all three layers.

---

## File Structure

```
upstream-analysis/
├── SKILL.md                          # This file: trigger + interaction engine
├── references/
│   ├── common/
│   │   ├── server-setup.md           # SSH config + passwordless login
│   │   ├── env-checklist.md          # Dependency checklist per analysis type
│   │   ├── download-strategy.md      # Download fallback decision tree
│   │   ├── reference-genome.md       # Reference genome selection + building
│   │   ├── geo-metadata.md           # GEO metadata collection spec
│   │   ├── long-task.md              # 3-layer architecture: orchestrator + watcher + polling
│   │   ├── fallback.md               # General fallback principles
│   │   └── pitfalls.md              # Pitfall checklist (13+ items)
│   ├── chip-seq/
│   │   ├── stages.md                 # Stage tree + verification points
│   │   ├── params.md                 # Parameter templates (TF/Histone/SE/PE)
│   │   ├── test-mode.md              # Test mode definition + PASS/FAIL criteria
│   │   └── visualization.md          # deepTools + pyGenomeTracks config
│   ├── atac-seq/
│   │   ├── stages.md                 # ATAC stage tree (mtDNA filter, Tn5 shift)
│   │   ├── params.md                 # ATAC params (length_required 15, -X 2000)
│   │   └── test-mode.md              # ATAC PASS/FAIL criteria
│   ├── hic-seq/
│   │   ├── stages.md                 # Hi-C stage tree (chimeric map, matrix, balance, structure)
│   │   └── params.md                 # chromap/cooler/cooltools params + resolution/QC tables
│   └── rna-seq/                      # Future extension
└── scripts/
    ├── orchestrator_template.sh      # Layer 1: server-side pipeline chain script (parallel master/worker)
    ├── check_env.sh                  # Environment scanner (JSON output)
    ├── test_pipeline.sh              # Test mode runner (small-scale validation)
    └── poll_job.sh                   # Generic job poller
```

---

## Extending with New Analysis Types

To add a new analysis type (e.g., RNA-seq):

1. Create `references/rna-seq/` directory
2. Write `stages.md` defining the stage tree and fallback strategy
3. Write `params.md` with parameter templates
4. Add one line to the analysis type list in Step 1 of this file

Shared parts (server, download, long-task, pitfalls) do not need changes.

---

## Privacy Notes

- All server credentials (IP, port, username, password, SSH keys) must be provided by the user at runtime
- This skill never hardcodes credentials
- Saved connection aliases are stored in the user's `~/.ssh/config`, not in skill files
- All examples in reference files use placeholders like `<SERVER_IP>`, `<USERNAME>`
