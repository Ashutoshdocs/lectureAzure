# Azure Network Watcher End-to-End Lab

## Two Linux VMs, NIC NSG, Subnet NSG, UDR, and Network Watcher

This hands-on lab demonstrates how Azure networking controls affect
traffic between two Linux virtual machines. You will create a virtual
network, one subnet, two VMs, a Network Security Group (NSG) at the
subnet level, another NSG on one VM's network interface (NIC), and a
User Defined Route (UDR). You will then troubleshoot the traffic using
Azure Network Watcher.

The Network Watcher exercises cover:

-   Query on a Log Analytics workspace
-   IP Flow Verify
-   Next hop
-   NSG flow logs
-   Traffic Analytics

> **Lab design note:** Both VMs are placed in the same subnet so you can
> compare subnet-level and NIC-level NSG enforcement on the same traffic
> path. The UDR exercise temporarily adds a `/32` route to the second VM
> with next hop `None` to demonstrate a route-based drop without needing
> a third firewall/router VM. Remove that route at the end.

------------------------------------------------------------------------

## 1. Architecture

``` text
                     Azure Subscription
                            |
                    Resource Group
                            |
                    Virtual Network
                     10.20.0.0/16
                            |
                 Subnet: snet-lab
                  10.20.1.0/24
                  [Subnet NSG]
                      |
          +-----------+------------+
          |                        |
       VM-APP                    VM-CLIENT
     10.20.1.x                   10.20.1.x
          |                        |
      NIC-APP                  NIC-CLIENT
      [NIC NSG]                [No NIC NSG]
          |                        |
          +---- TCP 8080 ----------+
                  Test traffic

       UDR associated with snet-lab
       Temporary route:
       VM-CLIENT-private-IP/32 -> None
```

### Traffic evaluation

For traffic to or from `VM-APP`, Azure evaluates both the subnet NSG and
the NIC NSG. The traffic must be permitted by both NSGs. A rule allowing
traffic in one NSG does not override a deny in the other NSG.

The UDR controls routing, not permission. An NSG can allow a packet
while a route sends it to a different next hop or drops it. Use IP Flow
Verify to inspect NSG decisions and Next hop to inspect routing.

------------------------------------------------------------------------

## 2. Prerequisites

-   An Azure subscription with permission to create resource groups,
    VNets, NSGs, NICs, VMs, route tables, and Network Watcher
    diagnostics.
-   Azure CLI installed.
-   A Linux terminal, Azure Cloud Shell, or an Ubuntu administration VM.
-   An SSH key pair.
-   For SSH access, know your public IP address.

Sign in and select the subscription:

``` bash
az login
az account show --output table
az account set --subscription "<SUBSCRIPTION_ID>"
```

Check your CLI version:

``` bash
az version
```

Set the lab variables. Change the names if they already exist in your
subscription:

``` bash
LOCATION="centralindia"
RG="rg-networkwatcher-lab"
VNET="vnet-nw-lab"
SUBNET="snet-lab"
NSG_SUBNET="nsg-subnet-lab"
NSG_NIC="nsg-nic-app"
NIC_APP="nic-vm-app"
NIC_CLIENT="nic-vm-client"
VM_APP="vm-app"
VM_CLIENT="vm-client"
RT="rt-lab"
```

Create the resource group:

``` bash
az group create \
  --name "$RG" \
  --location "$LOCATION"
```

------------------------------------------------------------------------

## 3. Create the VNet and one subnet

Create a VNet with one subnet:

``` bash
az network vnet create \
  --resource-group "$RG" \
  --name "$VNET" \
  --location "$LOCATION" \
  --address-prefixes 10.20.0.0/16 \
  --subnet-name "$SUBNET" \
  --subnet-prefixes 10.20.1.0/24
```

Get the subnet resource ID:

``` bash
SUBNET_ID=$(az network vnet subnet show \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$SUBNET" \
  --query id -o tsv)

echo "$SUBNET_ID"
```

------------------------------------------------------------------------

## 4. Create the subnet-level NSG

Create the NSG:

