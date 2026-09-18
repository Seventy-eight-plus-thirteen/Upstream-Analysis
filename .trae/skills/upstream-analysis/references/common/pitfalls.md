# Pitfall Quick Reference

## All Known Pitfalls (Sorted by Stage)

### Download Stage

| # | Symptom | Cause | Fix |
|---|---------|-------|-----|
| 1 | Aspera connection timeout | Port 33001/33002 blocked by firewall | Switch to prefetch (HTTPS) |
| 2 | ENA Aspera auth failure | ENA doesn't host all samples or cert expired | Switch to NCBI prefetch |
| 3 | SRA file deleted/BAM incomplete | Intermediate files cleaned up too early | Re-download; never delete until next step verified |

### QC Stage

| # | Symptom | Cause | Fix |
|---|---------|-------|-----|
| 4 | Bowtie2 "fewer reads in R2 than R1" | SRA incomplete or fastq conversion error | Re-download SRA; fastp to enforce pairing |

### Alignment Stage

| # | Symptom | Cause | Fix |
|---|---------|-------|-----|
| 5 | Low alignment rate (<60%) | Wrong reference genome or adapter contamination | Check genome version; re-run fastp |

### Deduplication Stage

| # | Symptom | Cause | Fix |
|---|---------|-------|-----|
| 6 | Genrich "SAM/BAM not sorted by queryname" | Genrich requires queryname sort | `samtools sort -n` before Genrich |

### Peak Calling Stage

| # | Symptom | Cause | Fix |
|---|---------|-------|-----|
| 7 | No peaks called | Wrong BAM sort or too stringent threshold | Check tool's sort requirement; lower -q threshold |
| 8 | Too many peaks (>50000) | Input control not working or loose threshold | Verify Input BAM; raise -q threshold |
| 9 | MACS2 not installed | Server doesn't have MACS2 | Use Genrich as fallback |

### Visualization Stage

| # | Symptom | Cause | Fix |
|---|---------|-------|-----|
| 10 | plotHeatmap "unrecognized arguments" | Parameter name changed between versions | Use `--whatToShow "heatmap and colorbar"` |
| 11 | bigwigCompare command not found | Typo: wrote `bigwCompare` | Correct: `bigwigCompare` |
| 12 | `--operation log2ratio` invalid | Wrong parameter value | Use `--operation log2` |
| 13 | ChIP and Input heatmaps look identical | Raw signal too similar globally | Use `bigwigCompare --operation log2` for ratio heatmap |
| 14 | pyGenomeTracks crash on startup | NumPy 2.x incompatibility | `pip install "numpy<2"` |
| 15 | Gene annotation track empty | Chromosome naming mismatch (chr1 vs 1) | `sed 's/^chr//' bed_file` |
| 16 | Signal appears as flat bars | max_value too low (30 vs actual 3500) | Check data range; set max_value to p99 |
| 17 | Signal line breaks at zero | `type=line` breaks at NaN/zero | Use `type=fill` + `nans_to_zeros=true` |
| 18 | deepTools breaks after NumPy downgrade | deepTools 3.5.6 expects NumPy>=2 | `pip install --force-reinstall --no-deps deeptools` |
| 19 | pip command not found | pip installed to wrong PATH | `python3 -m pip` or `export PATH=~/.local/bin:$PATH` |
| 25 | `samtools view -v` invalid option (mtDNA filter fails) | samtools 1.13+ removed the `-v` "exclude region" flag; `--help` also matches `-v` inside `--verbosity` | Exclude MT by passing all nuclear contigs as explicit regions: `REGIONS=$(samtools view -H in.bam | awk -v mt="$MT" '$1=="@SQ"{sub(/^SN:/,"",$2); if($2!=mt) print $2}'); samtools view -b in.bam $REGIONS > out.bam`; do NOT probe support via `--help \| grep -v` |
| 26 | Pipeline watcher misfires on stale FAILED lines | `pipeline_status.txt` keeps historical FAILED lines across restarts; `grep FAILED` hits old entries | Watch the orchestrator PID (survives = running) and only detect a NEW FAILED by counting failure lines, not by grepping the whole file |
| 27 | `alignmentSieve: command not found` (also bamCoverage, deeptools) when run by orchestrator/script | Non-interactive shells (cron, `ssh cmd`, `nohup`) don't source `~/.profile`, so `~/.local/bin` is not on PATH; the tool exists but is invisible | At the top of every orchestration script: `export PATH="$HOME/.local/bin:$PATH"` — same root cause and fix as chromap (#21) |
| 28 | Genrich `--atacpair` → "unrecognized option"; `-q 2.0` → "p-/q-value must be in (0,1]" | Genrich 0.6.2 has no `--atacpair`; the ATAC-seq mode flag is `-j`. `-q` must be ≤1. `-e` requires an argument and silently swallows the next token (e.g. `-v`) when left empty | Use `Genrich -t <qname.bam> -r -v -j -q 0.05`; drop `-e` entirely (mtDNA already removed upstream) |
| 29 | `bamCoverage: invalid choice: 'RPM'` | newer deepTools removed `--normalizeUsing RPM` (allowed: RPKM/CPM/BPM/RPGC/None) | Use `--normalizeUsing BPM` (bins per million = per-million-reads equivalent, no length normalization) |
| 30 | Editing orchestrator.sh mid-run doesn't affect already-started stages | bowtie2 launched with `--very-sensitive` keeps using that even after the script is edited to `--sensitive`; the process reads its args at launch time, not from the file | To change params for a running stage: `kill` the process + `rm` half-finished BAMs + `rm flags/<stage>_<SRR>` + restart orchestrator. Always verify the new process's actual CLI args with `ps -p <pid> -o cmd` |

