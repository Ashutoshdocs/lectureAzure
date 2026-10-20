Azure networking lab

# VNet Injection vs VNet Integration

Switch between four setups of the same web app and fire six traffic tests at each. Watch which packets get through, which time out, and which leak to the internet. Then reproduce it all with the Azure CLI steps further down.

**VNet Integration**The app stays on shared Microsoft infrastructure. It gets a one-way door *out* into your VNet. Nothing can come *in* through it.

**VNet Injection**The service's compute is deployed *into* a subnet of your VNet. It has a private IP, so traffic flows both in and out privately.

**Private Endpoint**The separate add-on that gives a multi-tenant app a private *inbound* address. Integration and Private Endpoint are usually paired.

The short answer

## What an app cannot do

### Without VNet Integration (outbound)

- Call anything that only has a private IP: VMs, internal load balancers, AKS internal services
- Reach Private Endpoints of SQL, Storage, Key Vault, Cosmos DB once their public access is off
- Reach peered VNets or on-premises networks over VPN or ExpressRoute
- Resolve names from Private DNS zones linked to your VNet
- Send traffic through your NAT Gateway for a fixed outbound IP, or through Azure Firewall via a route table
- Have its outbound traffic filtered by your NSGs

### Even with VNet Integration (inbound)

- Receive calls on a private IP. It still has none.
- Hide from the internet. The public endpoint stays open.
- Be protected by inbound NSG rules on the integration subnet
- Be reached from on-premises over the VPN
- Run on dedicated, single-tenant compute

Fix inbound with a **Private Endpoint**, or skip both add-ons and use **VNet Injection**.

Results matrix

## Six tests, four setups

The same results as the lab above, in one grid.

Reference

## Side by side

|  | VNet Integration (App Service regional) | VNet Injection (e.g. App Service Environment v3) |
| --- | --- | --- |
| Where the compute runs | Shared multi-tenant workers, outside your VNet | Inside a dedicated subnet of your VNet |
| Traffic direction | Outbound only | Inbound and outbound |
| Private inbound address | None. Add a Private Endpoint. | Yes. Internal load balancer IP in the subnet. |
| Public endpoint | Stays open until you disable public access or add access restrictions | Optional. An internal (ILB) deployment has no public IP. |
| NSG and route tables on the subnet | Apply to the app's outbound traffic only | Apply to inbound and outbound traffic |
| Subnet | Delegated to `Microsoft.Web/serverFarms`. /28 minimum, /26 recommended. | Delegated to `Microsoft.Web/hostingEnvironments`. /24 recommended. |
| Tenancy | Shared | Single-tenant |
| Cost and setup | Basic tier and up. Enabled in about a minute. | Isolated v2 pricing, billed for at least one instance. Deployment can take an hour or more. |
| Other services that work this way | Azure Functions (Premium, Flex Consumption, Dedicated), Logic Apps Standard, API Management Standard v2 | SQL Managed Instance, AKS, API Management (Developer/Premium in a VNet), Azure Databricks, Container Apps environments with a custom VNet, Application Gateway, Azure Firewall, Bastion |

Hands-on

## Reproduce it in your subscription

Run these in Azure Cloud Shell (Bash) in one session so the variables persist. Each step moves the lab to the next setup and has a test that proves the change.

### Build the VNet and a private-only VM

This VM is the "internal API". It has no public IP, so only something inside the VNet can reach it.

```
RG=rg-vnetdemo; LOC=centralindia; APP=app-vnetdemo-$RANDOM; echo $APP
az group create -n $RG -l $LOC
az network vnet create -g $RG -n vnet-demo --address-prefix 10.0.0.0/16 \
  --subnet-name snet-vm --subnet-prefixes 10.0.1.0/24
az network vnet subnet create -g $RG --vnet-name vnet-demo -n snet-integration \
  --address-prefixes 10.0.0.0/27 --delegations Microsoft.Web/serverFarms
az vm create -g $RG -n vm-api --image Ubuntu2204 --size Standard_B1s \
  --vnet-name vnet-demo --subnet snet-vm --private-ip-address 10.0.1.4 \
  --public-ip-address "" --nsg-rule NONE \
  --admin-username azureuser --generate-ssh-keys
az vm run-command invoke -g $RG -n vm-api --command-id RunShellScript \
  --scripts "apt-get update -y && apt-get install -y nginx"
```

### Create the app and prove it is cut off

Setup: **Public only**. Open an SSH session into the app container and try the VM.