``` bash
az network nsg create \
  --resource-group "$RG" \
  --name "$NSG_SUBNET" \
  --location "$LOCATION"
```

Create an inbound rule allowing SSH only from your public IP. Replace
`YOUR_PUBLIC_IP` with your public IPv4 address in CIDR format, for
example `203.0.113.10/32` (use your actual address, not this
documentation example).

``` bash
MY_PUBLIC_IP="YOUR_PUBLIC_IP/32"

az network nsg rule create \
  --resource-group "$RG" \
  --nsg-name "$NSG_SUBNET" \
  --name Allow-SSH-From-Admin \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes "$MY_PUBLIC_IP" \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 22
```

Allow the lab's TCP application port between the two VMs:

``` bash
az network nsg rule create \
  --resource-group "$RG" \
  --nsg-name "$NSG_SUBNET" \
  --name Allow-App-8080 \
  --priority 110 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes 10.20.1.0/24 \
  --source-port-ranges '*' \
  --destination-address-prefixes 10.20.1.0/24 \
  --destination-port-ranges 8080
```

Associate this NSG with the subnet:

``` bash
az network vnet subnet update \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$SUBNET" \
  --network-security-group "$NSG_SUBNET"
```

Verify:

``` bash
az network vnet subnet show \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$SUBNET" \
  --query "{name:name,prefix:addressPrefix,nsg:networkSecurityGroup.id}" \
  --output json
```

------------------------------------------------------------------------

## 5. Create a second NSG for the VM-APP NIC

Create the NIC-level NSG:

``` bash
az network nsg create \
  --resource-group "$RG" \
  --name "$NSG_NIC" \
  --location "$LOCATION"
```

Allow SSH from your administration IP:

``` bash
az network nsg rule create \
  --resource-group "$RG" \
  --nsg-name "$NSG_NIC" \
  --name Allow-SSH-From-Admin \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes "$MY_PUBLIC_IP" \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 22
```

Allow TCP 8080 from the lab subnet:

``` bash
az network nsg rule create \
  --resource-group "$RG" \
  --nsg-name "$NSG_NIC" \
  --name Allow-App-8080 \
  --priority 110 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes 10.20.1.0/24 \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 8080
```

At this point, the subnet NSG applies to both VMs. The NIC NSG will be
attached only to `VM-APP`.

------------------------------------------------------------------------

## 6. Create the two VM NICs

Create the application VM NIC and attach the NIC NSG:

``` bash
az network nic create \
  --resource-group "$RG" \
  --name "$NIC_APP" \
  --location "$LOCATION" \
  --vnet-name "$VNET" \
  --subnet "$SUBNET" \
  --network-security-group "$NSG_NIC"
```

Create the client VM NIC without a NIC-level NSG:

``` bash
az network nic create \
  --resource-group "$RG" \
  --name "$NIC_CLIENT" \
  --location "$LOCATION" \
  --vnet-name "$VNET" \
  --subnet "$SUBNET"
```

Get the NIC IDs:

``` bash
NIC_APP_ID=$(az network nic show -g "$RG" -n "$NIC_APP" --query id -o tsv)
NIC_CLIENT_ID=$(az network nic show -g "$RG" -n "$NIC_CLIENT" --query id -o tsv)
```

------------------------------------------------------------------------

## 7. Create the two Linux VMs

Use an existing SSH public key. Update the path if your key is stored
elsewhere:

``` bash
SSH_PUBLIC_KEY="$HOME/.ssh/id_rsa.pub"
test -f "$SSH_PUBLIC_KEY" || { echo "Public key not found: $SSH_PUBLIC_KEY"; exit 1; }
```

Create `VM-APP`:

``` bash
az vm create \
  --resource-group "$RG" \
  --name "$VM_APP" \
  --location "$LOCATION" \
  --nics "$NIC_APP_ID" \
  --image Ubuntu2404 \
  --size Standard_B1s \
  --admin-username azureuser \
  --ssh-key-values "$SSH_PUBLIC_KEY" \
  --public-ip-sku Standard
```

Create `VM-CLIENT`:

