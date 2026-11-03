# Shared settings for all demo scripts. Edit these, then run the scripts in order.
RG="rg-autoscale-demo"
LOCATION="centralindia"
PLAN="plan-autoscale-demo"
APP="autoscale-demo-$(whoami | tr -cd 'a-z0-9' | cut -c1-8)-$(date +%m%d)"   # must be globally unique
SKU="S1"                       # autoscale needs Standard (S1) or higher; Basic/Free cannot autoscale
AUTOSCALE="autoscale-demo-rules"

# Autoscale thresholds (deliberately aggressive so the demo is quick)
MIN=1
MAX=3
SCALE_OUT_CPU=60               # add 1 instance when avg CPU > 60% ...
SCALE_OUT_WINDOW=5m            # ... over the last 5 minutes (5m is the smallest window Azure allows)
SCALE_IN_CPU=30                # remove 1 instance when avg CPU < 30% ...
SCALE_IN_WINDOW=10m            # ... over the last 10 minutes
COOLDOWN=5                     # minutes to wait between scale actions

# Remember the generated app name across scripts
STATE_FILE="$(dirname "${BASH_SOURCE[0]}")/.app-name"
if [ -f "$STATE_FILE" ]; then APP="$(cat "$STATE_FILE")"; fi
URL="https://${APP}.azurewebsites.net"
