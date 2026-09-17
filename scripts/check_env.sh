#!/bin/bash
# check_env.sh — Server environment scanner for upstream-analysis
# Usage: ssh <ALIAS> 'bash -s' < check_env.sh
# Output: JSON-formatted environment report

echo "{"

# OS info
echo '"os": {'
echo "  \"hostname\": \"$(hostname)\","
echo "  \"uname\": \"$(uname -s)\","
echo "  \"kernel\": \"$(uname -r)\""
echo "},"

# CPU
CPU_CORES=$(nproc 2>/dev/null || echo "unknown")
echo "\"cpu\": {"
echo "  \"cores\": $CPU_CORES"
echo "},"

# Memory
MEM_TOTAL=$(free -g 2>/dev/null | awk '/^Mem:/ {print $2}')
echo "\"memory\": {"
echo "  \"total_gb\": ${MEM_TOTAL:-0}"
echo "},"

# Disk
echo '"disk": ['
df -h 2>/dev/null | grep -E "^/dev" | awk -F' ' '{
  printf "  {\"mountpoint\": \"%s\", \"total\": \"%s\", \"used\": \"%s\", \"avail\": \"%s\", \"usage\": \"%s\"}", $6, $2, $3, $4, $5
  if (NR > 0) printf ","
  print ""
}'
echo "],"

# Python
PY_VER=$(python3 --version 2>&1 | awk '{print $2}')
echo "\"python\": {"
echo "  \"version\": \"$PY_VER\","
NP_VER=$(python3 -c "import numpy; print(numpy.__version__)" 2>/dev/null || echo "not installed")
echo "  \"numpy\": \"$NP_VER\","
SCIPY=$(python3 -c "import scipy; print('ok')" 2>/dev/null && echo "yes" || echo "no")
echo "  \"scipy\": \"$SCIPY\","
MPL=$(python3 -c "import matplotlib; print('ok')" 2>/dev/null && echo "yes" || echo "no")
echo "  \"matplotlib\": \"$MPL\","
PBW=$(python3 -c "import pyBigWig; print('ok')" 2>/dev/null && echo "yes" || echo "no")
echo "  \"pyBigWig\": \"$PBW\""
echo "},"

# Conda
echo '"conda": {'
if command -v conda &>/dev/null; then
  CONDA_VER=$(conda --version 2>&1 | awk '{print $NF}')
  echo "  \"version\": \"$CONDA_VER\","
  echo "  \"envs\": ["
  conda env list 2>/dev/null | grep -v "^#" | grep -v "^$" | awk '{printf "    \"%s\"", $1}' | paste -sd, -
  echo "  ]"
else
  echo "  \"installed\": false"
fi
echo "},"

# Tools
echo '"tools": {'
TOOLS="prefetch fasterq-dump ascp kingfisher aria2c pigz fastp fastqc trimmomatic bowtie2 bwa star samtools picard Genrich macs2 bamCoverage bigwigCompare computeMatrix plotHeatmap plotProfile pyGenomeTracks"
echo "  ["
FIRST=true
for tool in $TOOLS; do
  if [ "$FIRST" = true ]; then
    FIRST=false
  else
    echo ","
  fi
  if command -v $tool &>/dev/null; then
    VER=$($tool --version 2>&1 | head -1 | sed 's/"/\\"/g')
    printf "    {\"name\": \"%s\", \"installed\": true, \"version\": \"%s\"}" "$tool" "$VER"
  else
    # Try with python3 -m
    if python3 -m $tool --help &>/dev/null 2>&1; then
      printf "    {\"name\": \"%s\", \"installed\": true, \"version\": \"unknown\"}" "$tool"
    else
      printf "    {\"name\": \"%s\", \"installed\": false}" "$tool"
    fi
  fi
done
echo ""
echo "  ]"
echo "}"

echo "}"
