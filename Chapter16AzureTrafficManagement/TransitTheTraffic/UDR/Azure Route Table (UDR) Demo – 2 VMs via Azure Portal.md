# Azure Route Table (UDR) Demo – 2 VMs via Azure Portal

Nov 8, 2026 · @ashutosh

## Goal and lab design

This lab proves a User Defined Route (UDR) overrides Azure's default system route: after one route table is attached, VM1's internet traffic leaves through VM2 and shows VM2's public IP.

**How it works**

- **VM1 (vm-client)** sits in a private subnet with no public IP, so by default it cannot reach the internet.
- **VM2 (vm-router)** has a public IP, IP forwarding on, and Linux NAT. It acts as a small network virtual appliance (NVA).
- A **route table** on VM1's subnet sends `0.0.0.0/0` to VM2's private IP (next hop type: Virtual appliance).
- **Proof:** VM1 runs `curl ifconfig.me` and gets VM2's public IP back. Effective routes, Network Watcher Next hop, traceroute and tcpdump on VM2 all confirm the path.

**Traffic path after the UDR**

```
VM1 10.10.1.4 --(UDR 0.0.0.0/0)--> VM2 10.10.2.4 --(NAT to VM2 public IP)--> Internet
```

Intra-VNet traffic (for example SSH from VM2 to VM1) is not affected. The system route `10.10.0.0/16 -> VnetLocal` is more specific than `0.0.0.0/0`, and Azure always picks the longest prefix match.

## Prerequisites and IP plan

You need an Azure subscription with Contributor rights on a resource group, and about 45 minutes. Two B-series VMs cost a few cents an hour; delete everything at the end.

| Resource | Name | Address / setting |
| --- | --- | --- |
| Resource group | rg-udr-demo | Region: any one region (e.g. Central India) |
| Virtual network | vnet-udr-demo | 10.10.0.0/16 |
| Subnet A (client) | snet-client | 10.10.1.0/24, private subnet ON |
| Subnet B (router) | snet-router | 10.10.2.0/24 |
| VM1 | vm-client | 10.10.1.4, no public IP |
| VM2 | vm-router | 10.10.2.4, public IP pip-vm-router, IP forwarding ON |
| Route table | rt-client-via-router | Associated to snet-client |
| Route | default-via-router | 0.0.0.0/0 -> Virtual appliance 10.10.2.4 |

Image for both VMs: **Ubuntu Server 24.04 LTS**, size **Standard\_B1s** or **B2s**, username `azureuser`. Azure gives the first usable IP (.4) to the first NIC in each subnet, so the IPs above match if each subnet holds one VM.

## Step 1 – Resource group and VNet with two subnets

1. Portal search bar -> **Resource groups** -> **+ Create**. Name `rg-udr-demo`, pick your region -> **Review + create** -> **Create**.
2. Search **Virtual networks** -> **+ Create**.
3. **Basics** tab: Resource group `rg-udr-demo`, Name `vnet-udr-demo`, same region.
4. **IP addresses** tab: set the address space to `10.10.0.0/16`. Delete the `default` subnet.
5. **+ Add a subnet**: Name `snet-client`, starting address `10.10.1.0`, size `/24`. Leave **Enable private subnet (no default outbound access)** ticked -> **Add**.
6. **+ Add a subnet** again: Name `snet-router`, `10.10.2.0/24` -> **Add**.
7. **Review + create** -> **Create**.

