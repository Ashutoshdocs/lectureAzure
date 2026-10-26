# Container Apps + ACR Demo — Azure Portal (UI) Step-by-Step

This guide does the whole demo by **clicking in the Azure Portal**. The only commands are one or two to push the image into **Azure Container Registry (ACR)**, because the portal itself can't upload source code.

You'll build this:

```
 Your code ──build/push──▶  ACR  (acrdemo<you>.azurecr.io/aca-demo:v1)
                             │  image pull
                             ▼
        ┌──────── Container Apps Environment ────────┐
        │  frontend  (public URL, scales 0→10)       │
        │     │ http://backend                       │
        │     ▼                                      │
        │  backend   (internal only)                 │
        │  batch-job (Container Apps Job)            │
        └────────────────────────────────────────────┘
```

> Portal labels change occasionally. If a label differs slightly from this guide, look for the closest match on the same tab.

**Time:** ~40 minutes · **Region:** Central India (or any near you) · **Clean up:** Step 11

---

## Step 0 — Get the code ready

Unzip `aca-demo.zip`. You need the `app/` and `job/` folders. Each has a `Dockerfile`.

---

## Step 1 — Create a Resource Group

1. Portal → search **Resource groups** → **+ Create**.
2. **Resource group:** `rg-aca-demo` · **Region:** `Central India`.
3. **Review + create** → **Create**.

---

## Step 2 — Create the Azure Container Registry (ACR)

1. Portal → search **Container registries** → **+ Create**.
2. **Basics** tab:
   - Resource group: `rg-aca-demo`
   - Registry name: `acrdemo<yourname>` (globally unique, lowercase letters/numbers only)
   - Location: `Central India`
   - Pricing plan: **Basic**
3. **Review + create** → **Create**. Wait ~1 minute → **Go to resource**.
4. Left menu → **Settings → Access keys** → turn **Admin user** **ON**.
   Note the **Login server** (e.g. `acrdemoakash.azurecr.io`), **Username** and **password**.

> In production use a **managed identity** instead of the admin user. Admin user keeps the demo simple.

---

## Step 3 — Push the images into ACR

Choose **one** option.

### Option A — Azure Cloud Shell (no Docker needed) ✅ easiest

1. In the portal top bar click the **Cloud Shell** icon `>_` → choose **Bash**.
2. Click **Manage files → Upload** → upload `aca-demo.zip`.
3. Run:
   ```bash
   unzip aca-demo.zip && cd aca-demo
   ACR=acrdemo<yourname>                      # your registry name
   az acr build -r $ACR -t aca-demo:v1 ./app
   az acr build -r $ACR -t aca-job:v1  ./job
   ```
   ACR builds the images in the cloud using each `Dockerfile` (this feature is called **ACR Tasks**).

### Option B — Docker Desktop on your laptop

```bash
cd aca-demo
docker login acrdemo<yourname>.azurecr.io      # username + password from Step 2
docker build -t acrdemo<yourname>.azurecr.io/aca-demo:v1 ./app
docker build -t acrdemo<yourname>.azurecr.io/aca-job:v1  ./job
docker push acrdemo<yourname>.azurecr.io/aca-demo:v1
docker push acrdemo<yourname>.azurecr.io/aca-job:v1
```
On an Apple Silicon Mac add `--platform linux/amd64` to each `docker build`.

### Verify in the portal

ACR → **Services → Repositories**. You should see **aca-demo** and **aca-job**, each with tag **v1**. 🎉 Your images are in your private registry.

---

## Step 4 — Create the Container App (frontend) from the ACR image

1. Portal → search **Container Apps** → **+ Create** → **Container App**.

2. **Basics** tab
   - Resource group: `rg-aca-demo`
   - Container app name: `frontend`
   - Deployment source: **Container image**
   - Region: `Central India`
   - Container Apps environment: **Create new** → name `aca-demo-env` → leave defaults (Consumption only, Log Analytics new) → **Create**

