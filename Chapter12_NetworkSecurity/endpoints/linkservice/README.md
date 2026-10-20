# Azure Private Link Service — End-to-End Production-Style Demo

> **Goal:** Prove that a consumer VNet can access a provider-owned HTTP service through Azure Private Link Service (PLS) and a Private Endpoint, without VNet peering and without exposing the provider VM or service through a public IP.
>
> **Important:** This is a production-style reference lab for learning and validation. It is not automatically production-ready. Before production use, apply your organization's approved security, availability, monitoring, change-management, and cost controls.

## 1. What you will build

A service provider publishes a private HTTP service behind an **Azure Standard Internal Load Balancer**. Azure Private Link Service exposes that load-balancer frontend. A consumer creates a **Private Endpoint** in a separate VNet and connects to the provider service using a private IP.

```text
 SERVICE PROVIDER SUBSCRIPTION / VNET                  SERVICE CONSUMER VNET
 ┌───────────────────────────────────────┐            ┌──────────────────────────────┐
 │ VNet: vnet-pls-provider               │            │ VNet: vnet-pls-consumer       │
 │ Address: 10.10.0.0/16                 │            │ Address: 10.20.0.0/16        │
 │                                       │            │                              │
 │ Subnet: snet-provider 10.10.1.0/24    │            │ Subnet: snet-consumer         │
 │   ┌──────────────────────────────┐    │            │   ┌──────────────────────┐   │
 │   │ VM: vm-pls-web               │    │            │   │ VM: vm-pls-client    │   │
 │   │ Nginx HTTP :80               │    │            │   │ curl / browser       │   │
 │   │ No public IP                 │    │            │   └──────────┬───────────┘   │
 │   └──────────────┬───────────────┘    │            │              │               │
 │                  ▲                    │            │   Private Endpoint NIC       │
 │                  │ backend pool        │            │   e.g. 10.20.2.4             │
 │   ┌──────────────┴───────────────┐    │            │              │               │
 │   │ Standard Internal Load       │    │            │              ▼               │
 │   │ Balancer frontend :80        │◄───┼── Private Link connection ────────────────┤
 │   └──────────────▲───────────────┘    │            │                              │
 │                  │                    │            │                              │
 │   ┌──────────────┴───────────────┐    │            │                              │
 │   │ Azure Private Link Service   │    │            │                              │
 │   │ PLS NAT IP configuration     │    │            │                              │
 │   └───────────────────────────────┘    │            └──────────────────────────────┘
 └───────────────────────────────────────┘

             No VNet peering is configured between these VNets.
```

### Packet path

1. The consumer VM sends HTTP traffic to the Private Endpoint's private IP.
2. Azure Private Link carries the connection to the provider's Private Link Service.
3. PLS performs destination-side NAT using its configured provider-side NAT IP configuration.
4. The Standard Internal Load Balancer forwards the traffic to a healthy backend VM.
5. Nginx returns the HTTP response through the same private connectivity path.

**Important distinction:** The Private Endpoint is in the consumer VNet. The Private Link Service is in the provider VNet and is associated with a Standard Load Balancer frontend. They are different resources with different roles.

## 2. Naming plan and IP addressing

Use one region for all resources; this README uses **Central India**. Select another region only if it supports the required resources and your subscription has capacity.

| Resource | Name | Configuration |
|---|---|---|
| Resource group | `rg-pls-e2e` | Central India |
| Provider VNet | `vnet-pls-provider` | `10.10.0.0/16` |
| Provider subnet | `snet-provider` | `10.10.1.0/24` |
| Provider PLS NAT subnet | `snet-pls-nat` | `10.10.2.0/24` |
| Provider VM | `vm-pls-web` | Ubuntu Server, no public IP |
| Internal Load Balancer | `ilb-pls-provider` | Standard, Internal |
| ILB frontend | `fe-pls-http` | Private IP in `snet-provider` |
| Backend pool | `be-pls-web` | NIC-based backend pool |
| Health probe | `probe-http-80` | HTTP `/` on port 80 |
| Load-balancing rule | `rule-http-80` | TCP 80 to backend TCP 80 |
| Private Link Service | `pls-orders-api` | Linked to ILB frontend |
| Consumer VNet | `vnet-pls-consumer` | `10.20.0.0/16` |
| Consumer subnet | `snet-consumer` | `10.20.1.0/24` |
| Private Endpoint subnet | `snet-private-endpoint` | `10.20.2.0/24` |
| Consumer VM | `vm-pls-client` | Test client, no public IP preferred |
| Private Endpoint | `pe-orders-api` | Connects to `pls-orders-api` |

