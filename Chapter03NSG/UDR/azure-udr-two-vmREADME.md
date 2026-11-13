# Azure UDR End-to-End Demo --- Only 2 Virtual Machines (No Azure Firewall)

## Use VM-1 as a Linux Router/NAT Gateway and VM-2 as a Private Workload

This practical demonstrates how an Azure **User Defined Route (UDR)**
changes the network path using exactly **two Azure Linux VMs**. No Azure
Firewall, third VM, VPN Gateway, or other network appliance is deployed.

-   **VM-1 (`vm-router`)**: Linux router, NAT gateway, and jump host. It
    has a public IP for administration and IP forwarding enabled on its
    NIC.
-   **VM-2 (`vm-private`)**: Private workload VM. It has no public IP.
-   **UDR**: Associated with VM-2's subnet. It sends `0.0.0.0/0` to
    VM-1's private IP using next-hop type `Virtual appliance`.
-   **Linux IP forwarding + NAT** on VM-1: forwards VM-2's outbound
    traffic and translates its source address so replies return through
    VM-1.

> **Important:** This is a learning demonstration of UDR and a
> self-managed Linux network virtual appliance (NVA). A single Linux VM
> is a single point of failure and is not a production-grade replacement
> for Azure Firewall or a highly available NVA solution. For production,
> use a supported HA design with redundancy, health monitoring,
> patching, capacity planning, and tested failover. The lab itself uses
> only two VMs.

------------------------------------------------------------------------

## 1. What you will build

``` text
                       Internet
                           |
                    VM-1 Public IP
                           |
                    Azure VNet
                     10.60.0.0/16
                           |
             +-------------+--------------+
             |                            |
        snet-router                  snet-private
        10.60.1.0/24                 10.60.2.0/24
             |                            |
        VM-1: vm-router               VM-2: vm-private
        10.60.1.4                    10.60.2.4
        Public IP: Yes               Public IP: No
        IP forwarding: ON            IP forwarding: OFF
        Linux IP forwarding           Default route via VM-1
        NAT (MASQUERADE)                    |
             |                              |
             +--------- UDR ----------------+
                 0.0.0.0/0
                 Next hop: Virtual appliance
                 Next hop IP: 10.60.1.4
```

### Traffic path

When VM-2 accesses an internet destination:

``` text
VM-2 (10.60.2.4)
       |
       | Route table on snet-private
       | 0.0.0.0/0 -> Virtual appliance 10.60.1.4
       v
VM-1 (10.60.1.4)
       |
       | Linux IP forwarding + NAT
       v
Internet
```

The reply returns to VM-1 because NAT changed the source address. Linux
connection tracking reverses the NAT and forwards the reply to VM-2.

### What this lab proves

1.  Without a UDR, VM-2 uses Azure's default system route for internet
    traffic.
2.  With a UDR, VM-2 sends internet-bound traffic to VM-1.
3.  Azure requires IP forwarding enabled on the VM-1 NIC when it
    forwards packets not addressed to itself.
4.  Linux must also have IP forwarding enabled.
5.  NAT on VM-1 allows VM-2 to use VM-1's outbound connectivity.
6.  Removing the UDR changes VM-2's route selection again.

------------------------------------------------------------------------

## 2. Prerequisites

-   Azure subscription and permission to create resource groups, VNets,
    subnets, NSGs, route tables, NICs, VMs, and public IPs.
-   Azure CLI installed and authenticated.
-   SSH key pair.
-   Your current public IPv4 address for restricted SSH access.

Sign in:

``` bash
az login
az account show --output table
az account set --subscription "<SUBSCRIPTION_ID>"
```

Set variables:

``` bash
LOCATION="centralindia"
RG="rg-udr-two-vm-lab"

VNET="vnet-udr-lab"
ROUTER_SUBNET="snet-router"
PRIVATE_SUBNET="snet-private"

ROUTER_NSG="nsg-router"
PRIVATE_NSG="nsg-private"

ROUTER_NIC="nic-vm-router"
PRIVATE_NIC="nic-vm-private"

ROUTER_VM="vm-router"
PRIVATE_VM="vm-private"

ROUTE_TABLE="rt-private-default-via-router"

ADMIN_CIDR="YOUR_PUBLIC_IP/32"
SSH_PUBLIC_KEY="$HOME/.ssh/id_rsa.pub"
```

