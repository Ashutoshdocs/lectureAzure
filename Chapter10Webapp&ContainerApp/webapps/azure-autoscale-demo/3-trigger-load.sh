#!/usr/bin/env bash
# Step 3: SAFE load generator.
# It does NOT flood the site with traffic. It sends one tiny request every 20s to /burn,
# which tells the receiving instance to spin its CPU for 60s (the app caps it at 120s and a
# watchdog stops it automatically). The whole script stops after DURATION_MIN minutes,
# and Ctrl+C sends /stop so the CPU goes idle immediately.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

DURATION_MIN="${1:-12}"     # usage: ./3-trigger-load.sh [minutes]  (default 12)
END=$(( $(date +%s) + DURATION_MIN * 60 ))

cleanup() {
  echo; echo "==> Stopping load on all instances"
  for _ in 1 2 3 4 5 6; do curl -s "$URL/stop" -o /dev/null || true; done
  exit 0
}
trap cleanup INT TERM

echo "==> Generating CPU load on $URL for $DURATION_MIN min (Ctrl+C to stop early)"
echo "    Expect the first scale-out roughly 5-10 min in (5m metric window + Azure evaluation lag)."
while [ "$(date +%s)" -lt "$END" ]; do
  # a few requests per round so that, once there are several instances, each gets one
  for _ in 1 2 3; do
    curl -s --max-time 10 "$URL/burn?seconds=60" || true; echo
  done
  sleep 20
done
cleanup
