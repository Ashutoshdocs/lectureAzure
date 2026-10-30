# NSG Zero Trust Demo — nginx + live UI

A hands-on lab that **proves** how Azure Network Security Groups (NSGs) implement a Zero Trust network.
Four nginx containers play the role of four VMs in four subnets of one VNet. A dashboard fires real
requests between them and shows — per request — which layer allowed, denied or dropped the traffic.

![Dashboard](docs/dashboard.png)

---

## 1. Quick start

```bash
docker compose up -d          # start the 4 "VMs"
open http://localhost:8080    # click "Run all scenarios"
./test.sh                     # same proof from the CLI (14 checks)
docker compose down -v        # clean up
```

Requirements: Docker with Compose v2. Nothing else — no build step, only the `nginx:1.27-alpine` image.

---

## 2. What Zero Trust means here

| Principle | How the demo enforces it |
|---|---|
| **Never trust the network** | All subnets share one flat VNet (`10.10.0.0/16`) — routing would let anything reach anything. Only NSG rules stop it. |
| **Default deny** | Every NSG ends in `Deny-All-Inbound` *and* adds `4000 Deny-VNet-Inbound`, which overrides Azure's built-in `65000 AllowVnetInBound`. |
| **Microsegmentation** | Each tier accepts traffic only from the one subnet and port it needs (web → app:80, app → db). |
| **Verify explicitly** | Even on an allowed path, the app requires a workload identity token (`X-Workload-Token`). |
| **Least privilege** | The web identity may call `/api/*` only; `/admin` returns 403. |
| **Assume breach** | A compromised VM (`vm-legacy`) holding **stolen valid tokens** still can't reach app or DB. |

---

## 3. Architecture

```
                 Internet
                    │  :8080 (only published port)
                    ▼
 ┌──────────── vnet-zt 10.10.0.0/16 ─────────────────────────────────┐
 │                                                                   │
 │  snet-web 10.10.1.0/24        snet-app 10.10.2.0/24               │
 │  ┌────────────┐  :80 + token  ┌────────────┐                      │
 │  │  vm-web    │──────────────▶│  vm-app    │ :8080 mgmt (bastion) │
 │  │ 10.10.1.10 │               │ 10.10.2.10 │                      │
 │  └────────────┘               └─────┬──────┘                      │
 │        ╳ direct                     │ :80 + app token             │
 │        ╳                            ▼                             │
 │        ╳                      ┌────────────┐                      │
 │        ╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳╳▶│   vm-db    │ snet-db 10.10.3.0/24 │
 │                               │ 10.10.3.10 │                      │
 │  snet-legacy 10.10.9.0/24     └────────────┘                      │
 │  ┌────────────┐   ╳╳╳ to app ╳╳╳   ╳╳╳ to db ╳╳╳                   │
 │  │ vm-legacy ☠│  (stolen tokens — still dropped)                  │
 │  │ 10.10.9.10 │                                                   │
 │  └────────────┘                                                   │
 └───────────────────────────────────────────────────────────────────┘
```

### How each Azure concept maps to the lab

| Azure | Demo |
|---|---|
| VNet / subnets | Docker network `zt-vnet` with fixed IPs per "subnet" |
| NSG rule (source CIDR → port) | nginx `geo $remote_addr` blocks on each listener |
| NSG **Deny** (silent drop) | `return 444` — nginx closes the TCP connection with no response, exactly like a dropped packet (caller sees nothing / 502) |
| Public IP only on web | Only `zt-web` publishes a port (`8080:80`) |
| Managed Identity / mTLS | `X-Workload-Token` header checked by `map` |
| NSG flow logs | JSON access logs per tier, shared volume, live in the UI |

---

## 4. NSG rules

**nsg-web** (snet-web)
| Prio | Name | Source | Port | Action |
|---|---|---|---|---|
| 100 | Allow-HTTP-Internet | Internet | 80 | Allow |
| 4000 | Deny-VNet-Inbound | VirtualNetwork | * | Deny |
| 4096 | Deny-All-Inbound | * | * | Deny |

**nsg-app** (snet-app)
| Prio | Name | Source | Port | Action |
|---|---|---|---|---|
| 100 | Allow-Web-To-App-API | 10.10.1.0/24 | 80 | Allow |
| 200 | Allow-Bastion-Mgmt | 10.10.250.0/24 | 8080 | Allow |
| 4000 | Deny-VNet-Inbound | VirtualNetwork | * | Deny |
| 4096 | Deny-All-Inbound | * | * | Deny |

**nsg-db** (snet-db)
| Prio | Name | Source | Port | Action |
|---|---|---|---|---|
| 100 | Allow-App-To-DB | 10.10.2.0/24 | 80 (stands in for 1433/5432) | Allow |
| 4000 | Deny-VNet-Inbound | VirtualNetwork | * | Deny |
| 4096 | Deny-All-Inbound | * | * | Deny |

> **Why rule 4000 matters:** Azure adds `65000 AllowVnetInBound` to every NSG, so by default *every subnet trusts every other subnet*. That is the opposite of Zero Trust. A custom deny at a lower number than 65000 removes that implicit trust.

---

## 5. The 9 scenarios (and what proves each one)