Replace `YOUR_PUBLIC_IP/32` with your actual public IPv4 address in CIDR
format. Do not use `0.0.0.0/0` for SSH.

Check your public key:

``` bash
test -f "$SSH_PUBLIC_KEY" || {
  echo "SSH public key not found: $SSH_PUBLIC_KEY"
  exit 1
}
```

------------------------------------------------------------------------

## 3. Create the resource group and VNet

``` bash
az group create \
  --name "$RG" \
  --location "$LOCATION"
```

Create the VNet and router subnet:

``` bash
az network vnet create \
  --resource-group "$RG" \
  --name "$VNET" \
  --location "$LOCATION" \
  --address-prefixes 10.60.0.0/16 \
  --subnet-name "$ROUTER_SUBNET" \
  --subnet-prefixes 10.60.1.0/24
```

Create the private workload subnet:

``` bash
az network vnet subnet create \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$PRIVATE_SUBNET" \
  --address-prefixes 10.60.2.0/24
```

Get subnet IDs:

``` bash
ROUTER_SUBNET_ID=$(az network vnet subnet show \
  -g "$RG" --vnet-name "$VNET" -n "$ROUTER_SUBNET" --query id -o tsv)

PRIVATE_SUBNET_ID=$(az network vnet subnet show \
  -g "$RG" --vnet-name "$VNET" -n "$PRIVATE_SUBNET" --query id -o tsv)
```

------------------------------------------------------------------------

## 4. Create NSGs

### 4.1 Router VM NSG

``` bash
az network nsg create \
  --resource-group "$RG" \
  --name "$ROUTER_NSG" \
  --location "$LOCATION"
```

Allow SSH to VM-1 only from your admin IP:

``` bash
az network nsg rule create \
  --resource-group "$RG" \
  --nsg-name "$ROUTER_NSG" \
  --name Allow-SSH-Admin \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes "$ADMIN_CIDR" \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 22
```

Allow forwarded traffic from VM-2's subnet to reach the router VM. This
rule is scoped to the private workload subnet:

``` bash
az network nsg rule create \
  --resource-group "$RG" \
  --nsg-name "$ROUTER_NSG" \
  --name Allow-Forwarded-From-Private-Subnet \
  --priority 110 \
  --direction Inbound \
  --access Allow \
  --protocol '*' \
  --source-address-prefixes 10.60.2.0/24 \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges '*'
```

### 4.2 Private VM NSG

``` bash
az network nsg create \
  --resource-group "$RG" \
  --name "$PRIVATE_NSG" \
  --location "$LOCATION"
```

Allow SSH to VM-2 only from VM-1's subnet. This supports administration
through VM-1 as a jump host:

``` bash
az network nsg rule create \
  --resource-group "$RG" \
  --nsg-name "$PRIVATE_NSG" \
  --name Allow-SSH-From-Router-Subnet \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes 10.60.1.0/24 \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 22
```

Associate each NSG with its subnet:

``` bash
az network vnet subnet update \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$ROUTER_SUBNET" \
  --network-security-group "$ROUTER_NSG"

az network vnet subnet update \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$PRIVATE_SUBNET" \
  --network-security-group "$PRIVATE_NSG"
```

> NSGs are stateful. The rules above are for this focused lab. In a
> production implementation, explicitly design inbound and outbound
> rules, management access, monitoring, DNS, and required platform
> dependencies.

------------------------------------------------------------------------

## 5. Create VM-1 (Linux router)

Create VM-1 in the router subnet with a public IP for administration:

``` bash
az vm create \
  --resource-group "$RG" \
  --name "$ROUTER_VM" \
  --location "$LOCATION" \
  --image Ubuntu2404 \
  --size Standard_B1s \
  --vnet-name "$VNET" \
  --subnet "$ROUTER_SUBNET" \
  --nsg "" \
  --admin-username azureuser \
  --ssh-key-values "$SSH_PUBLIC_KEY" \
  --public-ip-sku Standard
```

