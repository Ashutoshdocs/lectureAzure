$ids = az vmss list-instances -g vmss-demo-rg -n vmssdemo-vmss --query "[].instanceId" -o tsv

foreach ($id in $ids) {
    az vmss run-command invoke `
        -g vmss-demo-rg `
        -n vmssdemo-vmss `
        --instance-id $id `
        --command-id RunShellScript `
        --scripts "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y stress-ng && stress-ng --cpu 0 --timeout 600s"
}
