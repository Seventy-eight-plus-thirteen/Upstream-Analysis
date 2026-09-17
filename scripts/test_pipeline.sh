#!/bin/bash
# test_pipeline.sh — Test mode runner for upstream-analysis
# Runs the entire pipeline with 1 SRR to verify connectivity
# Usage: test_pipeline.sh <SSH_ALIAS> <SRR> <BOWTIE2_INDEX> [INPUT_SRR]
#
# This script is a TEMPLATE — it demonstrates the full test flow.
# In practice, the agent orchestrates these steps interactively.

ALIAS="$1"
SRR="$2"
INDEX="$3"
INPUT_SRR="${4:-}"

if [ -z "$ALIAS" ] || [ -z "$SRR" ] || [ -z "$INDEX" ]; then
  echo "Usage: test_pipeline.sh <SSH_ALIAS> <SRR> <BOWTIE2_INDEX> [INPUT_SRR]"
  echo ""
  echo "Runs a full pipeline test with 1 ChIP sample (+ optional Input)."
  echo "Verifies: download -> convert -> QC -> align -> dedup -> peakcall -> viz"
  exit 1
fi

echo "═══ Test Mode Pipeline ═══"
echo "Server: $ALIAS"
echo "ChIP SRR: $SRR"
echo "Index: $INDEX"
if [ -n "$INPUT_SRR" ]; then
  echo "Input SRR: $INPUT_SRR"
fi
echo ""

WORK_DIR="/tmp/upstream_test_${SRR}"
RESULTS_FILE="${WORK_DIR}/test_results.txt"
PASS_COUNT=0
FAIL_COUNT=0
TOTAL=8

run_step() {
  local step_num=$1
  local step_name=$2
  local step_cmd="$3"
  local check_cmd="$4"

  echo ""
  echo "[$step_num/$TOTAL] $step_name"
  eval "$step_cmd"
  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    eval "$check_cmd"
    local check_exit=$?
    if [ $check_exit -eq 0 ]; then
      echo "  → PASS"
      echo "[$step_num/$TOTAL] $step_name .... PASS" >> "$RESULTS_FILE"
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      echo "  → FAIL (verification failed)"
      echo "[$step_num/$TOTAL] $step_name .... FAIL (verification)" >> "$RESULTS_FILE"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  else
    echo "  → FAIL (exit code $exit_code)"
    echo "[$step_num/$TOTAL] $step_name .... FAIL (exit $exit_code)" >> "$RESULTS_FILE"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# This template runs on the server via SSH
# In practice, the agent executes each step and tracks results

echo ""
echo "═══ Test Results ═══"
if [ -f "$RESULTS_FILE" ]; then
  cat "$RESULTS_FILE"
fi
echo ""
echo "Summary: ${PASS_COUNT}/${TOTAL} PASS"
if [ $FAIL_COUNT -gt 0 ]; then
  echo "         ${FAIL_COUNT} FAILED — fix before formal analysis"
else
  echo "         Pipeline ready for formal analysis"
fi
