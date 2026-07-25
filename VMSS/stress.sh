#!/usr/bin/env bash
# =====================================================================
#  stress.sh — burn CPU on this VM to push the scale set past 30%
#  Usage:  ./stress.sh [DURATION_SECONDS] [WORKERS]
#  Example: ./stress.sh 600 2      # 2 workers for 10 minutes
#  Defaults: 300s, one worker per vCPU.
# =====================================================================
set -euo pipefail

DURATION="${1:-300}"
WORKERS="${2:-$(nproc)}"

echo "CPU stress: ${WORKERS} worker(s) for ${DURATION}s (this host has $(nproc) vCPU)."

# Preferred path: stress-ng if available or installable.
if command -v stress-ng >/dev/null 2>&1; then
  echo "Using stress-ng."
  exec stress-ng --cpu "${WORKERS}" --timeout "${DURATION}s" --metrics-brief
fi

if command -v apt-get >/dev/null 2>&1; then
  echo "Installing stress-ng..."
  if sudo apt-get update -qq && sudo apt-get install -y -qq stress-ng; then
    exec stress-ng --cpu "${WORKERS}" --timeout "${DURATION}s" --metrics-brief
  fi
  echo "Install failed; falling back to pure-bash busy loops."
fi

# Fallback: portable busy loops, no packages required.
echo "Using bash busy-loop fallback."
pids=()
for _ in $(seq 1 "${WORKERS}"); do
  ( while :; do :; done ) &
  pids+=("$!")
done

cleanup() {
  echo "Stopping workers..."
  for pid in "${pids[@]}"; do kill "${pid}" 2>/dev/null || true; done
}
trap cleanup EXIT INT TERM

sleep "${DURATION}"
echo "Done."
