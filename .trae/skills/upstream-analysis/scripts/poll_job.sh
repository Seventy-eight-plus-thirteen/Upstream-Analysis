#!/bin/bash
# poll_job.sh — Generic job poller for remote long-running tasks
# Usage: poll_job.sh <SSH_ALIAS> <LOG_FILE> <FLAG_FILE> [INTERVAL_SECONDS] [MAX_WAIT_SECONDS]

ALIAS="$1"
LOG_FILE="$2"
FLAG_FILE="$3"
INTERVAL="${4:-60}"
MAX_WAIT="${5:-3600}"

if [ -z "$ALIAS" ] || [ -z "$LOG_FILE" ] || [ -z "$FLAG_FILE" ]; then
  echo "Usage: poll_job.sh <SSH_ALIAS> <LOG_FILE> <FLAG_FILE> [INTERVAL] [MAX_WAIT]"
  echo "  INTERVAL defaults to 60 seconds"
  echo "  MAX_WAIT defaults to 3600 seconds (1 hour)"
  exit 1
fi

echo "=== Job Poller Started ==="
echo "Server: $ALIAS"
echo "Log: $LOG_FILE"
echo "Flag: $FLAG_FILE"
echo "Interval: ${INTERVAL}s"
echo "Max wait: ${MAX_WAIT}s"
echo ""

ELAPSED=0
PREV_SIZE=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
  # Check if flag file exists (job completed)
  if ssh "$ALIAS" "test -f $FLAG_FILE" 2>/dev/null; then
    echo ""
    echo "=== JOB COMPLETED ==="
    echo "Flag file found: $FLAG_FILE"
    echo ""
    echo "=== Last 20 lines of log ==="
    ssh "$ALIAS" "tail -20 $LOG_FILE"
    exit 0
  fi

  # Check current progress
  LOG_TAIL=$(ssh "$ALIAS" "tail -3 $LOG_FILE" 2>/dev/null)
  FILE_SIZE=$(ssh "$ALIAS" "stat -c %s $LOG_FILE 2>/dev/null || echo 0")

  # Calculate rate
  if [ $PREV_SIZE -gt 0 ] && [ $FILE_SIZE -gt $PREV_SIZE ]; then
    RATE=$(( (FILE_SIZE - PREV_SIZE) / INTERVAL ))
    echo "[$(date '+%H:%M:%S')] elapsed=${ELAPSED}s | log=${FILE_SIZE}B (+${RATE}B/s) | tail: ${LOG_TAIL}"
  else
    echo "[$(date '+%H:%M:%S')] elapsed=${ELAPSED}s | log=${FILE_SIZE}B | tail: ${LOG_TAIL}"
  fi

  PREV_SIZE=$FILE_SIZE
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))

  # Check for stall (no log growth in 5 intervals)
  if [ $ELAPSED -ge $((INTERVAL * 5)) ] && [ "$FILE_SIZE" = "$PREV_SIZE" ]; then
    echo ""
    echo "=== WARNING: Possible stall ==="
    echo "Log file hasn't grown in ${INTERVAL}s x 5"
    echo "Checking if process is still alive..."
    PID=$(ssh "$ALIAS" "pgrep -f '$LOG_FILE'" 2>/dev/null)
    if [ -z "$PID" ]; then
      echo "Process NOT found — job may have crashed"
      echo "=== Last 30 lines of log ==="
      ssh "$ALIAS" "tail -30 $LOG_FILE"
      exit 2
    else
      echo "Process $PID still running, continuing to wait..."
    fi
  fi
done

echo ""
echo "=== TIMEOUT REACHED ==="
echo "Job did not complete within ${MAX_WAIT}s"
echo "=== Last 30 lines of log ==="
ssh "$ALIAS" "tail -30 $LOG_FILE"
exit 3