``` bash
az vm create \
  --resource-group "$RG" \
  --name "$VM_CLIENT" \
  --location "$LOCATION" \
  --nics "$NIC_CLIENT_ID" \
  --image Ubuntu2404 \
  --size Standard_B1s \
  --admin-username azureuser \
  --ssh-key-values "$SSH_PUBLIC_KEY" \
  --public-ip-sku Standard
```

> For a cost-conscious lab, stop and deallocate the VMs when you are not
> using them. VM, disk, and public IP charges may apply. Check regional
> VM SKU availability and subscription quota before deployment.

Get private and public IP addresses:

``` bash
az vm list-ip-addresses \
  --resource-group "$RG" \
  --output table
```

Store the private IPs for later commands:

``` bash
APP_PRIVATE_IP=$(az vm show -d -g "$RG" -n "$VM_APP" --query privateIps -o tsv)
CLIENT_PRIVATE_IP=$(az vm show -d -g "$RG" -n "$VM_CLIENT" --query privateIps -o tsv)

APP_PUBLIC_IP=$(az vm show -d -g "$RG" -n "$VM_APP" --query publicIps -o tsv)
CLIENT_PUBLIC_IP=$(az vm show -d -g "$RG" -n "$VM_CLIENT" --query publicIps -o tsv)

printf "APP private: %s | public: %s\n" "$APP_PRIVATE_IP" "$APP_PUBLIC_IP"
printf "CLIENT private: %s | public: %s\n" "$CLIENT_PRIVATE_IP" "$CLIENT_PUBLIC_IP"
```

------------------------------------------------------------------------

## 8. Configure a simple application on VM-APP

SSH to the application VM:

``` bash
ssh azureuser@"$APP_PUBLIC_IP"
```

Install Python and start a simple HTTP server on TCP port 8080:

``` bash
sudo apt-get update
sudo apt-get install -y python3
mkdir -p ~/nw-demo
echo "Hello from VM-APP - Network Watcher lab" > ~/nw-demo/index.html
cd ~/nw-demo
python3 -m http.server 8080 --bind 0.0.0.0
```

Keep this terminal open while testing. In a second terminal, SSH to the
client VM:

``` bash
ssh azureuser@"$CLIENT_PUBLIC_IP"
```

Test private-IP connectivity from `VM-CLIENT` to `VM-APP`:

``` bash
curl --connect-timeout 5 "http://APP_PRIVATE_IP:8080"
```

Replace `APP_PRIVATE_IP` with the actual private IP printed earlier, or
run the command from your administration shell after substituting the
value. Expected response:

``` text
Hello from VM-APP - Network Watcher lab
```

If it fails, check that the Python server is running and inspect both
NSGs before continuing.

------------------------------------------------------------------------

## 9. Demonstrate NIC NSG versus subnet NSG

### Test A --- Allow traffic

The subnet NSG allows TCP 8080 from `10.20.1.0/24`, and the NIC NSG on
`VM-APP` also allows TCP 8080 from that subnet.

From `VM-CLIENT`:

``` bash
curl --connect-timeout 5 "http://APP_PRIVATE_IP:8080"
```

Expected: the request succeeds.

### Test B --- Deny at the NIC NSG

Create a higher-priority deny rule on the NIC NSG:

``` bash
az network nsg rule create \
  --resource-group "$RG" \
  --nsg-name "$NSG_NIC" \
  --name Deny-App-8080-Demo \
  --priority 105 \
  --direction Inbound \
  --access Deny \
  --protocol Tcp \
  --source-address-prefixes 10.20.1.0/24 \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 8080
```

Retry from `VM-CLIENT`:

``` bash
curl --connect-timeout 5 "http://APP_PRIVATE_IP:8080"
```

Expected: the connection fails because the NIC NSG deny rule takes
precedence over its lower-priority allow rule. The subnet NSG allow rule
cannot override the NIC NSG deny.

Remove the demo deny rule:

``` bash
az network nsg rule delete \
  --resource-group "$RG" \
  --nsg-name "$NSG_NIC" \
  --name Deny-App-8080-Demo
```

