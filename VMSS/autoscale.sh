#!/usr/bin/env bash
# =====================================================================
#  autoscale.sh — attach CPU-based autoscale rules to the scale set.
#  Scale OUT +1 when avg CPU > 30% for 5m; scale IN -1 when < 15%.
#  Usage:  ./autoscale.sh
#     RG=my-rg VMSS=vmssdemo-vmss MAX=15 ./autoscale.sh
# =====================================================================
set -euo pipefail

RG="${RG:-vmss-demo-rg}"
VMSS="${VMSS:-vmssdemo-vmss}"
MIN="${MIN:-2}"
MAX="${MAX:-10}"
DEFAULT="${DEFAULT:-2}"
OUT_CPU="${OUT_CPU:-30}"
IN_CPU="${IN_CPU:-15}"

command -v az >/dev/null 2>&1 || { echo "Azure CLI not found: https://aka.ms/azcli"; exit 1; }

AUTOSCALE="${VMSS}-autoscale"

echo ">> Creating autoscale profile '$AUTOSCALE'"
az monitor autoscale create \
  --resource-group "$RG" \
  --resource "$VMSS" \
  --resource-type Microsoft.Compute/virtualMachineScaleSets \
  --name "$AUTOSCALE" \
  --min-count "$MIN" --max-count "$MAX" --count "$DEFAULT" -o none

echo ">> Scale-OUT rule: CPU > ${OUT_CPU}% for 5m -> +1"
az monitor autoscale rule create \
  --resource-group "$RG" --autoscale-name "$AUTOSCALE" \
  --condition "Percentage CPU > ${OUT_CPU} avg 5m" \
  --scale out 1 --cooldown 5 -o none

echo ">> Scale-IN rule:  CPU < ${IN_CPU}% for 5m -> -1"
az monitor autoscale rule create \
  --resource-group "$RG" --autoscale-name "$AUTOSCALE" \
  --condition "Percentage CPU < ${IN_CPU} avg 5m" \
  --scale in 1 --cooldown 5 -o none

echo ""
echo "=================================================="
echo " Autoscale configured on $VMSS"
echo " Range     : $MIN - $MAX instances (default $DEFAULT)"
echo " Scale out : CPU > ${OUT_CPU}%"
echo " Scale in  : CPU < ${IN_CPU}%"
echo "=================================================="
echo ""
echo "Trigger load without SSH using run-command, e.g.:"
echo "  az vmss list-instances -g $RG -n $VMSS --query \"[].instanceId\" -o tsv"
echo "  az vmss run-command invoke -g $RG -n $VMSS --instance-id 0 \\"
echo "    --command-id RunShellScript --scripts \"for i in 1 2; do (while :; do :; done) & done; sleep 300; kill \\\$(jobs -p)\""