3. **Container** tab
   - **Uncheck** "Use quickstart image"
   - Name: `frontend`
   - Image source: **Azure Container Registry**
   - Registry: `acrdemo<yourname>.azurecr.io`
   - Authentication: **Secret-based** (uses the admin user) — or Managed identity if offered and you prefer it
   - Image: `aca-demo` · Image tag: `v1`
   - CPU and Memory: **0.25 CPU cores, 0.5 Gi memory**
   - **Environment variables** → add:

     | Name | Source | Value |
     |---|---|---|
     | `APP_ROLE` | Manual entry | `frontend` |
     | `APP_VERSION` | Manual entry | `v1` |
     | `APP_COLOR` | Manual entry | `#2563eb` |
     | `APP_IMAGE` | Manual entry | `acrdemo<yourname>.azurecr.io/aca-demo:v1` |

4. **Ingress** tab
   - Ingress: **Enabled**
   - Ingress traffic: **Accepting traffic from anywhere**
   - Ingress type: **HTTP**
   - Target port: **8080**

5. **Review + create** → **Create**. Wait 2–4 minutes → **Go to resource**.

6. On the **Overview** page click the **Application Url**.
   ✅ You see the demo UI. Card 1 shows the **revision**, **replica** and the **ACR image** it was pulled from.

---

## Step 5 — Look around (what the portal gives you for free)

On the `frontend` app:

| Blade | What to show |
|---|---|
| **Overview** | Public HTTPS URL with automatic TLS certificate — no setup |
| **Application → Revisions and replicas** | Revision `frontend--xxxxxxx` and its running replica(s) |
| **Application → Containers** | The image coming from your ACR |
| **Monitoring → Log stream** | Live `console.log` output (`listening on :8080`) |
| **Monitoring → Console** | Open a shell inside the running container |
| **Monitoring → Metrics** | Choose **Replica Count** — keep this tab open for Step 6 |

---

## Step 6 — Autoscale and scale to zero (Web App can't scale to zero)

1. `frontend` → **Application → Scale** (in some portal versions: **Revisions and replicas → Create new revision → Scale** tab).
2. Set **Min replicas = 0**, **Max replicas = 10**.
3. **+ Add** a scale rule:
   - Rule name: `http-rule`
   - Type: **HTTP scaling**
   - Concurrent requests: **5**
4. **Save / Create**. This creates a **new revision** — scaling config is part of the revision.

**Demo it:**
1. Open the app URL. In card **2** set *Requests = 60*, *Hold = 8000*, click **Send burst**.
2. Bars show **multiple replica names** answering.
3. Switch to **Revisions and replicas** (refresh) or **Metrics → Replica Count**: replicas rise toward 10.
4. Stop and wait ~5 minutes. Replica count goes to **0**. Nothing running = no compute cost.
5. Open the URL again: first load takes 1–2 s (**cold start**), then normal.

> If the browser doesn't create enough parallel load, run this in Cloud Shell:
> `seq 100 | xargs -P 100 -I{} curl -s "https://<app-url>/api/work?ms=10000" -o /dev/null`

---

## Step 7 — Revisions and traffic splitting (canary release)

1. `frontend` → **Application → Revisions and replicas** → **Choose revision mode** → **Multiple: several revisions active simultaneously** → **Apply**.
2. Click **+ Create new revision**.
   - **Name / suffix:** `v2`
   - Under **Container image**, click the `frontend` container → **Environment variables** → change:
     - `APP_VERSION` = `v2`
     - `APP_COLOR` = `#059669`
     - Add `APP_MESSAGE` = `Hello from v2 — the canary!`
   - **Save** → **Create**.
3. Back on **Revisions and replicas** (Active revisions tab) set **Traffic**:
   - Old revision: **80**
   - `frontend--v2`: **20**
   - **Save**.

**Demo it:** open the UI → card **3** → **Sample 50 requests** → roughly **80% v1 / 20% v2**. Refresh the page a few times: the badge flips between blue **v1** and green **v2**.

**Promote:** set v2 = **100**, old = **0**, then select the old revision → **Deactivate**.
**Rollback:** just move the traffic back. Old revisions are immutable and kept until you delete them.

> Web App comparison: deployment slots are a fixed number of full app copies that you *swap*; revisions are lightweight, unlimited and can share traffic in any ratio.