### Hi-C Matrix Stage

| # | Symptom | Cause | Fix |
|---|---------|-------|-----|
| 31 | `cooler cload pairs` BadGzipFile error | chromap outputs **plain-text** pairs (not gzip); cooler expects `.pairs.gz` | `gzip pairsfile` before cload, or use `cooler cload pairs --input-buffer 0` |
| 32 | `cooler zoomify` resolution not found | zoomify doubles base resolution (1000→2000→4000→…→64000→128000); arbitrary values like 10000/25000/100000 don't exist | Use powers-of-2 multiples of base: 32000/64000/128000/256000; check with `cooler ls mcool` |
| 33 | cooltools `eigs-cis: No such option: -I` | cooltools 0.7.1 changed API: takes `COOL_PATH` as positional arg, not `-I` | `cooltools eigs-cis mcool::resolutions/128000 -o prefix` (no `-I`) |
| 34 | cooltools `--bigwig` fails (FileNotFoundError: bedGraphToBigWig) | `--bigwig` requires UCSC `bedGraphToBigWig` tool; server doesn't have it | Drop `--bigwig`; eigenvector/insulation data is in TSV, can convert to bedgraph manually for pyGenomeTracks |
| 35 | cooltools `insulation` IndexError (index 0 out of bounds for axis 0 with size 0) | cooler 0.10.4 `annotate` incompatible with cooltools 0.7.1 `insul_diamond` on sparse bins | Non-fatal — skip insulation; TAD boundaries visible from contact heatmap. Or upgrade cooler/cooltools to matching versions |

### Hi-C Visualization Stage (gghic)

| # | Symptom | Cause | Fix |
|---|---------|-------|-----|
| 36 | BiocManager "Bioconductor version cannot be validated; no internet connection" | bioconductor.org config.yaml times out in CN; BiocManager forces validation even with mirror set | Bypass BiocManager entirely: `install.packages("HiCExperiment", repos="https://mirrors.tuna.tsinghua.edu.cn/bioconductor/packages/release/bioc")` |
| 37 | gghic install fails — "cannot connect to github.com" | github.com port 443 blocked (even with gh CLI) | Download source tarball via `gh api repos/jasonwong-lab/gghic/tarball > gghic.tar.gz` locally, scp to server, `R CMD INSTALL` from source |
| 38 | `ChromatinContacts()` "resolution must be a single positive integer" | Passed numeric (128000) instead of integer; or file.path() concatenated region into path | Use `128000L` (R integer suffix); pass `focus=` and `resolution=` as separate args, not concatenated in path |
| 39 | gghic X-axis leftmost label truncated ("5.0 M" instead of "45.0 M") | Default plot margins too tight for long axis labels | Add `expand_xaxis = TRUE` in `gghic()` call, or `theme(plot.margin = margin(5, 15, 5, 10))` |

### Tool Installation Stage

| # | Symptom | Cause | Fix |
|---|---------|-------|-----|
| 20 | GitHub release download timeout (local Mac too) | github.com blocked, but api.github.com works | `curl -H "Accept: application/octet-stream" -L -o file https://api.github.com/repos/<owner>/<repo>/releases/assets/<ID>` |
| 21 | chromap repo "Not Found" | Correct repo is `haowenz/chromap` (with z); v0.3.x has no prebuilt binaries | Use v0.2.7 release asset `chromap-0.2.7_x64-linux.tar.bz2`, scp to server |
| 22 | cooltools import `SystemError: initialization of _internal failed` | System numba (dist-packages) is broken; pip skips install because it "exists" | `python3 -m pip install --user -i <tsinghua> "numba>=0.59"` to shadow it |
| 23 | `cooler cload pairs` "File not found" on binspec | `::` is cooler URI syntax; cload binspec uses SINGLE colon | `chrom.sizes:1000` not `chrom.sizes::1000` |
| 24 | pip warning "deeptools requires numpy>=2.0" | Metadata-only conflict after installs | Cosmetic — verify with `bamCoverage --version`; deeptools still runs on numpy 1.26 |

## Top 5 Most Impactful Pitfalls

1. **Aspera port blocking** (#1) — costs hours of trial-and-error if not known
2. **R1/R2 mismatch** (#4) — causes entire pipeline to fail at alignment
3. **Genrich queryname sort** (#6) — silent failure that blocks peak calling
4. **NumPy version conflict** (#14, #18) — blocks all visualization
5. **Chromosome naming inconsistency** (#15) — silently produces empty tracks

## Prevention Checklist

Before starting the pipeline, verify:
- [ ] Aspera port 33001 reachable? (if not, plan to use prefetch)
- [ ] NumPy version < 2.0?
- [ ] All BED/narrowPeak files use same chromosome naming as bigWig?
- [ ] BAM sort order matches the peak caller's requirement?
- [ ] bigWig data range checked before setting visualization Y-axis max?
