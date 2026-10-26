# Azure Container Apps — Hands-on Demo

A small, zero-dependency Node.js app with a **live web UI** that makes Azure Container Apps (ACA) features visible: replicas appearing and disappearing, traffic split between versions, private service-to-service calls, and run-to-completion jobs. It also explains **what Container Apps can do that an App Service Web App cannot.**

> 👉 **Prefer clicking in the Azure Portal?** Follow [`PORTAL-STEPS.md`](PORTAL-STEPS.md). It covers the same demo with ACR, done through the UI step by step. This README covers the CLI path.

Total time: ~30 minutes. Cost: a few rupees if you run `cleanup.sh` at the end (ACA has a monthly free grant, and the app scales to zero when idle).

---

## 1. What is Azure Container Apps?

Azure Container Apps is a **serverless platform for running containers**. Under the hood it runs on Kubernetes, with **KEDA** (event-driven autoscaling), **Envoy** (ingress and traffic splitting) and optional **Dapr** — but you never see or manage the cluster. You give it a container image and a few rules; it handles scaling, networking, TLS, revisions and logs.

Think of it as the middle ground:

| | You manage | Good for |
|---|---|---|
| **App Service (Web App)** | Code or one container on an always-on plan | Classic websites and APIs |
| **Container Apps** | Containers + scaling rules, no cluster | Microservices, APIs, background workers, jobs, event processing |
| **AKS (Kubernetes)** | The whole cluster | Full Kubernetes control, custom operators |

### How it works

```
                       Internet
                          │  HTTPS (auto TLS)
          ┌───────────────▼────────────────────────────────────┐
          │  Container Apps ENVIRONMENT  (shared VNet + logs)  │
          │                                                    │
          │   ┌──────────────────────┐      http://backend     │
          │   │ frontend (external)  │ ───────────────────┐    │
          │   │  rev v1  80% ▣ ▣ ▣   │                    ▼    │
          │   │  rev v2  20% ▣       │      ┌────────────────┐ │
          │   └──────────────────────┘      │backend(internal)│ │
          │       ▲ KEDA scale rule         │  ▣ (0..3)       │ │
          │       │ 0..10 replicas          └────────────────┘ │
          │                                                    │
          │   ┌──────────────────────┐                         │
          │   │ batch-job (Job)      │ runs → exits → stops    │
          │   └──────────────────────┘                         │
          └────────────────────────────────────────────────────┘
```

Key building blocks:

- **Environment** — a secure boundary. All apps in it share a virtual network and a Log Analytics workspace, and can call each other by name.
- **Container App** — one deployable service (one or more containers + sidecars).
- **Revision** — an immutable snapshot of an app's configuration. Every change to the container template creates a new revision. You can run several at once and split traffic between them.
- **Replica** — a running instance of a revision. KEDA adds and removes replicas based on **scale rules** (HTTP concurrency, CPU, queue length, Kafka lag, cron, ...), including down to **zero**.
- **Ingress** — `external` (public HTTPS endpoint), `internal` (only reachable inside the environment), or none (background worker).
- **Job** — a container that runs to completion (manually, on a cron schedule, or when events arrive) and then stops.

---

## 2. What Container Apps can do that a Web App cannot

| Capability | Container Apps | App Service Web App | Demo step |
|---|---|---|---|
| **Scale to zero** — no replicas, no compute bill when idle | ✅ | ❌ min 1 instance always billed via the plan | Step 6 |
| **Event-driven scaling** on queue depth, Kafka lag, Service Bus, cron, custom metrics (any KEDA scaler) | ✅ | ❌ CPU / memory / schedule only | Step 6 |
| **Revisions** with weighted traffic across any number of versions (e.g. 70/20/10), plus revision labels for direct testing | ✅ | ⚠️ Deployment slots: fixed count, swap-based | Step 7 |
| **Internal-only microservices** with built-in DNS service discovery (`http://backend`) | ✅ | ⚠️ Needs VNet integration + private endpoints per app | Step 8 |
| **Jobs** — run-to-completion containers (manual / scheduled / event-driven), billed only while running | ✅ | ⚠️ WebJobs, tied to an always-on app | Step 9 |
| **Non-HTTP workloads** — TCP ingress, or no ingress at all (queue workers) | ✅ | ❌ HTTP(S) only | Step 9 |
| **Sidecars & init containers** in the same app | ✅ | ⚠️ Limited | — |
| **Built-in Dapr** (pub/sub, state store, service invocation, secrets) | ✅ | ❌ | — |
| **Serverless GPUs** for AI inference | ✅ | ❌ | — |

Where the **Web App is better**: deploying plain code without building a container, built-in authentication UI options, mature deployment slots for classic sites, Windows/.NET Framework apps, and predictable always-on hosting for a single website.

> **Rule of thumb:** one website or API that is always busy → Web App. Several services, bursty or event-driven traffic, background processing, or you want to pay nothing when idle → Container Apps.

---

## 3. Project structure