---

## Step 8 — Private backend microservice (internal ingress)

### 8.1 Create the backend

1. **Container Apps → + Create → Container App**.
2. **Basics:** name `backend`, same resource group, environment **aca-demo-env** (select existing).
3. **Container:** same ACR image `aca-demo:v1`, env vars:
   `APP_ROLE=backend`, `APP_COLOR=#7c3aed`, `APP_MESSAGE=I am the internal backend`,
   `APP_IMAGE=acrdemo<yourname>.azurecr.io/aca-demo:v1`
4. **Ingress:** Enabled → **Limited to Container Apps Environment** → HTTP → Target port **8080**.
5. **Review + create** → **Create**.

On its Overview page notice the URL contains **`.internal.`** — open it in your browser: **it doesn't load**. It's not on the internet.

### 8.2 Point the frontend at it

1. `frontend` → **Revisions and replicas → + Create new revision** → suffix `v3`.
2. Edit the container → add env var `BACKEND_URL` = `http://backend` → **Create**.
3. Move **100%** traffic to `frontend--v3`.

**Demo it:** UI card **4** → **Call backend**. The response shows `backendRole: "backend"` and the backend's own replica name. The frontend found it **by name only** — built-in service discovery inside the environment.

---

## Step 9 — Container Apps Job (run-to-completion)

1. Portal → search **Container App Jobs** → **+ Create**.
2. **Basics**
   - Name: `batch-job` · Resource group `rg-aca-demo` · Environment `aca-demo-env`
   - Trigger type: **Manual**
   - Replica timeout: `300` · Retry limit: `1` · Parallelism: `1` · Replica completion count: `1`
3. **Container**: image source **Azure Container Registry** → `acrdemo<yourname>.azurecr.io` → image **aca-job**, tag **v1** → env var `STEPS=5`.
4. **Review + create** → **Create** → **Go to resource**.
5. Click **▶ Run now**.
6. Left menu → **Execution history** → status goes **Running → Succeeded**. Click **Console logs** to see:
   ```
   processed batch 1/5 … processed batch 5/5
   done — exiting with code 0
   ```

Extra: create another job with **Trigger type = Schedule** and cron `*/5 * * * *`, or **Event** (e.g. one run per message in an Azure Storage Queue). A Web App can't do run-and-stop jobs billed only while running.

---

## Step 10 — Ship a new image version through ACR

This is the real-world loop: **change code → new image tag in ACR → new revision**.

1. Edit `app/server.js` (e.g. change the default `"Hello from Azure Container Apps"` text).
2. Cloud Shell:
   ```bash
   az acr build -r $ACR -t aca-demo:v2 ./app
   ```
3. ACR → **Repositories → aca-demo** now shows tags **v1** and **v2**.
4. `frontend` → **Revisions and replicas → + Create new revision** → edit container → **Image tag: v2**, update `APP_IMAGE` to `...aca-demo:v2` → **Create**.
5. Split traffic or send 100% to it. Card 1 now shows the **v2** image.

> To automate this, `frontend` → **Settings → Continuous deployment** connects a GitHub repo. It builds the image into ACR and creates a new revision on every push.

---

## Step 11 — Clean up

Portal → **Resource groups → rg-aca-demo → Delete resource group** → type the name → **Delete**.
This removes ACR, the environment, both apps, the job and the logs.

---

## Presenter cheat-sheet

| # | Point | Where in portal |
|---|---|---|
| 1 | Images live privately in **ACR**; Container Apps pulls them | ACR → Repositories; app → Containers |
| 2 | Public HTTPS URL + TLS out of the box | App → Overview |
| 3 | Autoscale on HTTP load, **down to zero** | App → Scale; Metrics → Replica Count |
| 4 | Revisions + **80/20 canary**, instant rollback | Revisions and replicas |
| 5 | **Internal-only** backend, called by name | Backend Overview (`.internal.` URL), card 4 |
| 6 | **Jobs** that run and stop | Container App Jobs → Run now → Execution history |
| 7 | New image tag in ACR → new revision | ACR tags v1/v2 → Create new revision |

For the CLI version of the same demo, see `README.md`.
