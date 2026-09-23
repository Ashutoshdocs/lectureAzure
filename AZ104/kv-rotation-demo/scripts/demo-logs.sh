#!/usr/bin/env bash
# DEMO: tail the app logs on the VM (shows 'Event received' / 'Secret loaded').
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
ssh "azureuser@$(vm_ip)" 'sudo journalctl -u kvdemo -f'