```
az appservice plan create -g $RG -n plan-demo --sku P0v3 --is-linux
az webapp create -g $RG -p plan-demo -n $APP --runtime "NODE:20-lts"
az webapp ssh -g $RG -n $APP
# inside the app container:
curl -m 5 http://10.0.1.4
```

**Expected:** `curl: (28) Connection timed out`. If `az webapp ssh` is unavailable, use the browser SSH at `https://<app>.scm.azurewebsites.net/webssh/host`.

### Add VNet Integration and retry

Setup: **VNet Integration**. Outbound now works, and the app is still public.

```
az webapp vnet-integration add -g $RG -n $APP --vnet vnet-demo --subnet snet-integration
# in the app's SSH session again:
curl -m 5 http://10.0.1.4                       # 200 OK from nginx
# from your own laptop:
curl -I https://$APP.azurewebsites.net          # still 200: inbound unchanged
# from inside the VNet:
az vm run-command invoke -g $RG -n vm-api --command-id RunShellScript \
  --scripts "nslookup $APP.azurewebsites.net"   # public IP, no private one
```

### Add a Private Endpoint and close the public door

Setup: **Integration + Private Endpoint**. The app gets an inbound IP in `snet-pe`.

```
az network vnet subnet create -g $RG --vnet-name vnet-demo -n snet-pe --address-prefixes 10.0.2.0/27
APP_ID=$(az webapp show -g $RG -n $APP --query id -o tsv)
az network private-endpoint create -g $RG -n pe-app --vnet-name vnet-demo --subnet snet-pe \
  --private-connection-resource-id $APP_ID --group-id sites --connection-name pe-app-conn
az network private-dns zone create -g $RG -n privatelink.azurewebsites.net
az network private-dns link vnet create -g $RG -n link-demo \
  -z privatelink.azurewebsites.net -v vnet-demo -e false
az network private-endpoint dns-zone-group create -g $RG --endpoint-name pe-app -n default \
  --private-dns-zone privatelink.azurewebsites.net --zone-name webapp
az resource update --ids $APP_ID --set properties.publicNetworkAccess=Disabled
```

**Expected:** the VM's `nslookup` now returns `10.0.2.x`, and `curl -I` from your laptop returns `403 Forbidden`.

### Optional: VNet Injection with an internal ASE v3

Setup: **VNet Injection**. The app runs inside `snet-ase`. No integration or private endpoint needed.

```
az network vnet subnet create -g $RG --vnet-name vnet-demo -n snet-ase \
  --address-prefixes 10.0.4.0/24 --delegations Microsoft.Web/hostingEnvironments
az appservice ase create -g $RG -n ase-demo --vnet-name vnet-demo --subnet snet-ase \
  --kind asev3 --virtual-ip-type Internal
ILB=$(az appservice ase list-addresses -g $RG -n ase-demo --query internalIpAddress -o tsv)
Z=ase-demo.appserviceenvironment.net
az network private-dns zone create -g $RG -n $Z
az network private-dns link vnet create -g $RG -n link-ase -z $Z -v vnet-demo -e false
for r in '*' '*.scm' '@'; do
  az network private-dns record-set a add-record -g $RG -z $Z -n "$r" -a $ILB
done
az appservice plan create -g $RG -n plan-ase --app-service-environment ase-demo --sku I1v2 --is-linux
az webapp create -g $RG -p plan-ase -n $APP-ase --runtime "NODE:20-lts"
```

An ASE v3 can take an hour or more to deploy and bills for at least one Isolated v2 instance while it exists. Delete it as soon as you finish the demo.

### Clean up

```
az group delete -n $RG --yes --no-wait
```

Common mistakes

## Things that trip people up

### "We integrated it, so it's private"

Integration changes outbound only. The app keeps answering on its public hostname until you disable public network access or add access restrictions.

### DNS is half the job

Reaching a Private Endpoint by name needs the matching `privatelink.*` Private DNS zone linked to the VNet. Without it, the app resolves the public IP and gets denied.

### NSGs on the integration subnet

Outbound rules apply to the app's traffic. Inbound rules there do nothing for the app, because nothing comes in through that subnet.

### Allow the right source range

Targets in the VNet see integrated calls coming from the integration subnet (here `10.0.0.0/27`). Open firewalls and NSGs for that range, not the app's public outbound IPs.

### Route all traffic

To use a NAT Gateway, Azure Firewall or on-prem routes, the app's outbound internet traffic must be routed into the VNet. Newer apps do this by default; check the app's outbound routing setting on older ones.

### Pick by requirement

Need private outbound only? Integration. Need private inbound too? Add a Private Endpoint. Need full isolation, dedicated compute, or inbound NSG control? Use injection.