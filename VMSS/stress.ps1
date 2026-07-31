$script = @'
sudo apt-get update
sudo apt-get install -y stress-ng
stress-ng --cpu 2 --timeout 600s
'@

$ids = az vmss list-instances `
-g vmss-demo-rg `
-n vmssdemo-vmss `
--query "[].instanceId" -o tsv

foreach ($id in $ids) {

    Write-Host "Starting stress on VM $id"

    az vmss run-command invoke `
      -g vmss-demo-rg `
      -n vmssdemo-vmss `
      --instance-id $id `
      --command-id RunShellScript `
      --scripts $script

}