```
aca-demo/
├── README.md            ← this file
├── deploy.sh            ← creates everything in Azure (one command)
├── cleanup.sh           ← deletes everything
├── app/                 ← the demo service (used for BOTH frontend and backend)
│   ├── server.js        ← zero-dependency Node HTTP server + APIs
│   ├── public/index.html← the live demo UI
│   ├── package.json
│   └── Dockerfile
└── job/                 ← a run-to-completion job
    ├── job.js
    └── Dockerfile
```

### App endpoints

| Endpoint | What it does | Feature it proves |
|---|---|---|
| `/` | Demo UI | — |
| `/api/info` | Returns app, **revision** and **replica** name (from env vars ACA injects) | Load balancing, revisions |
| `/api/work?ms=8000` | Holds the request open for N ms | Drives the HTTP-concurrency scale rule |
| `/api/downstream` | Calls `BACKEND_URL` (`http://backend`) | Internal ingress + service discovery |
| `/healthz` | Health probe | Liveness / readiness probes |

The same image runs as both **frontend** and **backend**; environment variables (`APP_ROLE`, `APP_VERSION`, `APP_COLOR`, `BACKEND_URL`) change its behaviour. That itself shows a nice ACA pattern: one image, many configurations.

---

## 4. Prerequisites

- An Azure subscription
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) 2.60+ (or use **Azure Cloud Shell** in the portal — everything is preinstalled)
- Node.js 18+ only if you want to run locally (Step 5). **Docker is not required** — images are built in the cloud with `az acr build`.

```bash
az login
az account set --subscription "<your-subscription-name-or-id>"
```

---

## 5. Run locally (optional, 1 minute)

```bash
cd aca-demo/app
node server.js
# open http://localhost:8080
```

Locally you'll see one replica named after your machine and a note saying you're not in Azure. Card 4 shows an error because there's no backend — that's expected. Everything becomes interesting once deployed.

---

## 6. Deploy to Azure + demo autoscaling & scale to zero

### 6.1 Deploy

```bash
cd aca-demo
chmod +x deploy.sh cleanup.sh
./deploy.sh
```

This takes ~5–8 minutes and creates: a resource group, a container registry, a Container Apps environment, **frontend** (external), **backend** (internal), and **batch-job** (manual job). At the end it prints the demo URL and an `export` line — **run that export line**, the later steps use those variables.

The important part of the frontend command:

```bash
az containerapp create -n frontend ... \
  --ingress external --target-port 8080 \
  --min-replicas 0 --max-replicas 10 \
  --scale-rule-name http-rule --scale-rule-type http --scale-rule-http-concurrency 5
```

Meaning: *"Run zero replicas when nobody is calling. Add one replica for every 5 concurrent requests, up to 10."*

### 6.2 Show autoscaling

1. Open the demo URL. Card **1** shows the revision (`frontend--v1`) and replica name.
2. In a second terminal, watch replicas live:
   ```bash
   watch -n 3 "az containerapp replica list -g $RG -n frontend --query '[].name' -o tsv"
   ```
3. In card **2**, keep *Requests = 60* and *Hold = 8000 ms*, click **Send burst**.
4. Watch the bars fill with **several different replica names**, and the terminal list grow (60 concurrent ÷ 5 per replica ≈ up to 10 replicas).

> Browsers limit parallel connections per host (~6 on HTTP/1.1; HTTP/2 allows many more, and ACA ingress supports HTTP/2). If you see few replicas, run the burst from a terminal instead:
> ```bash
> URL=https://<your-fqdn>
> seq 100 | xargs -P 100 -I{} curl -s "$URL/api/work?ms=10000" -o /dev/null
> ```

### 6.3 Show scale to zero

Stop sending traffic and wait ~5 minutes (the default cool-down is 300 s). The replica list becomes **empty** — nothing is running and nothing is billed for compute. Reload the page: the first request takes a second or two (**cold start**) while a replica starts, then it's fast again.

> 💡 **Web App can't do this.** A Web App always has at least one instance running on its App Service Plan, billed 24/7.

To avoid cold starts in production, set `--min-replicas 1`.

---

## 7. Demo revisions & traffic splitting (canary / blue-green)

Switch the app to **multiple revision mode** so old and new versions can run side by side:

```bash
az containerapp revision set-mode -g $RG -n frontend --mode multiple
```

Deploy **v2** — same image, new configuration (a template change creates a new revision):

```bash
az containerapp update -g $RG -n frontend \
  --revision-suffix v2 \
  --set-env-vars APP_VERSION=v2 APP_COLOR="#059669" APP_MESSAGE="Hello from v2 — the canary!"
```

Send 80% of traffic to v1 and 20% to v2:

```bash
az containerapp ingress traffic set -g $RG -n frontend \
  --revision-weight frontend--v1=80 frontend--v2=20
```

In the UI, card **3** → click **Sample 50 requests**. You'll see roughly **80% v1 / 20% v2**. Reload the page a few times: the header badge flips between blue `v1` and green `v2`.

Promote v2 fully, then retire v1:

```bash
az containerapp ingress traffic set -g $RG -n frontend --revision-weight frontend--v2=100
az containerapp revision deactivate -g $RG -n frontend --revision frontend--v1
az containerapp revision list -g $RG -n frontend -o table
```

**Bonus — test a revision before giving it any traffic** using labels:

```bash
az containerapp revision label add -g $RG -n frontend --label staging --revision frontend--v2
# gives a dedicated URL: https://frontend---staging.<env-domain>
```

Rollback is instant: shift the weight back. Old revisions stay available until you deactivate them.

> 💡 **Web App comparison:** deployment slots give you a fixed number of copies of the whole app that you *swap*. Revisions are lightweight, immutable, unlimited, and traffic can be split across many of them at once.

---

## 8. Demo private microservices (internal ingress + service discovery)

The **backend** was created with `--ingress internal`. Try to reach it from the internet:

```bash
az containerapp show -g $RG -n backend --query properties.configuration.ingress.fqdn -o tsv
# backend.internal.<env-domain>  → not resolvable/reachable from your laptop
```

Now in the UI, card **4** → **Call backend**. The frontend calls `http://backend` — just the app's name — and gets a response showing the backend's own revision and replica (`role: backend`). The environment provides DNS-based service discovery and keeps the traffic inside its network.

Because the backend also has `--min-replicas 0`, the first call may take a moment while it wakes up — each microservice scales independently.

> 💡 **Web App comparison:** every Web App is public by default. Making one private needs VNet integration plus a private endpoint and private DNS zone per app.

---

## 9. Demo Jobs (run-to-completion work)

A Job starts a container, lets it finish, and stops — you pay only for the seconds it runs.

```bash
# Start an execution
az containerapp job start -g $RG -n batch-job

# See executions and their status (Running → Succeeded)
az containerapp job execution list -g $RG -n batch-job -o table
```

View the job's output in **Azure Portal → batch-job → Execution history → Console logs**, or query Log Analytics:

```kusto
ContainerAppConsoleLogs_CL
| where ContainerJobName_s == "batch-job"
| project TimeGenerated, Log_s
| order by TimeGenerated asc
```

You'll see `processed batch 1/5 … done — exiting with code 0`.

Turn it into a **scheduled** job (every 5 minutes):

```bash
az containerapp job update -g $RG -n batch-job --cron-expression "*/5 * * * *"
```

> If `update` complains about the trigger type, create a separate scheduled job instead:
> ```bash
> az containerapp job create -g $RG -n nightly-job --environment $ENV_NAME \
>   --trigger-type Schedule --cron-expression "*/5 * * * *" \
>   --image $ACR.azurecr.io/aca-job:v1 --registry-server $ACR.azurecr.io \
>   --registry-username $(az acr credential show -n $ACR --query username -o tsv) \
>   --registry-password $(az acr credential show -n $ACR --query "passwords[0].value" -o tsv) \
>   --replica-timeout 300 --replica-retry-limit 1 --replica-completion-count 1 --parallelism 1
> ```

Jobs can also be **event-driven** (`--trigger-type Event` with a KEDA scale rule, e.g. one job execution per Azure Storage Queue / Service Bus message) — a pattern a Web App can't do natively.

---

## 10. Explore more (optional)

```bash
# Live logs from the frontend
az containerapp logs show -g $RG -n frontend --follow

# Open a shell inside a running replica
az containerapp exec -g $RG -n frontend --command sh

# Change scaling without redeploying code
az containerapp update -g $RG -n frontend --min-replicas 1 --max-replicas 20
```

In the portal, look at **frontend → Revisions and replicas**, **Metrics → Replica count**, and **Log stream** while you send bursts.

Ideas to extend the demo:

- **Dapr**: `az containerapp dapr enable -n backend --dapr-app-id backend --dapr-app-port 8080`, then call it via `http://localhost:3500/v1.0/invoke/backend/method/api/info` from the frontend.
- **Queue-driven scaling**: add a `--scale-rule-type azure-queue` rule and watch replicas follow queue length.
- **Managed identity** instead of registry passwords: `--registry-identity system`.

---

## 11. Clean up

```bash
./cleanup.sh
```

This deletes the whole resource group (registry, environment, apps, job, logs).

---

## Demo script cheat-sheet (for presenting)

| # | Say | Do |
|---|---|---|
| 1 | "ACA is serverless containers — Kubernetes power without the cluster." | Show the diagram in section 1 |
| 2 | "Each request tells us which revision and replica answered." | UI card 1 |
| 3 | "It scales on demand…" | Card 2 → Send burst, show replica list growing |
| 4 | "…and to zero when idle. A Web App can't." | Show empty replica list after 5 min, cold start |
| 5 | "Ship v2 to 20% of users, roll back in one command." | Section 7 commands + card 3 |
| 6 | "Private microservices, discovered by name." | Card 4 + unreachable backend FQDN |
| 7 | "Batch work that runs and stops." | `az containerapp job start` + execution list |
| 8 | "When to choose which." | Comparison table, section 2 |