Get VM-1's NIC name, private IP, and public IP:

``` bash
ROUTER_NIC_ID=$(az vm show -g "$RG" -n "$ROUTER_VM" \
  --query "networkProfile.networkInterfaces[0].id" -o tsv)

ROUTER_NIC_NAME=$(basename "$ROUTER_NIC_ID")

ROUTER_PRIVATE_IP=$(az vm show -d -g "$RG" -n "$ROUTER_VM" \
  --query privateIps -o tsv)

ROUTER_PUBLIC_IP=$(az vm show -d -g "$RG" -n "$ROUTER_VM" \
  --query publicIps -o tsv)

printf "Router private IP: %s\nRouter public IP: %s\nNIC: %s\n" \
  "$ROUTER_PRIVATE_IP" "$ROUTER_PUBLIC_IP" "$ROUTER_NIC_NAME"
```

The expected router private IP is in `10.60.1.0/24`.

------------------------------------------------------------------------

## 6. Enable Azure NIC IP forwarding on VM-1

This is a critical step. Azure must allow VM-1's NIC to forward packets
whose source/destination IPs are not simply the VM's own IP.

``` bash
az network nic update \
  --resource-group "$RG" \
  --name "$ROUTER_NIC_NAME" \
  --ip-forwarding true
```

Verify:

``` bash
az network nic show \
  --resource-group "$RG" \
  --name "$ROUTER_NIC_NAME" \
  --query "{nic:name,enableIPForwarding:enableIPForwarding}" \
  --output table
```

Expected: `enableIPForwarding` is `true`.

**Do not confuse these two settings:**

-   Azure NIC IP forwarding: Azure platform setting on the NIC.
-   Linux IP forwarding: operating-system setting inside Ubuntu.

Both are required for this router design.

------------------------------------------------------------------------

## 7. Create VM-2 (private workload VM)

Create VM-2 in the private subnet. Do not assign it a public IP:

``` bash
az vm create \
  --resource-group "$RG" \
  --name "$PRIVATE_VM" \
  --location "$LOCATION" \
  --image Ubuntu2404 \
  --size Standard_B1s \
  --vnet-name "$VNET" \
  --subnet "$PRIVATE_SUBNET" \
  --nsg "" \
  --public-ip-address "" \
  --admin-username azureuser \
  --ssh-key-values "$SSH_PUBLIC_KEY"
```

Get VM-2's private IP and NIC:

``` bash
PRIVATE_NIC_ID=$(az vm show -g "$RG" -n "$PRIVATE_VM" \
  --query "networkProfile.networkInterfaces[0].id" -o tsv)

PRIVATE_NIC_NAME=$(basename "$PRIVATE_NIC_ID")

PRIVATE_VM_IP=$(az vm show -d -g "$RG" -n "$PRIVATE_VM" \
  --query privateIps -o tsv)

printf "Private VM IP: %s\nNIC: %s\n" "$PRIVATE_VM_IP" "$PRIVATE_NIC_NAME"
```

Confirm VM-2 has no public IP:

``` bash
az vm show -d -g "$RG" -n "$PRIVATE_VM" \
  --query "{name:name,privateIps:privateIps,publicIps:publicIps}" \
  --output table
```

------------------------------------------------------------------------

## 8. Configure Linux routing and NAT on VM-1

SSH to VM-1:

``` bash
ssh azureuser@"$ROUTER_PUBLIC_IP"
```

Install the required packages:

``` bash
sudo apt-get update
sudo apt-get install -y iptables-persistent curl
```

Identify the network interface and default gateway:

``` bash
ip -br address
ip route
```

On a typical Azure Ubuntu VM, the primary interface is often `eth0`. Do
not assume; confirm it with `ip route`. Set the interface variable based
on the output:

``` bash
WAN_IF="eth0"
```

Enable Linux IPv4 forwarding immediately:

``` bash
sudo sysctl -w net.ipv4.ip_forward=1
```

Persist it across reboots:

``` bash
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-azure-router.conf
sudo sysctl --system
```

Verify:

``` bash
sysctl net.ipv4.ip_forward
```

Expected:

