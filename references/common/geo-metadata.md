# GEO Metadata Collection Spec

## What to Ask the User

When user selects GEO/SRA data source:

### 1. Request SRA Metadata Table

> Please download the SRA metadata table from the GEO Accession page:
> 1. Go to the GEO page (e.g., https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSEXXXXXX)
> 2. Click "Send results to" -> "File format: Tab-delimited text" or download SRA Run Selector
> 3. Share the file with me (CSV/TSV/Excel)

### 2. Extract Required Information

From the metadata table, confirm:

| Field | Required | Example |
|-------|----------|---------|
| SRR number(s) | YES | SRR37221781 |
| Sample name | YES | MYOD1_ChIP_LHCN-M2_WT |
| LibraryStrategy | YES | ChIP-seq |
| LibraryLayout | YES | PAIRED |
| Platform | YES | ILLUMINA HiSeq 2500 |
| InsertSize | optional | 150 |
| Read length | optional | 50 |
| Organism | YES | Homo sapiens |
| Cell line | YES | LHCN-M2 |
| TF / target | YES (ChIP) | MYOD1 |
| Antibody | optional | anti-MYOD1 |

### 3. Confirm Sample Pairing (ChIP-seq)

> Which samples are ChIP and which are Input control?
> - ChIP sample: SRR37221781
> - Input control: SRR37221777
> - Biological replicates? (list groups)

### 4. Confirm Reference Genome

> The original publication used which reference genome?
> - hg19 / GRCh37
> - hg38 / GRCh38
> - Other: ___

If original genome differs from what's available on server, warn user (see reference-genome.md).

### 5. Confirm Analysis Parameters

Based on metadata:
- Paired-end or single-end?
- Read length (affects fastp and alignment parameters)
- Insert size (affects Genrich/MACS2 parameters)

## Metadata Parsing

The SRA Run Selector CSV typically has columns:
```
Run,Assay_Type,LibraryName,LibraryStrategy,LibrarySelection,LibrarySource,
LibraryLayout,InsertSize,Library_Name_s,Organism_s,Platform_s,Sample_Name_s,
disease_s,cell_line_s,treatment_s,chip_antibody_s,...
```

Parse and present to user in a readable table for confirmation.

## Example Metadata Table

```
Run         | Type     | Layout | TF    | Cell    | Input
SRR37221781 | ChIP-seq | PAIRED | MYOD1 | LHCN-M2  | SRR37221777
SRR37221777 | Input    | PAIRED | -     | LHCN-M2  | -
```

## Multiple Samples

If user has multiple ChIP samples and multiple Inputs:
- Ask which Input pairs with which ChIP
- If unsure, suggest matching by cell line and treatment
- For replicates, group by condition
