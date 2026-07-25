$ids = az vmss list-instances `
  -g vmss-demo-rg `
  -n vmssdemo-vmss `
  --query "[].instanceId" -o tsv

foreach ($id in $ids) {
    Write-Host "Starting CPU stress on instance $id..."

    az vmss run-command invoke `
      -g vmss-demo-rg `
      -n vmssdemo-vmss `
      --instance-id $id `
      --command-id RunShellScript `
      --scripts "for i in 1 2; do (while :; do :; done) & done; sleep 600; kill \$(jobs -p)"
}
