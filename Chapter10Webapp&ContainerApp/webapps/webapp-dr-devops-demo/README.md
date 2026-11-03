# Web App Primary + DR Demo with Azure DevOps

Two pipelines in one Azure DevOps pipeline folder:

| Pipeline | When it runs | What it does |
|---|---|---|
| **01-Primary-Deploy** | On every push to `main` (or manually) | Creates the primary web app in `centralindia` if it doesn't exist, deploys the repo code, checks the site is up |
| **02-DR-Deploy** | Manually only | Creates a **brand-new** web app in the DR region you pick (`<base>-dr-<runId>`), deploys the same code, checks it's up |

The page shows a **green "Primary is live"** or a **red "DR is live"** screen with the web app name, region, build number and commit. That makes the switch obvious in a demo.

```
Azure DevOps project: WebApp-DR-Demo
├── Repos/webapp-dr-demo   (this code)
└── Pipelines/
    └── WebApp-DR/           ← one folder
        ├── 01-Primary-Deploy   → pipelines/primary-deploy.yml
        └── 02-DR-Deploy        → pipelines/dr-deploy.yml

Each pipeline:  Build (zip app) → Provision (create web app if missing) → Deploy (zip deploy + health check)
```

## Repo layout
```
app/                          Node.js web app (no npm dependencies)
pipelines/primary-deploy.yml  pipeline 1
pipelines/dr-deploy.yml       pipeline 2 (manual, with a DR-region dropdown)
pipelines/variables.yml       shared settings — set appBaseName here
pipelines/templates/          shared build + provision/deploy stages
scripts/provision-webapp.sh   creates RG / plan / web app only if missing
setup/setup-devops.sh         one-time setup: project → repo → service connection → pipelines
setup/cleanup.sh              delete the Azure resources (and optionally the project)
```

---

## Option A — scripted setup (fastest)

1. Edit `pipelines/variables.yml`: set `appBaseName` to something unique, e.g. `drdemo-ak1103`.
2. Edit the top of `setup/setup-devops.sh`: set `ORG_URL` to your organization.
3. Run:
   ```bash
   az login
   ./setup/setup-devops.sh
   ```
   The script creates the project, creates the repo and pushes the code, creates a service principal and service connection, then creates both pipelines in the `\WebApp-DR` folder.
   - When `git push` asks for credentials, sign in with your Azure DevOps account, or use a PAT as the password.

## Option B — portal setup (click-through)

1. **Create the project:** dev.azure.com → *New project* → `WebApp-DR-Demo`, Git, Private.
2. **Push the code:** *Repos* → copy the clone URL, then run:
   ```bash
   git init -b main && git add -A && git commit -m "init"
   git remote add origin <clone-url> && git push -u origin main
   ```
3. **Create the service connection:** *Project settings → Service connections → New → Azure Resource Manager*.
   - Choose **Workload identity federation (automatic)** and pick your subscription. Leave the resource group blank.
   - Name it `sc-azure-webapp-demo` and tick *Grant access permission to all pipelines*.
4. **Create the pipelines:** *Pipelines → New pipeline → Azure Repos Git → webapp-dr-demo → Existing Azure Pipelines YAML file*.
   - Choose `/pipelines/primary-deploy.yml` → *Save* (not Run) → rename it `01-Primary-Deploy` and move it to folder `\WebApp-DR` (⋯ menu → *Rename/move*).
   - Repeat with `/pipelines/dr-deploy.yml` → `02-DR-Deploy`, same folder.

---

## Run the demo

1. **Primary:** run **01-Primary-Deploy** (or push any change to `app/`).
   - On the first run it creates the web app. Open `https://<appBaseName>-primary.azurewebsites.net` and you'll see the **green** page.
2. **Show CI:** edit a line in `app/server.js` in Azure Repos and commit to `main`. The primary pipeline starts automatically. It reuses the existing web app and shows the new build number.
3. **DR drill:** run **02-DR-Deploy**, pick a region (default `southindia`) and type a reason.
   - It creates a **new** web app, e.g. `<appBaseName>-dr-57`, and deploys the same commit.
   - The *Verify* step prints the URL. Open it to see the **red DR page**.
4. Run DR again and you get *another* new web app (`-dr-58`). Each run is a fresh environment.

From the CLI:
```bash
az pipelines run --name 01-Primary-Deploy --folder-path '\WebApp-DR'
az pipelines run --name 02-DR-Deploy --folder-path '\WebApp-DR' --parameters drRegion=southindia reason="DR drill"
```

## First-run prompts and gotchas
- **"No hosted parallelism has been purchased or granted":** new orgs need the free Microsoft-hosted grant. Request it at https://aka.ms/azpipelines-parallelism-request (takes about 1 business day). In the meantime, use a self-hosted agent and change `vmImage` / `pool`.
- **"Permission needed to access a resource":** on the first run, click *Permit* for the service connection.
- **Web app name taken:** names are global. Change `appBaseName`.
- **Region has no capacity / quota:** choose another DR region from the dropdown.
- **The primary still has to be up for a real failover:** this demo stands up the DR copy. Routing users to it (Azure Front Door / Traffic Manager or a DNS change) is the next step if you want automatic failover.

## Cost and cleanup
Each web app runs on its own **B1** plan (about $13/month, billed hourly). Every DR run adds one more. Remove everything with:
```bash
./setup/cleanup.sh            # Azure resources only
./setup/cleanup.sh --project  # also delete the DevOps project and the service principal
```