Why the private subnet matters: the portal now creates new subnets as private by default, so VMs there get no automatic internet access ([Microsoft Learn](https://docs.azure.cn/en-us/virtual-network/ip-services/default-outbound-access)). That gives a clean "before": VM1 cannot reach the internet until the UDR sends it through VM2.

## Step 2 – Create VM2 (vm-router) and enable IP forwarding

1. Search **Virtual machines** -> **+ Create** -> **Azure virtual machine**.
2. **Basics**: Resource group `rg-udr-demo`, name `vm-router`, same region, Availability options **No infrastructure redundancy required**, Image **Ubuntu Server 24.04 LTS**, Size **Standard\_B1s**.
3. Administrator account: username `azureuser`, SSH public key or password (password is simpler for a demo).
4. Inbound port rules: **Allow selected ports** -> **SSH (22)**.
5. **Networking** tab: VNet `vnet-udr-demo`, Subnet `snet-router`, Public IP **(new) vm-router-ip**, NIC network security group **Basic**, public inbound ports **SSH**.
6. **Review + create** -> **Create**. Note the public IP when deployment finishes.

**Enable IP forwarding on the NIC (Azure side)**

1. Open `vm-router` -> **Networking** -> **Network settings** -> click the network interface name.
2. On the NIC: **Settings -> IP configurations**.
3. Tick **Enable IP forwarding** -> **Apply**.

Without this, Azure drops any packet that reaches VM2 but is addressed to another destination. This is the most common reason a UDR to an NVA "does nothing".

## Step 3 – Create VM1 (vm-client) with no public IP

1. **Virtual machines** -> **+ Create** -> **Azure virtual machine**.
2. **Basics**: name `vm-client`, same resource group, region, image and size as VM2, username `azureuser`. Public inbound ports: **None**.
3. **Networking** tab: VNet `vnet-udr-demo`, Subnet `snet-client`, Public IP **None**, NIC NSG **Basic**, public inbound ports **None**.
4. **Review + create** -> **Create**.

**Reach VM1 through VM2 (jump host)**

From your laptop, SSH to VM1 through VM2's public IP:

```bash
ssh -J azureuser@<VM2-public-IP> azureuser@10.10.1.4
```

This works before and after the UDR because VM2 -> VM1 is intra-VNet traffic. Keep two terminals open for the tests: one on VM1, one on VM2 (`ssh azureuser@<VM2-public-IP>`).

## Step 4 – Turn VM2 into a router (Linux forwarding + NAT)

Azure-side forwarding (Step 2) lets packets reach VM2. The OS must also forward them and NAT them to its public IP. Run on **VM2**:

```bash
# 1. Enable kernel IP forwarding now and after reboot
sudo sysctl -w net.ipv4.ip_forward=1
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-ipforward.conf

# 2. NAT traffic from the client subnet out of eth0
sudo iptables -t nat -A POSTROUTING -s 10.10.1.0/24 -o eth0 -j MASQUERADE

# 3. Check
sysctl net.ipv4.ip_forward
sudo iptables -t nat -L POSTROUTING -v -n
```

Expected: `net.ipv4.ip_forward = 1` and one MASQUERADE rule for `10.10.1.0/24` with 0 packets so far. Optional: `sudo apt install -y iptables-persistent` keeps the rule after reboot.

## Step 5 – Baseline: record the "before" state

Capture these three results before touching routing. Screenshot each one for the demo.

**A. Effective routes on VM1 (portal)**

`vm-client` -> **Networking** -> NIC name -> **Help -> Effective routes**. You see only Default routes, including:

| Source | Address prefix | Next hop type |
| --- | --- | --- |
| Default | 10.10.0.0/16 | Virtual network |
| Default | 0.0.0.0/0 | Internet |

**B. Network Watcher Next hop**

Search **Network Watcher** -> **Next hop**. Choose VM `vm-client`, source IP `10.10.1.4`, destination IP `8.8.8.8` -> **Next hop**. Result: **Internet**, no route table ID.

**C. Internet test from VM1**

```bash
curl -m 10 ifconfig.me
```

Expected: timeout. VM1 has no public IP and sits in a private subnet, so it has no way out. (If your subnet is not private, you instead get an Azure default IP that is NOT VM2's public IP. Either result works as the baseline.)

## Step 6 – Create the route table, add the UDR, associate it

**Create the route table**

1. Search **Route tables** -> **+ Create**.
2. Resource group `rg-udr-demo`, same region, name `rt-client-via-router`.
3. **Propagate gateway routes: Yes** (the default; no gateway here, so it does not matter) -> **Review + create** -> **Create**.

**Add the route**

1. Open `rt-client-via-router` -> **Settings -> Routes** -> **+ Add**.
2. Route name `default-via-router`.
3. Destination type **IP Addresses**, destination `0.0.0.0/0`.
4. Next hop type **Virtual appliance**, next hop address `10.10.2.4` -> **Add**.

**Associate it with VM1's subnet**

1. In the route table: **Settings -> Subnets** -> **+ Associate**.
2. Virtual network `vnet-udr-demo`, subnet `snet-client` -> **OK**.

Do not associate it with `snet-router`. If VM2's own subnet sent `0.0.0.0/0` to VM2, its NATed traffic would loop back to itself. Wait about one minute for the route to apply.

## Step 7 – Prove the UDR works (five pieces of evidence)

Repeat the baseline checks, then add two packet-level proofs. Every result should now point at VM2.

**Proof 1 – Effective routes (portal)**

`vm-client` NIC -> **Effective routes**:

| Source | State | Address prefix | Next hop type | Next hop IP |
| --- | --- | --- | --- | --- |
| Default | Active | 10.10.0.0/16 | Virtual network | – |
| Default | **Invalid** | 0.0.0.0/0 | Internet | – |
| **User** | **Active** | 0.0.0.0/0 | Virtual appliance | 10.10.2.4 |

The User route has replaced the Default internet route. That one table is the core proof.

**Proof 2 – Network Watcher Next hop**

Same inputs as the baseline (`vm-client`, `10.10.1.4` -> `8.8.8.8`). Result: **VirtualAppliance**, next hop IP `10.10.2.4`, and the route table ID ends in `rt-client-via-router`.

**Proof 3 – VM1 now egresses with VM2's public IP**

On VM1:

```bash
curl -m 10 ifconfig.me ; echo
```

Expected: VM2's public IP. Before the UDR this timed out.

**Proof 4 – Traceroute shows VM2 as the first hop**

On VM1 (internet works now, so the install succeeds):

```bash
sudo apt update && sudo apt install -y traceroute
sudo traceroute -n -T -p 443 8.8.8.8
```

Expected: hop 1 is `10.10.2.4`. Hops inside Azure after that may show `* * *`, which is normal.

**Proof 5 – VM2 sees VM1's packets**

On VM2 start a capture, then run the curl again on VM1:

```bash
sudo tcpdump -ni eth0 host 10.10.1.4 and port 80   # Ctrl+C to stop
sudo iptables -t nat -L POSTROUTING -v -n   # packet counter has increased
```

Expected: lines like `10.10.1.4.xxxxx > <ifconfig.me IP>.80`. Packets from VM1 to the internet physically pass through VM2.

## Step 8 – Negative tests: change the route, watch traffic change

These show the route table, not luck, controls the path.

| Test | What you change | Result on VM1 (`curl -m 10 ifconfig.me`) | Why |
| --- | --- | --- | --- |
| A. Break the appliance | On VM2: `sudo sysctl -w net.ipv4.ip_forward=0` | Timeout | The UDR still sends traffic to VM2, but VM2 no longer forwards it. |
| B. Blackhole | Edit route `default-via-router`: next hop type **None** | Timeout; Next hop tool shows **None**; tcpdump on VM2 sees nothing | Azure drops the packets before they leave VM1's NIC. |
| C. Remove the UDR | Route table -> **Subnets** -> dissociate `snet-client` | Timeout again (back to baseline) | The Default `0.0.0.0/0 -> Internet` route is active again, and the private subnet has no outbound access. |
| D. Restore | Next hop back to **Virtual appliance 10.10.2.4**, re-associate, `ip_forward=1` | VM2's public IP again | Proof 1–5 all pass again. |

Run A, then set `ip_forward=1` back before B. Each route change takes about a minute to apply.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Effective routes show the User route, but curl still times out | IP forwarding off on VM2's NIC, or `ip_forward=0` in the OS | Recheck Step 2 (NIC) and Step 4 (`sysctl`) |
| tcpdump on VM2 sees VM1's packets, but no reply comes back | MASQUERADE rule missing or wrong interface | `sudo iptables -t nat -L -v -n`; interface must be `eth0` |
| User route not listed in Effective routes | Route table not associated with `snet-client`, or VM1 is stopped | Check **Subnets** on the route table; VM must be running to show effective routes |
| Cannot SSH to VM1 | Using VM1's IP from your laptop directly | Use `ssh -J azureuser@<VM2-IP> azureuser@10.10.1.4` |
| VM2 lost internet after the change | Route table also associated with `snet-router` | Associate it with `snet-client` only |
| Next hop IP is not 10.10.2.4 | VM2 got a different private IP | Check VM2 -> Networking and update the route |

## Cleanup

Delete everything in one action: **Resource groups** -> `rg-udr-demo` -> **Delete resource group** -> type the name -> **Delete**. This removes both VMs, disks, public IP, NSGs, VNet and the route table.