Retry the curl test. It should work again, assuming the service is still
running.

### Test C --- Deny at the subnet NSG

Add a deny rule to the subnet NSG:

``` bash
az network nsg rule create \
  --resource-group "$RG" \
  --nsg-name "$NSG_SUBNET" \
  --name Deny-App-8080-Demo \
  --priority 105 \
  --direction Inbound \
  --access Deny \
  --protocol Tcp \
  --source-address-prefixes 10.20.1.0/24 \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 8080
```

Retry the curl test. Expected: failure, even though the NIC NSG allows
the traffic.

Remove the subnet deny rule:

``` bash
az network nsg rule delete \
  --resource-group "$RG" \
  --nsg-name "$NSG_SUBNET" \
  --name Deny-App-8080-Demo
```

**Teaching point:** For a flow to be allowed, every NSG applied to the
relevant NIC/subnet path must allow it. A deny in either NSG blocks the
flow.

------------------------------------------------------------------------

## 10. Create and associate a UDR

Create a route table:

``` bash
az network route-table create \
  --resource-group "$RG" \
  --name "$RT" \
  --location "$LOCATION"
```

Associate it with the lab subnet:

``` bash
az network vnet subnet update \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$SUBNET" \
  --route-table "$RT"
```

Verify the association:

``` bash
az network vnet subnet show \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$SUBNET" \
  --query "{subnet:name,routeTable:routeTable.id}" \
  --output json
```

### Test D --- Add a temporary route that drops traffic to VM-APP

Create a host route for the application VM's private IP. The `None` next
hop drops matching traffic:

``` bash
az network route-table route create \
  --resource-group "$RG" \
  --route-table-name "$RT" \
  --name Drop-VM-APP-Demo \
  --address-prefix "$APP_PRIVATE_IP/32" \
  --next-hop-type None
```

From `VM-CLIENT`, retry:

``` bash
curl --connect-timeout 5 "http://APP_PRIVATE_IP:8080"
```

Expected: failure. The route table now contains a more-specific route
for the app VM address that drops traffic.

### Remove the temporary route

``` bash
az network route-table route delete \
  --resource-group "$RG" \
  --route-table-name "$RT" \
  --name Drop-VM-APP-Demo
```

Retry the curl test. It should succeed again if the NSGs and application
are configured correctly.

> The route table remains associated with the subnet, but with the
> custom route removed Azure uses the applicable system routes. The
> temporary `/32` route is only a teaching demonstration; it is not a
> recommended production routing design.

------------------------------------------------------------------------

## 11. Network Watcher --- enable and inspect

Network Watcher is a regional Azure networking diagnostic service. It
must be available in the region where the VM resources are deployed.

List Network Watcher instances:

``` bash
az network watcher list --output table
```

Enable it in the lab region if it is not already enabled:

``` bash
az network watcher configure \
  --resource-group "$RG" \
  --locations "$LOCATION" \
  --enabled true
```

Get the Network Watcher name:

``` bash
NW_NAME=$(az network watcher list \
  --query "[?location=='$LOCATION'].name | [0]" -o tsv)

echo "$NW_NAME"
```

### 11.1 IP Flow Verify

IP Flow Verify checks whether a specific packet is allowed or denied by
NSG rules. Run it against the destination VM NIC while the deny rule is
present, then remove the deny rule and run it again.

Example inbound check for TCP 8080 to VM-APP:

``` bash
az network watcher test-ip-flow \
  --resource-group "$RG" \
  --vm "$VM_APP" \
  --direction Inbound \
  --protocol TCP \
  --local "$APP_PRIVATE_IP:8080" \
  --remote "10.20.1.5:50000"
```

Replace `10.20.1.5` with the actual client private IP. Expected output
identifies `Allow` or `Deny` and the NSG rule responsible.

Use this while `Deny-App-8080-Demo` exists on the NIC NSG or subnet NSG
to show the deny decision. Remove the deny rule and repeat to show the
allow decision.

### 11.2 Next hop

Next hop reports the route decision Azure uses from a VM to a
destination IP. Run it while the temporary `/32` drop route exists, and
again after deleting it.

