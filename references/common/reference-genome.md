# Reference Genome Selection & Building

## Selection Process

### 1. Check What Already Exists on Server

```bash
# Search for Bowtie2 indexes
find / -name "*.bt2" -o -name "*.bt2l" 2>/dev/null | head -20
# Common locations: ~/.local/share/bowtie2/, /media/*/indexes/, /opt/*/indexes/

# Search for BWA indexes
find / -name "*.bwt" -o -name "*.pac" 2>/dev/null | head -20

# Search for STAR indexes
find / -name "SAindex" 2>/dev/null | head -10

# Search for GTF/GFF annotations
find / -name "*.gtf" -o -name "*.gff3" 2>/dev/null | head -20
```

### 2. Present Options to User

```
Available reference genomes:
  [Existing] hg38 — Bowtie2 index at /path/to/hg38 (3.2GB)
  [Existing] hg19 — Bowtie2 index at /path/to/hg19 (2.8GB)
  [Existing] mm10 — STAR index at /path/to/mm10
  [Need build] GRCh37, mm39, danRer11, ...
```

### 3. If Genome Not Found

Ask user:
> Genome <NAME> not found. Build it now? (requires ~30min-1h download + indexing)

If confirmed:

#### Bowtie2 Index Build

```bash
# Download from UCSC
wget -O <GENOME>.fa.gz http://hgdownload.soe.ucsc.edu/goldenPath/<GENOME>/bigZips/<GENOME>.fa.gz
gunzip <GENOME>.fa.gz

# Build Bowtie2 index
bowtie2-build --threads 16 <GENOME>.fa <GENOME>_index

# Verify
ls -lh <GENOME>_index.*.bt2
```

#### GTF Annotation Download

```bash
# From GENCODE (recommended)
wget -O <GENOME>.gtf.gz https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_<VER>/<GENOME>_annotation.gtf.gz
gunzip <GENOME>.gtf.gz
```

### 4. Genome Version Compatibility Warning

**CRITICAL**: If the original publication used hg19/GRCh37 but user selects hg38/GRCh38:
- Peak coordinates will differ between builds
- Cross-reference with hg19-based databases (ENCODE, Roadmap) may fail
- Liftover is possible but introduces uncertainty

**Always inform the user of this discrepancy and require explicit confirmation.**

## Common Reference Genomes

| Name | Species | UCSC | GENCODE | Notes |
|------|---------|------|---------|-------|
| hg38 | Human | GRCh38 | v44+ | Current standard |
| hg19 | Human | GRCh37 | v19 | Legacy, many published datasets |
| mm10 | Mouse | GRCm38 | VM34+ | Mouse standard |
| mm39 | Mouse | GRCm39 | VM34+ | Latest mouse |
| danRer11 | Zebrafish | GRCz11 | — | Zebrafish |

## Index File Naming Convention

Keep genome files organized:
```
/path/to/genomes/
├── hg38/
│   ├── hg38.fa              # FASTA
│   ├── hg38.1.bt2           # Bowtie2 index
│   ├── hg38.2.bt2
│   ├── hg38.3.bt2
│   ├── hg38.4.bt2
│   ├── hg38.rev.1.bt2
│   ├── hg38.rev.2.bt2
│   └── hg38.gtf             # Annotation
├── hg19/
│   └── ...
└── mm10/
    └── ...
```

## BED File Chromosome Naming

**CRITICAL PITFALL**: Different sources use different chromosome naming:
- UCSC: `chr1`, `chr2`, ..., `chrM`
- NCBI/Ensembl: `1`, `2`, ..., `MT`
- Bowtie2 index: depends on FASTA source

**Always check consistency between bigWig, BED, narrowPeak, and GTF files.**

Unify naming:
```bash
# Remove chr prefix
sed 's/^chr//' input.bed > output_nochr.bed

# Add chr prefix
sed 's/^/chr/' input.bed > output_chr.bed
```