``` text
net.ipv4.ip_forward = 1
```

Configure NAT for traffic arriving from VM-2's subnet and leaving
through VM-1's primary interface:

``` bash
sudo iptables -t nat -A POSTROUTING \
  -s 10.60.2.0/24 \
  -o "$WAN_IF" \
  -j MASQUERADE
```

Allow forwarding from the private subnet to the internet:

``` bash
sudo iptables -A FORWARD \
  -s 10.60.2.0/24 \
  -o "$WAN_IF" \
  -m conntrack --ctstate NEW,ESTABLISHED,RELATED \
  -j ACCEPT
```

Allow return traffic:

``` bash
sudo iptables -A FORWARD \
  -d 10.60.2.0/24 \
  -i "$WAN_IF" \
  -m conntrack --ctstate ESTABLISHED,RELATED \
  -j ACCEPT
```

Persist the rules:

``` bash
sudo netfilter-persistent save
```

Verify the rules:

``` bash
sudo iptables -t nat -L POSTROUTING -n -v
sudo iptables -L FORWARD -n -v
```

> If you use UFW or another host firewall, check its forwarding policy.
> A host firewall can block forwarded traffic even when IP forwarding
> and NAT are configured. Do not disable host security controls blindly
> in a production environment.

Exit VM-1:

``` bash
exit
```

------------------------------------------------------------------------

## 9. Create the UDR route table

Create a route table:

``` bash
az network route-table create \
  --resource-group "$RG" \
  --name "$ROUTE_TABLE" \
  --location "$LOCATION"
```

Add the default route. This is the key step of the practical:

``` bash
az network route-table route create \
  --resource-group "$RG" \
  --route-table-name "$ROUTE_TABLE" \
  --name Default-Route-Via-Linux-Router \
  --address-prefix 0.0.0.0/0 \
  --next-hop-type VirtualAppliance \
  --next-hop-ip-address "$ROUTER_PRIVATE_IP"
```

This means:

-   Destination: all IPv4 destinations not matched by a more-specific
    route.
-   Next-hop type: `Virtual appliance`.
-   Next-hop IP: VM-1's private IP.

Associate the route table with VM-2's subnet:

``` bash
az network vnet subnet update \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$PRIVATE_SUBNET" \
  --route-table "$ROUTE_TABLE"
```

Verify the association:

``` bash
az network vnet subnet show \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$PRIVATE_SUBNET" \
  --query "{subnet:name,routeTable:routeTable.id}" \
  --output json
```

------------------------------------------------------------------------

## 10. Test the end-to-end UDR path

### 10.1 Connect to VM-2 through VM-1

VM-2 has no public IP. Use VM-1 as a jump host:

``` bash
ssh -J azureuser@"$ROUTER_PUBLIC_IP" azureuser@"$PRIVATE_VM_IP"
```

If your SSH client does not support `-J`, connect to VM-1 first and then
SSH to VM-2 using its private IP.

### 10.2 Check VM-2's route

On VM-2:

``` bash
ip route
ip route get 8.8.8.8
```

The OS may show its default gateway as the Azure subnet virtual router.
Azure applies the UDR in the platform data path; the guest OS route
table does not necessarily display the UDR next hop as a Linux gateway.

### 10.3 Test outbound connectivity

On VM-2:

``` bash
curl -4 https://ifconfig.me
```

Expected: the request succeeds. The observed public egress address
should be associated with VM-1's outbound path, not a public IP on VM-2.

Test DNS and HTTPS separately if needed:

``` bash
getent hosts example.com
curl -I --connect-timeout 10 https://example.com
```

### 10.4 Observe NAT on VM-1

On VM-1, run:

``` bash
sudo iptables -t nat -L POSTROUTING -n -v
sudo iptables -L FORWARD -n -v
```

Run curl again from VM-2. Packet counters should increase on the NAT and
forwarding rules.

You can also observe packets on VM-1:

``` bash
sudo tcpdump -ni any 'host 8.8.8.8'
```

------------------------------------------------------------------------

## 11. Demonstrate the UDR effect: remove and restore it

### Test A --- UDR enabled

Confirm the route exists:

``` bash
az network route-table route show \
  --resource-group "$RG" \
  --route-table-name "$ROUTE_TABLE" \
  --name Default-Route-Via-Linux-Router \
  --output table
```

From VM-2:

``` bash
curl -4 --connect-timeout 10 https://ifconfig.me
```

Expected: outbound access succeeds through VM-1's forwarding/NAT path.

### Test B --- Delete the UDR route

From the administration terminal:

``` bash
az network route-table route delete \
  --resource-group "$RG" \
  --route-table-name "$ROUTE_TABLE" \
  --name Default-Route-Via-Linux-Router
```

VM-2's subnet now uses the applicable Azure system route for
internet-bound traffic. Depending on the VM's outbound access
configuration and current Azure platform behavior, direct internet
access may or may not be available. This is why the lab explicitly
configures VM-2 without a public IP and uses VM-1 as its intended egress
path.

Test again from VM-2:

``` bash
curl -4 --connect-timeout 10 https://ifconfig.me
```

Expected in this design: the request should not use VM-1 as the egress
path. It will commonly fail because VM-2 has no public IP and the UDR no
longer sends its traffic to VM-1. Do not interpret a failure as an NSG
deny; it is a routing/egress-path change.

### Test C --- Recreate the UDR

``` bash
az network route-table route create \
  --resource-group "$RG" \
  --route-table-name "$ROUTE_TABLE" \
  --name Default-Route-Via-Linux-Router \
  --address-prefix 0.0.0.0/0 \
  --next-hop-type VirtualAppliance \
  --next-hop-ip-address "$ROUTER_PRIVATE_IP"
```

Retry curl from VM-2. Expected: outbound access succeeds through VM-1
again.

------------------------------------------------------------------------

## 12. Network Watcher --- Next hop

Network Watcher Next hop shows the route Azure selects from a VM to a
destination IP.

Get the Network Watcher in the VM region:

``` bash
az network watcher list --output table
```

If required, enable Network Watcher:

``` bash
az network watcher configure \
  --resource-group "$RG" \
  --locations "$LOCATION" \
  --enabled true
```

Check the next hop from VM-2 toward an internet IP:

``` bash
az network watcher show-next-hop \
  --resource-group "$RG" \
  --vm "$PRIVATE_VM" \
  --source-ip "$PRIVATE_VM_IP" \
  --dest-ip 8.8.8.8
```

Expected while the UDR is installed:

-   Next hop type: `VirtualAppliance`
-   Next hop IP address: VM-1's private IP

This is the most direct way to demonstrate that the UDR is steering
VM-2's traffic to VM-1.

------------------------------------------------------------------------

## 13. Network Watcher --- Effective routes

Show effective routes on VM-2's NIC:

``` bash
az network nic show-effective-route-table \
  --resource-group "$RG" \
  --name "$PRIVATE_NIC_NAME" \
  --output table
```

If the NIC name variable is not available in your current shell,
retrieve it:

``` bash
PRIVATE_NIC_ID=$(az vm show -g "$RG" -n "$PRIVATE_VM" \
  --query "networkProfile.networkInterfaces[0].id" -o tsv)
PRIVATE_NIC_NAME=$(basename "$PRIVATE_NIC_ID")
```

Look for:

``` text
Address Prefix    Next Hop Type       Next Hop IP
0.0.0.0/0         VirtualAppliance    10.60.1.x
```

The actual next-hop IP should equal VM-1's private IP.

------------------------------------------------------------------------

## 14. Network Watcher --- Connection troubleshoot

Test from VM-2 to a public HTTPS endpoint:

``` bash
az network watcher test-connectivity \
  --resource-group "$RG" \
  --source-resource "$PRIVATE_VM" \
  --dest-address example.com \
  --dest-port 443 \
  --protocol Tcp
```

You can also test VM-2 to VM-1's private address for a suitable
listening port. Interpret the result together with the route and host
firewall configuration.

------------------------------------------------------------------------