``` bash
az network watcher show-next-hop \
  --resource-group "$RG" \
  --vm "$VM_CLIENT" \
  --source-ip "$CLIENT_PRIVATE_IP" \
  --dest-ip "$APP_PRIVATE_IP"
```

With the temporary route installed, the result should show next hop type
`None`. After removing the route, the destination is on the same
VNet/subnet and should use the virtual network route.

### 11.3 Connection troubleshoot

Connection troubleshoot checks connectivity from a source VM to a
destination, and can help identify the failing component.

``` bash
az network watcher test-connectivity \
  --resource-group "$RG" \
  --source-resource "$VM_CLIENT" \
  --dest-address "$APP_PRIVATE_IP" \
  --dest-port 8080 \
  --protocol Tcp
```

Run it once when the flow is allowed, then again with the NIC/subnet
deny rule or UDR drop route enabled. Compare the results.

### 11.4 NSG flow logs

NSG flow logs record network traffic information for an NSG and can help
analyze allowed and denied flows. **Important:** Azure NSG flow logs are
being retired; new deployments should use Virtual Network flow logs. If
your subscription/region still exposes NSG flow logs, use the portal's
Network Watcher \> NSG flow logs workflow for an existing supported
configuration. For a new lab, prefer Virtual Network flow logs.

For a portal walkthrough: 1. Open **Network Watcher**. 2. Open **Logs**
or **Flow logs** (the blade label can vary). 3. Select **Virtual network
flow logs** for the lab VNet. 4. Select a storage account for log
storage. 5. Enable traffic analytics if the portal offers it and you
have a Log Analytics workspace. 6. Save the configuration and generate
traffic by running the curl tests. 7. Review the flow log status and the
generated records.

Do not assume that creating an NSG automatically enables flow logging.

### 11.5 Traffic Analytics

Traffic Analytics analyzes flow-log data and presents traffic patterns,
top talkers, allowed/denied traffic, and related insights in a Log
Analytics workspace.

High-level setup: 1. Create or select a Log Analytics workspace in a
supported region. 2. Configure Virtual Network flow logs for the lab
VNet. 3. Enable Traffic Analytics and select the workspace. 4. Generate
both allowed and denied traffic using the tests above. 5. Open the
workspace and Traffic Analytics views to review the processed data.

Processing is not necessarily instantaneous. Allow time for flow-log
ingestion and analytics processing. Availability, retention, and
supported configuration options depend on the current Azure region and
service lifecycle.

### 11.6 Query on a Log Analytics workspace

Once flow logs are sent to a Log Analytics workspace, open the workspace
and select **Logs**. The exact table and schema depend on the flow-log
version and destination configuration. Start by discovering available
tables:

``` kusto
search *
| summarize Records=count() by $table
| order by Records desc
```

For Virtual Network flow logs using the resource-specific `VNetFlow`
table, a basic discovery query is:

``` kusto
VNetFlow
| take 20
```

After confirming the columns in your workspace, summarize traffic by
source and destination. Example for a schema containing `SrcIp`,
`DestIp`, `DestPort`, and `FlowDirection`:

``` kusto
VNetFlow
| summarize FlowCount=count() by SrcIp, DestIp, DestPort, FlowDirection
| order by FlowCount desc
```

If your workspace uses a different schema or legacy table, inspect the
table's **Schema** pane and adapt the query. Do not assume these column
names exist in every workspace.

------------------------------------------------------------------------

## 12. End-to-end test matrix

  -----------------------------------------------------------------------
  Test              Configuration     Expected result   Network Watcher
                                                        tool
  ----------------- ----------------- ----------------- -----------------
  1                 Subnet and NIC    curl succeeds     IP Flow Verify:
                    NSGs allow TCP                      Allow
                    8080                                

  2                 NIC NSG denies    curl fails        IP Flow Verify:
                    TCP 8080                            Deny

  3                 Subnet NSG denies curl fails        IP Flow Verify:
                    TCP 8080                            Deny

  4                 Remove both deny  curl succeeds     IP Flow Verify:
                    rules                               Allow

  5                 UDR route to app  curl fails        Next hop: None
                    IP uses `None`                      

  6                 Delete temporary  curl succeeds     Next hop:
                    UDR route                           VirtualNetwork

  7                 Run connection    Reports           Connection
                    troubleshoot      connectivity      troubleshoot
                                      status            

  8                 Enable flow logs  Flow records      Flow logs /
                    and generate      appear after      Traffic Analytics
                    traffic           ingestion         / Logs
  -----------------------------------------------------------------------

