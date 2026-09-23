#!/usr/bin/env bash
# DEMO terminal 1: watch which secret version the VM app is using.
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
IP=$(vm_ip)
echo "Open in browser: http://$IP:8080"
watch -n 2 "curl -s http://$IP:8080/api/secret | jq '{version, masked_value, loaded_at, last: .history[0]}'"