## 15. Troubleshooting

  -----------------------------------------------------------------------
  Symptom                             Checks
  ----------------------------------- -----------------------------------
  Next hop is not VM-1                UDR association, route prefix,
                                      next-hop IP, effective routes

  VM-2 cannot access internet         VM-1 Linux forwarding, NAT rules,
                                      NIC forwarding, NSGs, DNS, outbound
                                      connectivity from VM-1

  VM-1 receives packets but does not  `net.ipv4.ip_forward`, FORWARD
  forward                             chain, host firewall

  NAT counters remain zero            UDR not applied, wrong source
                                      subnet, wrong interface, traffic
                                      not generated

  VM-2 cannot SSH through VM-1        VM-2 NSG source, SSH service,
                                      correct private IP, jump-host
                                      command

  Azure reports invalid next hop      Ensure VM-1 private IP is in the
                                      same VNet and is a valid virtual
                                      appliance next hop

  Internet access works without UDR   Check current Azure outbound access
                                      configuration and effective routes;
                                      do not assume all VMs have
                                      identical default egress

  Return traffic fails                Check NAT, conntrack, Linux
                                      forwarding, and stateful host
                                      firewall rules
  -----------------------------------------------------------------------

Useful VM-1 checks:

``` bash
sysctl net.ipv4.ip_forward
ip route
sudo iptables -t nat -L -n -v
sudo iptables -L FORWARD -n -v
```

Useful Azure checks:

``` bash
az network nic show -g "$RG" -n "$ROUTER_NIC_NAME" \
  --query "{name:name,ipForwarding:enableIPForwarding}" -o json

az network route-table route list -g "$RG" \
  --route-table-name "$ROUTE_TABLE" -o table
```

------------------------------------------------------------------------

## 16. Production considerations

This lab uses a single VM as a router. That is useful for understanding
the mechanism, but it is not a resilient production architecture by
itself.

Before using a self-managed router/NVA in production, design for:

-   Multiple NVA instances across Availability Zones or fault domains
    where supported.
-   A supported load-balancing and failover design.
-   Health probes and route convergence/failover behavior.
-   Stateful session symmetry and connection tracking.
-   OS hardening, patching, secure boot, and access controls.
-   Capacity, throughput, packet-per-second, and connection limits.
-   Monitoring, logs, alerts, and operational ownership.
-   Backup and tested recovery procedures.
-   DNS, private endpoints, platform dependencies, and management-plane
    access.
-   Explicit outbound policy and egress address management.

A single VM router is a single point of failure. For a production
service, use a vendor-supported HA NVA design or a managed network
service appropriate to the security and availability requirements.

------------------------------------------------------------------------

## 17. Cleanup

Delete the resource group after the demonstration to remove both VMs,
disks, public IP, VNet, NSGs, and route table:

``` bash
az group delete \
  --name "$RG" \
  --yes \
  --no-wait
```

Verify:

``` bash
az group exists --name "$RG"
```

Expected after deletion completes:

``` text
false
```

------------------------------------------------------------------------

## 18. Teaching and interview summary

**What is a UDR?**\
A User Defined Route is a custom route in an Azure route table that
controls the next hop for a destination prefix.

**Why is VM-1 configured for IP forwarding?**\
Because VM-1 forwards packets whose destination is not VM-1 itself.
Azure NIC forwarding and Linux IP forwarding must both be enabled.

**Why do we use NAT?**\
VM-2 has no public IP. VM-1 translates VM-2's private source IP to its
own egress source so internet replies can return through VM-1.

**What does `0.0.0.0/0` mean?**\
It is the default route for IPv4 destinations that do not match a
more-specific route.

**What does next-hop type `Virtual appliance` mean?**\
Send matching packets to the private IP of a network appliance, such as
VM-1 in this lab.

**Does UDR perform packet filtering?**\
No. UDR chooses the route. NSGs and host firewall rules filter traffic.

**What is the difference between Azure NIC forwarding and Linux
forwarding?**\
Azure NIC forwarding permits the platform to pass packets through the
NIC. Linux forwarding allows the operating system to route packets
between interfaces/paths.

**Final takeaway:** With only two VMs, VM-1 can act as a simple Linux
router/NAT appliance and VM-2 can send its default-route traffic through
VM-1 using a UDR. This demonstrates traffic steering without deploying
Azure Firewall.
