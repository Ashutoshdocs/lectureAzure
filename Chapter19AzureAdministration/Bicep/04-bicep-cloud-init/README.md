# Practical 4 – Provision a Linux VM with Bicep and cloud-init

## Learning objectives

- Understand how Bicep passes cloud-init configuration to a Linux VM.
- Use `customData` to bootstrap a VM at first boot.
- Install and enable Nginx automatically.
- Publish a simple teaching webpage.
- Inspect cloud-init logs when troubleshooting.

## What will be created?

- VNet and subnet
- NSG allowing HTTP (80) and SSH (22) from the configured admin source
- Standard static public IP
- NIC
- Ubuntu 24.04 Linux VM
- cloud-init configuration that installs Nginx and writes a landing page

This is a teaching example. SSH is restricted by `adminSourceAddressPrefix`; use your public IP `/32`.

## 1. Prepare

```bash
az login
RG="rg-bicep-cloudinit"
az group create --name "$RG" --location centralus
ssh-keygen -t ed25519 -f ~/.ssh/bicep_cloudinit -N ""
```

## 2. Validate and preview

```bash
az bicep build --file main.bicep
az deployment group validate -g "$RG" -f main.bicep \
  -p adminUsername="azureadmin" \
     sshPublicKey="$(cat ~/.ssh/bicep_cloudinit.pub)" \
     adminSourceAddressPrefix="<YOUR_PUBLIC_IP>/32"

az deployment group what-if -g "$RG" -f main.bicep \
  -p adminUsername="azureadmin" \
     sshPublicKey="$(cat ~/.ssh/bicep_cloudinit.pub)" \
     adminSourceAddressPrefix="<YOUR_PUBLIC_IP>/32"
```

## 3. Deploy

```bash
az deployment group create -g "$RG" -f main.bicep \
  -p adminUsername="azureadmin" \
     sshPublicKey="$(cat ~/.ssh/bicep_cloudinit.pub)" \
     adminSourceAddressPrefix="<YOUR_PUBLIC_IP>/32"
```

## 4. Open the website

```bash
VM_IP=$(az deployment group show -g "$RG" -n main \
  --query properties.outputs.vmPublicIp.value -o tsv)
echo "http://$VM_IP"
```

Open the displayed HTTP URL in a browser. The page should show that cloud-init completed the configuration.

## 5. Connect and inspect cloud-init

```bash
ssh -i ~/.ssh/bicep_cloudinit azureadmin@"$VM_IP"
```

On the VM:

```bash
cloud-init status --long
sudo tail -n 100 /var/log/cloud-init-output.log
sudo systemctl status nginx --no-pager
curl -I http://localhost
```

cloud-init custom data normally runs during the first boot. Editing the YAML and redeploying the same VM does not guarantee that cloud-init will rerun as a fresh first-boot operation. For a clean repeat, recreate the VM or use an appropriate configuration-management/extension workflow.

## 6. Teaching challenge

Ask students to:
- Change the HTML page title and message.
- Add another package to `packages`.
- Add a second file under `/var/www/html`.
- Explain the difference between Bicep (Azure resource provisioning) and cloud-init (guest OS first-boot configuration).

## Cleanup

```bash
az group delete --name "$RG" --yes --no-wait
```
