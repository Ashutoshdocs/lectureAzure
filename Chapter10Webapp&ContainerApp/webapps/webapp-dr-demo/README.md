# Web App Primary + DR Demo (Azure DevOps, UI setup)

Two pipelines, one folder in Azure DevOps:

- **01-Primary-Deploy:** creates the primary web app (Central India) if it doesn't exist, deploys the code from the repo, and checks the site is up. It runs automatically on every push to `main` that changes `app/`.
- **02-DR-Deploy:** run it manually when you want DR. Every run creates a **brand-new** web app in the DR region you pick and deploys the same code there.

The primary site shows a **green "Primary is live"** page and the DR site a **red "DR is live"** page, with the web app name, region, build number and commit.

## Repo layout
```
app/
  server.js              the web app (Node.js, no dependencies)
  package.json
pipelines/
  primary-deploy.yml     pipeline 1: Primary
  dr-deploy.yml          pipeline 2: DR
README.md
```
Each pipeline file is self-contained: Build (zip `app/`) → Provision (create the web app) → Deploy (push the code and check the site).

## What you need
- An Azure subscription where you are **Owner**, or **Contributor + User Access Administrator**, so the service connection can be created.
- An Azure DevOps organization: https://dev.azure.com (sign in with the same account).

---

## Step 1: Create the project
1. Go to https://dev.azure.com → your organization → **+ New project**.
2. Name `WebApp-DR-Demo`, visibility **Private** → **Create**.

The project comes with an empty Git repo of the same name.

## Step 2: Put the code in the repo
**Option A: upload in the browser**
1. **Repos → Files** → **Initialize** (with a README) if the repo is empty.
2. Click **⋯** next to the repo name → **New → Folder**. Folder name `app`. It asks for a first file: name it `server.js`, paste the contents of `app/server.js` → **Commit**.
3. In the `app` folder: **⋯ → New → File** → `package.json` → paste → **Commit**.
4. Back at the root: **⋯ → New → Folder** `pipelines` → first file `primary-deploy.yml` → paste → **Commit**.
5. In `pipelines`: **⋯ → New → File** → `dr-deploy.yml` → paste → **Commit**.
6. Open `README.md` → **Edit** → paste this README → **Commit**.

**Option B: git push from your laptop**
```bash
git clone <repo clone URL from Repos → Files → Clone>
# copy app/, pipelines/, README.md into the cloned folder
git add -A && git commit -m "Primary + DR demo" && git push
```

## Step 3: Set a unique app name
Web app names are global across Azure, so pick something unique, e.g. `drdemo-ak1103` (lowercase letters, digits, hyphens, short).

In **Repos → Files**, edit **both** pipeline files and change this line to your name, then **Commit** each:
```yaml
appBaseName: 'drdemo-CHANGEME'
```
- `pipelines/primary-deploy.yml`
- `pipelines/dr-deploy.yml`

## Step 4: Create the service connection (Azure DevOps → Azure)
1. **Project settings** (bottom left) → **Service connections** → **New service connection**.
2. **Azure Resource Manager** → **Next**.
3. Identity type: **App registration (automatic)** (workload identity federation, no secrets).
4. Scope level **Subscription** → pick your subscription → leave **Resource group empty**.
5. Service connection name: **`sc-azure-webapp-demo`**. It must match the name in the pipeline files exactly.
6. Tick **Grant access permission to all pipelines** → **Save**.

## Step 5: Create pipeline 1 (Primary)
1. **Pipelines → New pipeline**.
2. **Azure Repos Git** → select **WebApp-DR-Demo**.
3. **Existing Azure Pipelines YAML file** → Branch `main`, Path **`/pipelines/primary-deploy.yml`** → **Continue**.
4. Click the **▾** next to **Run** → **Save**.
5. **⋯** (top right) → **Rename/move** → Name `01-Primary-Deploy`, Folder **`\WebApp-DR`** → **Save**.

## Step 6: Create pipeline 2 (DR)
Repeat Step 5 with:
- Path **`/pipelines/dr-deploy.yml`**
- Name `02-DR-Deploy`, Folder **`\WebApp-DR`**

**Pipelines → All** now shows the folder **WebApp-DR** with both pipelines inside.

---

## Step 7: Run the demo

### Primary
1. Open **01-Primary-Deploy** → **Run pipeline** → **Run**.
2. You'll see 3 stages: **Build → Provision → Deploy**. The first run takes about 4–6 min.
3. Open the **Deploy** stage → **Verify site is up**. The last line prints the URL:
   `https://<appBaseName>-primary.azurewebsites.net` → open it and you'll see the **green page**.
4. **Show auto-deploy:** in Repos, edit something in `app/server.js` (e.g. the heading text) → Commit.
   - The primary pipeline starts by itself, reuses the existing web app and deploys the change.
   - Refresh the site: you'll see the new text and the new build number.

### DR
1. Open **02-DR-Deploy** → **Run pipeline**. Choose a **DR region** (default South India), type a **Reason** → **Run**.
2. The Provision stage creates a **new** web app: `<appBaseName>-dr-<runId>`.
3. **Deploy → Verify site is up** prints its URL → open it and you'll see the **red DR page** with the DR region.
4. Run DR again and you get another new web app (`-dr-<nextRunId>`).

### See it in Azure
Azure portal → **Resource groups**:
- `rg-<appBaseName>-primary` holds the primary web app and its plan.
- `rg-<appBaseName>-dr` holds every DR web app created, with its own plan.

---

## First-run messages

| Message | Fix |
|---|---|
| **This pipeline needs permission to access a resource** | Click **View → Permit** (once per pipeline) |
| **No hosted parallelism has been purchased or granted** | New orgs need a free grant: request it at https://aka.ms/azpipelines-parallelism-request (about 1 business day) |
| Service connection creation fails with a permission error | Your account can't create app registrations. Ask an admin, or use **App registration or managed identity (manual)** with an existing service principal |
| **Website with given name already exists** | Change `appBaseName` (in both files) to something more unique |
| Region quota / capacity error in DR | Run DR again and pick another region |

## Cost and cleanup
Each web app has its own **B1** plan (about $13/month, billed hourly), and every DR run adds one. After the demo, go to the Azure portal → **Resource groups** → delete `rg-<appBaseName>-primary` and `rg-<appBaseName>-dr`.

To remove the project too: Azure DevOps → **Project settings → Overview → Delete**.
