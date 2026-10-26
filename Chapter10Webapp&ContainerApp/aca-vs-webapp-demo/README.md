# Azure Web App vs Azure Container Apps — Hands-on Demo

One container image, built once into **Azure Container Registry (ACR)**, deployed to both an **Azure Web App (App Service)** and an **Azure Container App**. Four short demos then prove, with live output, how the two platforms behave differently while running the exact same, fully functioning application.

**Resources created (nothing else):**

| # | Resource | Why it exists |
|---|----------|---------------|
| 1 | Resource group | Container for everything; delete it to clean up |
| 2 | Azure Container Registry (Basic) | Stores the `demoapp:v1` and `demoapp:v2` images |
| 3 | App Service Plan (Linux B1) | Mandatory host for a Web App (the VM you pay for) |
| 4 | Web App | Runs the image on App Service |
| 5 | Container Apps Environment | Mandatory host boundary for Container Apps |
| 6 | Container App | Runs the same image on Container Apps |

> The Container Apps Environment is created with `--logs-destination none`, so **no Log Analytics workspace** is added. ACR pull uses the registry admin credentials, so **no managed identity or role assignments** are needed.

---

## 1. Project structure

```
aca-vs-webapp-demo/
├── README.md
├── app/
│   ├── app.py               # Flask app that reports platform, instance, version, uptime
│   ├── requirements.txt
│   ├── Dockerfile           # APP_VERSION build-arg -> v1 / v2 images
│   └── .dockerignore
└── scripts/
    ├── 00-variables.sh      # names + random suffix (saved in .demo.env)
    ├── 01-setup-acr-build.sh
    ├── 02-deploy-webapp.sh
    ├── 03-deploy-containerapp.sh
    ├── 04-demo-identity.sh      # DEMO 1  same image, different platforms
    ├── 05-demo-autoscale.sh     # DEMO 2  load -> replicas vs fixed instances
    ├── 06-demo-scale-to-zero.sh # DEMO 3  idle cost + cold start
    ├── 07-demo-rollout.sh       # DEMO 4  revisions/traffic split vs in-place replace
    ├── load.py                  # dependency-free load generator
    └── 99-cleanup.sh
```

### The application

`app/app.py` is a small Flask app served by gunicorn on port **8000**:

| Endpoint | Purpose |
|----------|---------|
| `/` | Colored dashboard (blue = v1, green = v2) showing platform, instance, uptime, request count, platform env vars |
| `/api/info` | Same data as JSON — used by all demo scripts |
| `/health` | Health check |
| `/work?ms=500` | Sleeps 500 ms to simulate a slow request, so load creates concurrency |

It detects the platform from the env vars each platform injects: `CONTAINER_APP_*` on Container Apps, `WEBSITE_*` on App Service.

---

## 2. Prerequisites

- An Azure subscription with Contributor rights.
- **Azure Cloud Shell (Bash)** — recommended; has `az`, `curl`, `python3` ready. Or locally: Azure CLI 2.60+, bash, curl, python3.
- **No local Docker needed** — images are built inside ACR with `az acr build`.

```bash
az login                                  # skip in Cloud Shell
az account set --subscription "<your-subscription-id>"
```

Upload or clone this folder into Cloud Shell, then:

```bash
cd aca-vs-webapp-demo
chmod +x scripts/*.sh
# optional: change region (default centralindia)
export LOCATION=centralindia
```

---

## 3. Setup (≈10–15 minutes, run once before presenting)

```bash
./scripts/01-setup-acr-build.sh      # RG + ACR + builds demoapp:v1 and demoapp:v2
./scripts/02-deploy-webapp.sh        # App Service Plan B1 + Web App (v1 image)
./scripts/03-deploy-containerapp.sh  # ACA Environment + Container App (v1 image)
```

At the end, both URLs are printed and saved in `.demo.env`. Open both in two browser tabs side by side — same app, different header text.

Key configuration differences already visible in the scripts:

| Setting | Web App | Container App |
|---------|---------|---------------|
| Port | `WEBSITES_PORT=8000` app setting | `--target-port 8000` |
| Sizing | Plan SKU `B1` (1 vCPU, 1.75 GB VM) | `--cpu 0.25 --memory 0.5Gi` per replica |
| Scaling | Instance count of the plan (1) | `--min-replicas 0 --max-replicas 5` + HTTP rule (10 concurrent req/replica) |
| Idle | `--always-on true` | Scales to 0 |
| Versioning | Single running image | `--revision-suffix v1` → named revision |

---

## 4. Demo script (≈25 minutes live)

Every demo script sources `00-variables.sh`, so just run them in order.

### DEMO 1 — Same image, two platforms (2 min)

```bash
./scripts/04-demo-identity.sh
```

**What to show:**
- Both resources point at the **same** `acrdemoxxxxx.azurecr.io/demoapp:v1` image.
- Web App JSON has `WEBSITE_SITE_NAME`, `WEBSITE_SKU=Basic`, `WEBSITE_INSTANCE_ID` populated; `CONTAINER_APP_*` are `null`.
- Container App JSON has `CONTAINER_APP_NAME`, `CONTAINER_APP_REVISION=aca-demo-xxxxx--v1`, `CONTAINER_APP_REPLICA_NAME`; `WEBSITE_*` are `null`.
- Web App compute = a **plan** with N VM instances. Container App compute = **replicas** of a **revision**, governed by scale rules.

**Message:** the app is identical and works on both; the difference is the hosting model around it.