------------------------------------------------------------------------

## 13. Useful verification commands

List NSGs:

``` bash
az network nsg list -g "$RG" -o table
```

Show subnet NSG rules:

``` bash
az network nsg rule list -g "$RG" --nsg-name "$NSG_SUBNET" -o table
```

Show NIC NSG rules:

``` bash
az network nsg rule list -g "$RG" --nsg-name "$NSG_NIC" -o table
```

Show NIC configuration:

``` bash
az network nic show -g "$RG" -n "$NIC_APP" \
  --query "{name:name,privateIp:ipConfigurations[0].privateIPAddress,nsg:networkSecurityGroup.id,subnet:ipConfigurations[0].subnet.id}" \
  -o json
```

Show route table and routes:

``` bash
az network route-table show -g "$RG" -n "$RT" -o json
az network route-table route list -g "$RG" --route-table-name "$RT" -o table
```

Show effective routes on a NIC:

``` bash
az network nic show-effective-route-table \
  --resource-group "$RG" \
  --name "$NIC_CLIENT" \
  --output table
```

Show effective NSG rules on a NIC:

``` bash
az network nic list-effective-nsg \
  --resource-group "$RG" \
  --name "$NIC_APP" \
  --output json
```

------------------------------------------------------------------------

## 14. Troubleshooting checklist

-   Confirm the Python HTTP server is running and listening on
    `0.0.0.0:8080`.
-   Confirm you are testing the VM's private IP from the other VM.
-   Check the subnet NSG and NIC NSG independently. Both must permit the
    flow.
-   Check rule priorities: lower numeric priority is evaluated first.
-   Confirm the UDR is associated with the subnet and the custom route
    has the intended prefix and next hop.
-   Use IP Flow Verify for NSG decisions and Next hop for route
    decisions; they answer different questions.
-   Confirm the Network Watcher instance is enabled in the VM region.
-   Check guest OS firewall rules if Azure NSGs allow the traffic but
    the connection still fails.
-   Confirm the VM is running and the destination service is listening.
-   For flow logs and Traffic Analytics, verify the correct VNet,
    storage account, workspace, and region configuration, and allow for
    ingestion delay.

------------------------------------------------------------------------

## 15. Cleanup --- avoid ongoing Azure charges

Delete the entire lab resource group when finished:

``` bash
az group delete \
  --name "$RG" \
  --yes \
  --no-wait
```

Check deletion:

``` bash
az group exists --name "$RG"
```

Expected result after deletion completes:

``` text
false
```

------------------------------------------------------------------------

## 16. Key concepts to explain

1.  **NIC NSG:** filters traffic at the network interface.
2.  **Subnet NSG:** filters traffic at the subnet boundary.
3.  **Two NSGs:** when both apply to a flow, both must allow it.
4.  **UDR:** changes the next-hop route; it does not grant or deny
    permission like an NSG.
5.  **IP Flow Verify:** identifies the NSG rule decision for a specific
    five-tuple-style flow.
6.  **Next hop:** shows the route decision from a VM toward a
    destination IP.
7.  **Connection troubleshoot:** tests end-to-end connectivity and helps
    isolate the failing component.
8.  **Flow logs:** capture network flow information for analysis.
9.  **Traffic Analytics:** analyzes flow-log data and visualizes traffic
    patterns.
10. **Log Analytics query:** lets you investigate ingested records using
    Kusto Query Language (KQL).

**Final teaching takeaway:** NSGs answer "is this traffic permitted?",
while route tables answer "where should this traffic go?". Network
Watcher helps investigate both sides of the connectivity path.