The ranges are deliberately non-overlapping. Do not use these ranges if they overlap with existing networks in your environment.

### Sizing and production notes

- Microsoft recommends having **at least eight IP addresses available** in the subnet used for Private Link Service NAT IP configurations. The example `/24` NAT subnet provides room for this lab and growth, subject to other subnet allocations.
- Use a **Standard** Load Balancer, not Basic.
- Configure the load-balancer backend pool using **network interfaces (NICs)**; IP-address-based backend pool configuration is not supported for this PLS scenario.
- For a real production service, use multiple backend instances across availability zones where supported, application health checks, controlled deployment/rollback, monitoring, alerting, and documented ownership.
- Use Azure Bastion or an approved private administration path for the VMs. Do not add public IPs to the provider VM just to make the lab easier.
- This demo uses HTTP to keep the network path easy to inspect. For production, use TLS at the appropriate layer, validate certificates, and avoid sending sensitive data over unencrypted HTTP.

## 3. Prerequisites and permissions

- An active Azure subscription and permission to create networking resources, VMs, and role assignments as required by your organization's policy.
- A region with capacity for the selected VM size and networking resources.
- Rights to create a Standard Load Balancer, Private Link Service, Private Endpoint, VNets, subnets, NICs, and NSGs.
- If using Azure Bastion, deploy Bastion according to your organization's approved access design; Bastion has additional cost.
- For a cross-subscription or third-party consumer, confirm subscription/tenant access and approval requirements before creating the Private Endpoint.

Use a dedicated lab subscription or resource group. Review costs before deployment and delete lab resources when finished.

## 4. Build the provider network in Azure Portal

### 4.1 Create the resource group