### DEMO 2 — Same load, different scaling (5 min)

```bash
./scripts/05-demo-autoscale.sh
# tune with: DURATION=120 CONCURRENCY=80 ./scripts/05-demo-autoscale.sh
```

Each target gets 50 concurrent users for 90 seconds hitting `/work?ms=500`.

**Expected result:**

| | Web App | Container App |
|--|--|--|
| Distinct instances that served traffic | **1** | **4–5** (grows during the test) |
| Replicas/instances after test | 1 | up to 5 |
| Who decided to scale | Nobody — needs manual scale-out or a separate autoscale setting | Built-in HTTP scale rule (KEDA) |

The `[watch]` lines show ACA replica count climbing every 15 s. The Web App's single instance absorbs everything, so its p95 latency is typically higher.

**Message:** Container Apps scales on *events/requests* natively; Web App scales *the plan*, which you configure and pay for separately.

### DEMO 3 — Idle: scale to zero vs Always On (6–7 min)

```bash
./scripts/06-demo-scale-to-zero.sh
```

Wait while no traffic flows (~5 min cooldown). The loop prints replicas every 30 s until ACA hits **0**, while the Web App stays at **1**. Then one request is sent to each:

- **Container App:** response takes a few seconds (cold start), `instance_uptime_seconds` ≈ 1–5 s → a brand-new replica.
- **Web App:** fast response, uptime = minutes/hours → the same instance never stopped.

**Message:** idle ACA costs nothing for compute (consumption plan); Web App bills the plan 24×7 but is always warm. Set `--min-replicas 1` on ACA if cold starts matter.

> Tip: run DEMO 3 right after DEMO 2 and talk through slides/comparison table during the 5-minute wait.

### DEMO 4 — Releasing v2 (7 min)

```bash
./scripts/07-demo-rollout.sh
```

**Container App part:**
1. Switches to multiple-revision mode.
2. Deploys v2 as a **new revision** — v1 keeps running.
3. Splits traffic **80% v1 / 20% v2** on the same URL → the 50-request sample shows ~40 × v1, ~10 × v2. Refresh the browser tab: header flips between blue and green.
4. **Instant rollback** to 100% v1 — no redeploy, no restart.
5. Promotes v2 to 100%.

**Web App part:**
1. A background probe hits the Web App every second.
2. Image is switched to v2 and the app restarts.
3. The probe timeline shows `v1 … (possibly DOWN/ERR) … v2` — an all-or-nothing in-place swap.

**Message:** canary/blue-green is built into Container Apps revisions. On a single Web App you get one version at a time; safe swaps need **deployment slots** (Standard tier and above).

---

## 5. Summary — what the demo proved

| Capability | Azure Web App (App Service) | Azure Container Apps |
|-----------|-----------------------------|----------------------|
| Runs the same container image from ACR | ✅ | ✅ |
| Hosting unit | App Service Plan (dedicated VMs) | Environment (serverless, consumption) |
| Billing | Per plan instance, 24×7 | Per vCPU-second / GiB-second of running replicas (+ free monthly grant) |
| Scale to zero | ❌ (Always On / plan always billed) | ✅ (DEMO 3) |
| Autoscale trigger | CPU/memory/schedule via autoscale settings on the plan | HTTP concurrency, queues, events, CPU, cron (KEDA) — built in (DEMO 2) |
| Max scale | Plan tier limit (e.g. B1 = 3 instances) | Up to hundreds of replicas per app |
| Versions live at once | 1 per slot | Many revisions (DEMO 4) |
| Traffic splitting | Slots + "testing in production" % (Standard+) | Revision weights, any plan (DEMO 4) |
| Rollback | Swap slots back / redeploy | Move traffic weight — seconds |
| Cold start | None (Always On) | Yes when min-replicas = 0 |
| Platform conveniences | Kudu/SSH console, built-in auth, custom domains, slots, WebJobs, code-based (non-container) deploy | Dapr, sidecars, jobs, internal service-to-service networking, KEDA |
| Best fit | Classic web apps/APIs, steady traffic, teams wanting PaaS conveniences | Microservices, event-driven or bursty workloads, cost-sensitive idle apps |

---

## 6. Cost note

For a one-hour demo the cost is a few rupees/cents:
- App Service Plan B1 is billed hourly while it exists.
- ACR Basic is billed daily.
- Container Apps consumption is effectively free at demo volume (monthly free grant).

**Always clean up:**

```bash
./scripts/99-cleanup.sh
```

---

## 7. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `az webapp create` errors on `--container-image-name` | Upgrade CLI: `az upgrade` (older CLIs use `--deployment-container-image-name`) |
| Web App shows "Application Error" | Wait 1–2 min for first pull; check `WEBSITES_PORT=8000`; `az webapp log tail -n <name> -g <rg>` (enable with `az webapp log config --docker-container-logging filesystem`) |
| ACA scaling not visible | Increase load: `CONCURRENCY=100 ./scripts/05-demo-autoscale.sh` |
| ACA never reaches 0 replicas | Make sure no browser tab is auto-refreshing it; cooldown is ~300 s |
| `az containerapp` not found | `az extension add --name containerapp --upgrade` |
| Provider not registered error | `az provider register -n Microsoft.App --wait` |
| ACR name taken | Delete `.demo.env` to generate a new suffix |

## 8. Run the app locally (optional)

```bash
cd app
docker build -t demoapp:v1 .
docker run -p 8000:8000 demoapp:v1
# open http://localhost:8000  -> "Running on: Local / Docker"
```