| # | Scenario | Expected | Enforced by | Proof you'll see |
|---|---|---|---|---|
| 1 | Internet → web :80 | **ALLOW** | nsg-web #100 | 200 |
| 2 | web → app `/api/hello` with token | **ALLOW** | all layers pass | 200, app reports `src 10.10.1.10` |
| 3 | web → app → db | **ALLOW** | each hop re-verified | 200 + records, DB reports `src 10.10.2.10` |
| 4 | web → app, **no token** | **DENY** | identity | 401 — network said yes, identity said no |
| 5 | web → app `/admin` | **DENY** | least privilege | 403 — valid identity, wrong scope |
| 6 | web → app **:8080** mgmt | **DROP** | nsg-app (port) | no response → 502, `444 DROP:nsg` in app.log |
| 7 | web → db direct | **DROP** | nsg-db | no response → 502, `444 DROP:nsg` in db.log |
| 8 | vm-legacy → app, **stolen web token** | **DROP** | nsg-app | DROP although the token is valid |
| 9 | vm-legacy → db, **stolen app token** | **DROP** | nsg-db | DROP although the token is valid |

Scenarios 8 and 9 are the key result: **credentials alone are not enough — the network path itself must be explicitly allowed.**
Scenario 4 shows the reverse: **an allowed network path alone is not enough either.**

### Three outcomes, three colours

- 🟢 **ALLOW** — NSG allowed the flow *and* identity + authorization passed.
- 🟠 **DENY** (401/403) — the packet reached the server (NSG allowed it), but the app refused it.
- 🔴 **DROP** — the target NSG discarded the connection; the app never saw a request. The caller gets no answer at all.

---

## 6. Proving it yourself (without the UI)

`./test.sh` runs 14 checks: the 9 scenarios through the dashboard, then **raw requests from inside each container**, so you can see the rules are not a UI trick:

```bash
# breached VM tries the DB with a stolen app token -> no response
docker exec zt-attacker wget -qO- -T 3 --header 'X-Workload-Token: wt-app-2b8e1d' http://10.10.3.10/data/
# wget: error getting response    <- dropped

# the app tier, same token -> data
docker exec zt-app wget -qO- --header 'X-Workload-Token: wt-app-2b8e1d' http://10.10.3.10/data/

# what the DB saw
docker exec zt-db cat /var/log/nsg/db.log
```

Flow log line format:
```json
{"time":"…","tier":"db","src":"10.10.9.10","dst":"10.10.3.10:80","req":"GET /data/","status":"444","decision":"DROP:nsg"}
```

### Experiments to try
1. **Break Zero Trust:** in `nginx/db/nginx.conf` change `default 0;` in `geo $nsg_db` to `default 1;` (= Azure's default `AllowVnetInBound`), then `docker compose restart db`. Scenario 9 now returns data — the breached VM with a stolen token reads your database. Scenario 7 turns from DROP into DENY: only the identity layer is left protecting you.
2. **Remove identity:** in `nginx/app/nginx.conf` change `"1:0" 1;` to `"1:0" 0;`. Scenario 4 now passes as ALLOW.
3. **Add a rule:** allow the legacy subnet into app (`10.10.9.0/24 1;` in `geo $nsg_app_80`) and watch scenario 8 flip.

---

## 7. Deploy the real NSGs to Azure (optional)

`azure/deploy-nsgs.sh` creates the same VNet, four subnets and four NSGs with `az` CLI (NSGs and VNets have no cost):

```bash
az login
RG=rg-nsg-zero-trust-demo LOC=centralindia ./azure/deploy-nsgs.sh
# verify with Network Watcher once you add VMs:
az network watcher test-ip-flow -g rg-nsg-zero-trust-demo --vm <vm-db> --direction Inbound \
  --protocol TCP --local 10.10.3.4:1433 --remote 10.10.9.4:50000   # -> Deny
az group delete -n rg-nsg-zero-trust-demo --yes --no-wait           # clean up
```

---

## 8. Project layout

```
nsg-zero-trust-demo/
├── docker-compose.yml          # VNet + 4 "VMs" with fixed IPs
├── nginx/
│   ├── web/nginx.conf          # nsg-web, dashboard, probe endpoints
│   ├── web/html/index.html     # the UI (topology, scenarios, rules, live flow logs)
│   ├── app/nginx.conf          # nsg-app + identity + least privilege
│   ├── db/nginx.conf           # nsg-db
│   └── attacker/nginx.conf     # breached VM with stolen tokens
├── test.sh                     # CLI proof (14 checks)
├── azure/deploy-nsgs.sh        # same design in real Azure
└── docs/dashboard.png
```

## 9. Limits of the emulation (honest notes)

- Real NSGs filter at the hypervisor (L4) before traffic reaches the VM; here the filter lives in nginx on the target. The observable behaviour — a silent drop with no response — is the same, and source-IP based decisions are the same.
- Real NSGs are stateful and also have outbound rules; the demo models inbound rules only, which is where Zero Trust segmentation is usually enforced.
- Tokens are static strings to keep the demo readable. In production use Managed Identities, Entra ID tokens or mTLS, plus Azure Firewall / Private Endpoints for deeper control.