1. Open [Azure Portal](https://portal.azure.com/).
2. Search **Resource groups** → **Create**.
3. Select the subscription.
4. Resource group: `rg-pls-e2e`.
5. Region: **Central India**.
6. Select **Review + create** → **Create**.

### 4.2 Create the provider VNet and subnets

1. Search **Virtual networks** → **Create**.
2. Basics:
   - Resource group: `rg-pls-e2e`
   - Name: `vnet-pls-provider`
   - Region: Central India
3. IP addresses:
   - Address space: `10.10.0.0/16`
   - Create `snet-provider`: `10.10.1.0/24`
   - Create `snet-pls-nat`: `10.10.2.0/24`
4. Review + create → Create.

Keep the PLS NAT subnet separate from the backend subnet. Do not place unrelated workloads in the NAT subnet.

### 4.3 Create the provider VM

1. Search **Virtual machines** → **Create** → **Azure virtual machine**.
2. Basics:
   - Resource group: `rg-pls-e2e`
   - Name: `vm-pls-web`
   - Region: Central India
   - Image: Ubuntu Server 24.04 LTS (or your approved supported Ubuntu image)
   - Choose a small supported lab size.
   - Configure administrator authentication per your security policy.
3. Networking:
   - VNet: `vnet-pls-provider`
   - Subnet: `snet-provider`
   - Public IP: **None**
   - NIC network security group: use an appropriate NSG.
4. Review + create → Create.

For administration, use Azure Bastion or another approved private access path. Do not expose SSH to the internet as a default production pattern.

### 4.4 Install a test HTTP service on the provider VM

1. Open `vm-pls-web` in the portal.
2. Select **Operations → Run command → RunShellScript** (the exact menu label can vary).
3. Run:

```bash
#!/bin/bash
set -eux
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
cat >/var/www/html/index.nginx-debian.html <<'EOF'
<!doctype html>
<html>
<head><title>Private Link Service Demo</title></head>
<body>
  <h1>Private Link Service: provider backend reached</h1>
  <p>Service: orders-api-demo</p>
  <p>Path: Consumer VNet -> Private Endpoint -> Private Link Service -> Internal Load Balancer -> Nginx VM</p>
</body>
</html>
EOF
systemctl enable --now nginx
curl -I http://127.0.0.1/
```

4. Select **Run**.
5. Confirm the command output shows Nginx started and the local `curl` returned an HTTP response such as `HTTP/1.1 200 OK`.

If package installation fails, verify the VM has approved outbound internet access through your organization's egress design. Do not add a public inbound endpoint to solve an outbound package-installation issue.

### 4.5 Configure the provider NSG

Attach an NSG to `snet-provider` or the provider VM NIC, following your organization's policy.

- Allow TCP 80 to the provider VM from the **PLS NAT subnet** (`10.10.2.0/24`) or the narrowest appropriate source range.
- Allow required platform traffic and administration only according to your organization's policy.
- Do not create an internet-wide inbound allow rule.
- Check the effective security rules on the VM NIC if traffic fails.

PLS traffic is source-NATed from the configured PLS NAT IP pool, so the provider backend may see a source address from that pool rather than the original consumer VM address.

## 5. Create the Standard Internal Load Balancer

### 5.1 Create the load balancer

1. Search **Load balancers** → **Create**.
2. Basics:
   - Resource group: `rg-pls-e2e`
   - Name: `ilb-pls-provider`
   - Region: Central India
   - SKU: **Standard**
   - Type: **Internal**
   - Tier: Regional
3. Frontend IP configuration:
   - Add frontend: `fe-pls-http`
   - VNet: `vnet-pls-provider`
   - Subnet: `snet-provider`
   - Choose a private IP assignment method. For repeatable lab evidence, a static IP such as `10.10.1.10` can be used if it is available and not reserved by another resource. Otherwise use dynamic assignment and record the actual IP.
4. Backend pools:
   - Add pool: `be-pls-web`
   - Backend pool configuration: **NIC**
5. Inbound rules:
   - Add a load-balancing rule: `rule-http-80`
   - Frontend IP: `fe-pls-http`
   - Backend pool: `be-pls-web`
   - Protocol: TCP
   - Frontend port: `80`
   - Backend port: `80`
   - Health probe: create `probe-http-80`, protocol HTTP, port 80, path `/`
   - Leave floating IP disabled for this HTTP demo.
6. Review + create → Create.

### 5.2 Add the VM NIC to the backend pool

Depending on the portal workflow, you may select the VM NIC during backend-pool creation or add it afterwards:

1. Open `ilb-pls-provider` → **Backend pools**.
2. Open `be-pls-web` → **Add**.
3. Select `vm-pls-web`'s network interface and its IP configuration.
4. Save.
5. Open **Health probes** and **Load balancing rules**. Confirm the probe and rule are configured correctly.
6. Check the load balancer's backend health/health-probe status where available. The backend should become healthy.

**Proof checkpoint A:** The provider VM has no public IP, Nginx responds locally, and the Standard Internal Load Balancer has a frontend IP, NIC-based backend pool, HTTP health probe, and TCP/80 rule.

## 6. Create Azure Private Link Service

1. Search **Private link services** in the Azure Portal.
2. Select **Create**.
3. Basics:
   - Resource group: `rg-pls-e2e`
   - Name: `pls-orders-api`
   - Region: Central India
4. **Outbound settings**:
   - Load balancer: `ilb-pls-provider`
   - Load balancer frontend IP configuration: `fe-pls-http`
   - Source NAT subnet: `vnet-pls-provider / snet-pls-nat`
   - Leave TCP Proxy V2 disabled unless the backend explicitly requires its proxy protocol header.
   - Leave the other private IP configuration settings at approved defaults for the lab.
5. **Access security**:
   - For a same-subscription lab, use the approved access mode.
   - For a controlled consumer onboarding workflow, configure auto-approval only for explicitly trusted subscription IDs; otherwise require manual approval. Do not allow broad auto-approval without a security review.
6. Review + create → Create.
7. Open `pls-orders-api` and record:
   - Provisioning state
   - Associated load balancer and frontend
   - NAT IP configuration
   - Alias, if displayed
   - Auto-approval configuration, if used

**What this proves:** The PLS is associated with the provider's Standard Load Balancer frontend. The PLS itself is not a VM and does not replace the load balancer or backend service.

## 7. Create the consumer network

### 7.1 Create the consumer VNet

1. Search **Virtual networks** → **Create**.
2. Resource group: `rg-pls-e2e`.
3. Name: `vnet-pls-consumer`.
4. Region: Central India.
5. Address space: `10.20.0.0/16`.
6. Create:
   - `snet-consumer`: `10.20.1.0/24`
   - `snet-private-endpoint`: `10.20.2.0/24`
7. Create the VNet.

Do **not** configure VNet peering between `vnet-pls-provider` and `vnet-pls-consumer`. Do not add a route that bypasses Private Link.

### 7.2 Create a consumer test VM

1. Search **Virtual machines** → **Create**.
2. Name: `vm-pls-client`; resource group `rg-pls-e2e`; region Central India.
3. Use Ubuntu Server 24.04 LTS or an approved Linux image.
4. VNet: `vnet-pls-consumer`; subnet: `snet-consumer`.
5. Public IP: **None preferred**. Use Azure Bastion or an approved private administration path.
6. Create the VM.

If you use Azure Bastion, ensure its required subnet and connectivity are configured according to current Azure Bastion requirements. Bastion is for administrator access; it is not the Private Link data path being demonstrated.

## 8. Create the consumer Private Endpoint

1. Search **Private endpoints** → **Create**.
2. Basics:
   - Resource group: `rg-pls-e2e`
   - Name: `pe-orders-api`
   - Region: Central India (the same region is recommended for this lab)
3. Resource:
   - Connection method: connect to an Azure resource in your directory
   - Resource type: `Microsoft.Network/privateLinkServices`
   - Resource: `pls-orders-api`
4. Virtual Network:
   - VNet: `vnet-pls-consumer`
   - Subnet: `snet-private-endpoint`
   - IP configuration: dynamic allocation is fine for the lab; record the actual assigned IP.
5. DNS:
   - This demo uses HTTP to an IP address, so Private DNS is not required for the first connectivity proof.
   - For a production-like named endpoint, configure a private DNS name/zone and name resolution appropriate for the service. A custom PLS does not automatically provide a universally valid service DNS name in the same way as every Azure PaaS private endpoint.
6. Review + create → Create.

### 8.1 Approve the connection if required

1. Open `pls-orders-api` → **Private endpoint connections**.
2. Find the request from `pe-orders-api`.
3. If manual approval is required, select the connection and **Approve** it, following your access policy.
4. Open `pe-orders-api` and confirm its connection state is **Approved** and provisioning state is **Succeeded**.
5. Open its network interface and record the assigned private IP. Example: `10.20.2.4`. Use your actual address in all tests.

For a consumer in another subscription or tenant, the provider may need to approve the request, depending on the configured access and auto-approval policy.

**Proof checkpoint B:** The Private Endpoint has a private IP in `10.20.2.0/24`, the PLS connection is approved, and the consumer VNet remains unpeered from the provider VNet.

## 9. End-to-end verification from the consumer VM

Run these tests from `vm-pls-client` after connecting through Bastion or your approved admin path.

### 9.1 Verify the Private Endpoint IP

In the portal:

1. Open `pe-orders-api`.
2. Open **Network interface**.
3. Record the private IP configuration and address.

Alternatively, on the consumer VM, inspect its local network configuration and compare it with the Private Endpoint NIC IP in the portal.

### 9.2 Send an HTTP request to the Private Endpoint

Replace `10.20.2.4` below with the actual Private Endpoint IP:

```bash
curl -v --connect-timeout 5 http://10.20.2.4/
```

Expected result: an HTTP response containing:

```text
Private Link Service: provider backend reached
Service: orders-api-demo
Path: Consumer VNet -> Private Endpoint -> Private Link Service -> Internal Load Balancer -> Nginx VM
```

The exact HTML may be displayed without formatting in `curl`. An HTTP `200 OK` and the expected response body are the main success indicators.

### 9.3 Run a repeatable check

```bash
for i in 1 2 3 4 5; do
  date -Is
  curl -sS -o /tmp/pls-response.html -w 'HTTP %{http_code} | remote=%{remote_ip} | time=%{time_total}s\n' \
    --connect-timeout 5 http://10.20.2.4/
  grep -E 'Private Link Service|orders-api-demo' /tmp/pls-response.html
  sleep 2
done
```

Replace the IP as needed. This confirms repeated requests succeed through the endpoint. It does not, by itself, prove high availability or production performance.

### 9.4 Check the provider backend

In the Azure Portal:

1. Open `ilb-pls-provider` → **Backend pools** and confirm the VM NIC is attached.
2. Check health-probe status where available.
3. Open `vm-pls-web` → **Networking** and confirm there is no public IP.
4. If needed, use VM **Run command** to inspect Nginx:
   ```bash
   systemctl is-active nginx
   curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1/
   ```
5. Inspect NSG effective security rules and any configured firewall/route controls if requests fail.

### 9.5 Prove there is no VNet peering

1. Open `vnet-pls-provider` → **Peerings**.
2. Open `vnet-pls-consumer` → **Peerings**.
3. Confirm no peering exists between these VNets.
4. Record screenshots for the lab evidence pack.

A missing peering entry plus a successful HTTP request to the Private Endpoint IP is strong evidence that the demonstrated path is using Private Link rather than VNet peering.

## 10. Evidence checklist — save screenshots for your README or presentation

Capture these screenshots after your own deployment. Do not use invented or sample screenshots as proof of a live deployment.

- [ ] Resource group overview showing the created resources.
- [ ] Provider VNet address space and subnets.
- [ ] Provider VM overview/networking showing **no public IP**.
- [ ] Nginx install/health check output showing HTTP `200`.
- [ ] Standard Internal Load Balancer overview showing Standard SKU and Internal type.
- [ ] Load-balancer frontend, NIC-based backend pool, HTTP probe, and TCP/80 rule.
- [ ] PLS overview showing successful provisioning and its associated load balancer/frontend.
- [ ] PLS NAT IP configuration and source NAT subnet.
- [ ] Consumer VNet and subnet configuration.
- [ ] Private Endpoint overview showing provisioning state **Succeeded** and connection state **Approved**.
- [ ] Private Endpoint NIC showing its assigned private IP.
- [ ] Successful `curl -v http://<private-endpoint-ip>/` output from `vm-pls-client`.
- [ ] Provider and consumer VNet **Peerings** pages showing no peering between them.
- [ ] Optional: provider-side web server access log or approved network diagnostics that corroborate requests arriving through the PLS NAT IP range.

Redact subscription IDs, tenant IDs, usernames, public IPs, tokens, and other sensitive details before sharing screenshots.

## 11. What counts as end-to-end proof?

| Claim | Evidence |
|---|---|
| The service is exposed through PLS | PLS resource references the Standard Load Balancer frontend |
| The consumer has private connectivity | Private Endpoint NIC has a private IP in the consumer VNet |
| The endpoint is authorized | Connection state is Approved |
| The provider service works | Consumer `curl` returns HTTP `200` and the expected Nginx body |
| The provider VM is not public-facing | VM networking shows no public IP; no public HTTP inbound rule |
| VNet peering is not used | No peering between provider and consumer VNets |
| Traffic is routed to a working backend | Healthy load-balancer probe/backend and successful HTTP response |
| Source NAT is configured | PLS NAT IP configuration exists; backend logs/diagnostics may show a source address from that NAT range |

No single screenshot proves every property. Collect the evidence set above and correlate resource settings with a live request.

## 12. Troubleshooting

### Private Endpoint is Pending

- Open `pls-orders-api` → **Private endpoint connections**.
- Approve the request if your access policy requires manual approval.
- Verify the consumer is connecting to the correct PLS and subscription.

### Private Endpoint is Approved but `curl` times out

Check in this order:

1. Use the actual Private Endpoint NIC IP, not the ILB frontend IP or provider VM IP.
2. Confirm `pe-orders-api` is provisioned successfully.
3. Confirm the PLS references `ilb-pls-provider` and `fe-pls-http`.
4. Confirm the load-balancer rule is TCP 80 → backend 80.
5. Confirm the VM NIC is in the backend pool and the health probe succeeds.
6. Confirm Nginx is listening on port 80.
7. Confirm the provider NSG/firewall permits TCP 80 from the PLS NAT subnet.
8. Check NSG rules, user-defined routes, Nginx logs, and Azure network diagnostics where available.

### HTTP 5xx or no backend response

- Check Nginx with `systemctl status nginx`.
- Run `curl -I http://127.0.0.1/` on the provider VM through Run command.
- Confirm the load-balancer health probe path and port match the service.
- Check the VM NIC backend-pool membership and NSG rules.

### Cannot select the VM NIC in the backend pool

- Confirm the Load Balancer SKU is **Standard**.
- Use a NIC-based backend pool for this scenario.
- Confirm the VM NIC and load balancer are in compatible region/network configuration.

### Name resolution does not work

The basic demo deliberately tests by private IP so DNS does not hide the network behavior. If you add a hostname, create and link the correct private DNS setup or configure internal DNS to resolve the service name to the Private Endpoint IP. Do not assume that a custom PLS automatically creates the DNS record for your custom service.

## 13. Production hardening checklist

Before adapting the pattern to a real service:

- [ ] Deploy redundant backend instances and test failure behavior.
- [ ] Select an appropriate zone/redundancy design for the region and workload.
- [ ] Define consumer onboarding, approval, revocation, and subscription allow-list procedures.
- [ ] Keep the provider VM private; administer it through Bastion or an approved private access solution.
- [ ] Restrict NSGs to required source ranges and ports; review effective rules and routes.
- [ ] Use TLS and certificate validation for sensitive or production traffic.
- [ ] Implement health monitoring, logs, metrics, alerts, and operational dashboards.
- [ ] Configure DNS deliberately for the consumer experience.
- [ ] Review Private Link Service quotas, NAT IP capacity, regional support, and current service limitations.
- [ ] Document ownership, incident response, change control, rollback, and disaster recovery.
- [ ] Run security testing and load/performance testing before production approval.

## 14. Cleanup

To avoid ongoing charges:

1. Confirm you have saved required screenshots and evidence.
2. In Azure Portal, open **Resource groups** → `rg-pls-e2e`.
3. Select **Delete resource group**.
4. Type `rg-pls-e2e` to confirm, then delete.

If resources were created in other resource groups or shared networking was reused, review and delete only the lab resources. Do not delete shared or production resources.

## 15. Official Microsoft references

- [Quickstart: Create a Private Link service by using the Azure portal](https://learn.microsoft.com/en-us/azure/private-link/create-private-link-service-portal)
- [What is Azure Private Link Service?](https://learn.microsoft.com/en-us/azure/private-link/private-link-service-overview)
- [What is a Private Endpoint?](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)
- [Create a Standard Internal Load Balancer using the Azure portal](https://learn.microsoft.com/en-us/azure/load-balancer/quickstart-load-balancer-standard-internal-portal)

---

## Lab completion record

Fill this in after deployment:

- Subscription/resource group: `rg-pls-e2e`
- Region: `Central India`
- Provider ILB frontend private IP: `________________`
- PLS NAT IP address(es): `________________`
- Consumer Private Endpoint IP: `________________`
- Private Endpoint connection state: `________________`
- Backend health: `________________`
- Consumer HTTP status: `________________`
- VNet peering between provider and consumer: `No`
- Evidence folder/location: `________________`

**Pass condition:** The consumer VM receives the expected HTTP response using the Private Endpoint's private IP, the endpoint connection is approved, the provider VM has no public IP, and the provider/consumer VNets are not peered.
