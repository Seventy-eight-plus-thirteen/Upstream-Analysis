# Environment Dependency Checklist

## Universal Requirements (All Analysis Types)

| Category | Tool | Min Version | Check Command | Install Command |
|----------|------|-------------|----------------|-----------------|
| Core | Python3 | 3.8+ | `python3 --version` | System package |
| Core | pip | 20+ | `python3 -m pip --version` | `python3 -m ensurepip` |
| Core | conda | optional | `conda --version` | Miniconda installer |
| Download | sratoolkit | 3.0+ | `prefetch --version` | `conda install -c bioconda sra-tools` |
| Download | aspera | 3.9+ | `ascp --version` | IBM Aspera Connect |
| Download | kingfisher | optional | `kingfisher -h` | `pip install kingfisher` |
| Download | aria2c | optional | `aria2c --version` | `conda install -c conda-forge aria2` |
| Download | pigz | any | `pigz --version` | `conda install -c conda-forge pigz` |
| QC | fastp | 0.23+ | `fastp --version` | `conda install -c bioconda fastp` |
| QC | fastqc | 0.11+ (optional) | `fastqc --version` | `conda install -c bioconda fastqc` |
| QC | trimmomatic | 0.39 (fallback) | `trimmomatic -version` | `conda install -c bioconda trimmomatic` |
| Alignment | bowtie2 | 2.3+ | `bowtie2 --version` | `conda install -c bioconda bowtie2` |
| Alignment | bwa | 0.7.17+ (fallback) | `bwa 2>&1 \| head -1` | `conda install -c bioconda bwa` |
| Alignment | star | 2.7+ (RNA-seq) | `STAR --version` | `conda install -c bioconda star` |
| Processing | samtools | 1.10+ | `samtools --version` | `conda install -c bioconda samtools` |
| Processing | picard | 2.20+ (fallback dedup) | `picard --version` | `conda install -c bioconda picard` |
| Python libs | numpy | <2.0 | `python3 -c "import numpy; print(numpy.__version__)"` | `pip install "numpy<2"` |
| Python libs | scipy | any | `python3 -c "import scipy"` | `pip install scipy` |
| Python libs | matplotlib | any | `python3 -c "import matplotlib"` | `pip install matplotlib` |
| Python libs | pyBigWig | any | `python3 -c "import pyBigWig"` | `pip install pyBigWig` |

## ChIP-seq Specific

| Category | Tool | Check Command | Install | Fallback |
|----------|------|----------------|---------|----------|
| Peak calling | MACS2 | `macs2 --version` | `pip install MACS2` | Genrich, SEACR |
| Peak calling | Genrich | `Genrich --version` | From source (GitHub) | SEACR |
| Visualization | deepTools | `bamCoverage --version` | `pip install deeptools` | R ggplot |
| Visualization | pyGenomeTracks | `pyGenomeTracks --version` | `pip install pyGenomeTracks` | IGV batch |
| Annotation | R ChIPseeker | R console | `BiocManager::install("ChIPseeker")` | bedtools closest |

## RNA-seq Specific (Future)

| Category | Tool | Check Command | Install |
|----------|------|----------------|---------|
| Quantification | salmon | `salmon --version` | `conda install -c bioconda salmon` |
| Quantification | rsem | `rsem-calculate-expression --version` | `conda install -c bioconda rsem` |
| Quantification | featureCounts | `featureCounts -v` | `conda install -c bioconda subread` |
| Visualization | deepTools | same as ChIP-seq | same |

## ATAC-seq Specific (Future)

| Category | Tool | Check Command | Install |
|----------|------|----------------|---------|
| Peak calling | MACS2 (broad) | `macs2 --version` | `pip install MACS2` |
| Peak calling | Genrich | `Genrich --version` | From source |
| Accessibility | pyATAC | optional | `pip install pyatac` |

## Hi-C Specific (verified installed 2026-09-17)

| Category | Tool | Check Command | Install / Fix |
|----------|------|----------------|---------------|
| Alignment | chromap | `chromap --version` (0.2.7) | GitHub v0.2.7 asset via api.github.com, scp to `~/.local/bin` (see pitfalls #20-21) |
| Alignment (fallback) | hicstuff | `hicstuff --version` (3.2.5) | `pip install -i <tsinghua> hicstuff` |
| Matrix | cooler | `python3 -m cooler --version` (0.10.4) | preinstalled |
| Structure analysis | cooltools | `cooltools --version` (0.7.1) | `pip install -i <tsinghua> cooltools` + fix numba if SystemError (pitfall #22) |
| Visualization | pyGenomeTracks | same as ChIP-seq | `.cool`/`.mcool` track supported |
| Reference | chromap index | `ls <GENOME>.chromap.idx` | build once from genome FASTA (~15min hg38); note server currently has bt2 index only, FASTA must be downloaded |

## Disk Space Requirements

| Stage | Per Sample | Notes |
|-------|-----------|-------|
| SRA download | ~5GB | Compressed SRA archive |
| Fastq conversion | ~10GB | 2x fastq files (paired-end) |
| BAM (raw) | ~7GB | Pre-deduplication |
| BAM (deduped) | ~5GB | Post-deduplication |
| bigWig | ~550MB | RPM normalized |
| Total per sample | ~25GB | All intermediate files |
| Reference index | ~3.5GB | Bowtie2 hg38 index |

**Rule of thumb**: Ensure at least 30GB free space per sample before starting.

## NumPy Version Warning

**CRITICAL**: pyGenomeTracks 3.9 and several bioinformatics tools are incompatible with NumPy 2.x.

Before installing any visualization tools, lock NumPy version:
```bash
python3 -m pip install "numpy<2"
```

deepTools 3.5.6 technically requires NumPy >= 2.0.0, but in practice works with 1.26.4. If deepTools breaks after NumPy downgrade, reinstall it:
```bash
pip install --force-reinstall --no-deps deeptools
```

## Environment Scan Script

Run `scripts/check_env.sh` on the server to get a JSON-formatted environment report:

```bash
ssh <ALIAS> 'bash -s' < scripts/check_env.sh
```

Output includes tool availability, versions, disk space, and missing dependencies with install suggestions.
