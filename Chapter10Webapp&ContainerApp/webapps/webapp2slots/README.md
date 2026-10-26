# ☁ Azure Web App Deployment Slots with GitHub Actions

Deploy a static page from any branch to the **staging** or **production** slot of an Azure Web App, then **swap** staging into production. The page shows which slot is serving it, so a swap is visible straight away.

```
 GitHub Actions                       Azure App Service (S1)
 ───────────────                      ─────────────────────────────────────
 Deploy (branch, slot=staging) ──▶    myapp-staging.azurewebsites.net   🟡 STAGING
 Deploy (branch, slot=production) ─▶  myapp.azurewebsites.net           🟢 PRODUCTION
 Swap (type SWAP) ──────────────▶     staging ⇄ production  (zero downtime)
```

---

## 📁 Repository layout

```
.github/
└── workflows/
    ├── deploy-slot.yml     # Manual: pick branch + slot, inject build info, deploy, verify
    └── swap-slots.yml      # Manual: swap staging → production (type SWAP to confirm)
webapp2slots/
├── index.html              # The page; __PLACEHOLDERS__ are filled in by the workflow
└── web.config              # Only used on Windows App Service (default doc + no-cache)
README.md
```

### What the page shows

| Field | Where it comes from |
|-------|--------------------|
| **Currently serving from slot** | Worked out live in the browser from the hostname (`myapp-staging…` = staging) |
| **Deployed to slot** | The slot chosen when the workflow ran |
| 🔄 **Swapped** note | Appears when the two differ, e.g. a build deployed to staging now live in production |
| Branch, commit (linked), repo, web app, run #, actor, time | Injected by the workflow |

The page turns **green** in production and **amber** in staging.

---

## 🧱 Runtime stack

The app is plain HTML, so it needs a stack that serves static files. Pick one:

| Option | OS | Runtime stack | Startup command | Notes |
|--------|----|---------------|-----------------|-------|
| **A (recommended)** | Linux | **Node 22 LTS** (`NODE:22-lts`) | `pm2 serve /home/site/wwwroot --no-daemon` | PM2 ships in the Node image and serves the folder as a static site. |
| B | Linux | PHP 8.3 (`PHP:8.3`) | *(none)* | Built-in nginx serves `index.html` with no extra config. |
| C | Windows | ASP.NET V4.8 (or any .NET) | *(none)* | IIS serves `index.html`; `web.config` adds no-cache headers. |

> ⚠️ With option A, the **startup command must be set on both slots**. Without it, the Node container looks for a `server.js`/`npm start`, finds none and shows the default page — the workflow's verify step will then fail.

Check the exact runtime names available in your region with:

```powershell
az webapp list-runtimes --os linux -o table
```

### Plan tier

Deployment slots need **Standard (S1) or higher**. Free and Basic tiers do not support slots.

---

## 1️⃣ Create the Azure resources (PowerShell)

```powershell
$RG       = "RG-WebAppSlots"
$LOCATION = "centralindia"
$PLAN     = "SlotsPlan"
$APP      = "webapp2slots$(Get-Random -Maximum 99999)"   # globally unique
$STARTUP  = "pm2 serve /home/site/wwwroot --no-daemon"

az group create -n $RG -l $LOCATION

# Linux S1 plan + web app on Node 22 LTS (Option A)
az appservice plan create -g $RG -n $PLAN --sku S1 --is-linux
az webapp create -g $RG -p $PLAN -n $APP --runtime "NODE:22-lts"
az webapp config set -g $RG -n $APP --startup-file $STARTUP

# Staging slot (copies production's settings) + same startup command
az webapp deployment slot create -g $RG -n $APP --slot staging --configuration-source $APP
az webapp config set -g $RG -n $APP --slot staging --startup-file $STARTUP

Write-Host "Production: https://$APP.azurewebsites.net"
Write-Host "Staging:    https://$APP-staging.azurewebsites.net"
```

> **Option B / C instead?** Use `--runtime "PHP:8.3"` on Linux, or create a Windows plan (`az appservice plan create ... --sku S1` without `--is-linux`) and `--runtime "ASPNET:V4.8"`. Skip both `--startup-file` lines.

---

## 2️⃣ Allow publish-profile deployments

New web apps have **SCM basic auth turned off**, and publish profiles depend on it. Turn it on for both slots:

```powershell
az resource update -g $RG --name scm --namespace Microsoft.Web `
  --resource-type basicPublishingCredentialsPolicies `
  --parent "sites/$APP" --set properties.allow=true

az resource update -g $RG --name scm --namespace Microsoft.Web `
  --resource-type basicPublishingCredentialsPolicies `
  --parent "sites/$APP/slots/staging" --set properties.allow=true
```

Portal equivalent: **Web App → Settings → Configuration → General settings → SCM Basic Auth Publishing Credentials = On** (repeat on the staging slot).

---

## 3️⃣ Add GitHub secrets and variables

Each slot has its **own** publish profile.

**With the GitHub CLI** (fastest):

```powershell
az webapp deployment list-publishing-profiles -g $RG -n $APP --xml |
  gh secret set AZURE_WEBAPP_PUBLISH_PROFILE

az webapp deployment list-publishing-profiles -g $RG -n $APP --slot staging --xml |
  gh secret set AZURE_WEBAPP_STAGING_PUBLISH_PROFILE

gh variable set AZURE_WEBAPP_NAME    --body $APP
gh variable set AZURE_RESOURCE_GROUP --body $RG
```

**Or in the browser:** repo → **Settings → Secrets and variables → Actions**

| Type | Name | Value |
|------|------|-------|
| Secret | `AZURE_WEBAPP_PUBLISH_PROFILE` | Production publish profile XML (portal: Web App → **Download publish profile**) |
| Secret | `AZURE_WEBAPP_STAGING_PUBLISH_PROFILE` | Staging slot publish profile XML (open the slot → **Download publish profile**) |
| Variable | `AZURE_WEBAPP_NAME` | e.g. `webapp2slots12345` |
| Variable | `AZURE_RESOURCE_GROUP` | e.g. `RG-WebAppSlots` (only needed for the swap workflow) |

> Why a *variable* for the app name? Secrets are masked as `***` in logs, which hides the name and the deployed URL. The workflow still falls back to an `AZURE_WEBAPP_NAME` secret if that's what you already have.

---

## 4️⃣ Deploy

GitHub → **Actions → Deploy Azure WebApp Slot → Run workflow**

1. **Branch**: e.g. `main` or `feature/new-banner`
2. **Slot**: `staging` or `production`

The workflow:

1. Checks out the branch and checks the configuration
2. Fills in the `__PLACEHOLDERS__` in `index.html` (HTML-escaped; fails if any are left)
3. Deploys `webapp2slots/` to the chosen slot
4. **Verifies** the new commit is actually being served (retries for 2 minutes)
5. Writes a summary table on the run page, with the live URL as an environment link

---

## 5️⃣ Demo: staging → swap → production

1. Deploy `main` to **production** → production shows 🟢 PRODUCTION, deployed to `production`.
2. Make a visible change on a branch, deploy it to **staging** → staging shows 🟡 STAGING with the new commit. Production is untouched.
3. Swap (next section, or **Portal → Deployment slots → Swap**).
4. Refresh production: it now shows the new commit with the 🔄 **Swapped** note — *deployed to staging, now live in production*. Staging now holds the old production build, ready for an instant rollback (swap again).

---

## 6️⃣ Swap with GitHub Actions (optional)

`swap-slots.yml` logs in to Azure with **OIDC** (no stored password). One-time setup:

```powershell
$SUB      = az account show --query id -o tsv
$TENANT   = az account show --query tenantId -o tsv
$REPO     = "your-github-user/your-repo"          # ← change

$APP_ID = az ad app create --display-name "gh-$APP-swap" --query appId -o tsv
az ad sp create --id $APP_ID
az role assignment create --assignee $APP_ID --role "Website Contributor" `
  --scope "/subscriptions/$SUB/resourceGroups/$RG"

@"
{
  "name": "github-production-env",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:$($REPO):environment:production",
  "audiences": ["api://AzureADTokenExchange"]
}
"@ | Set-Content fedcred.json

az ad app federated-credential create --id $APP_ID --parameters fedcred.json

gh secret set AZURE_CLIENT_ID       --body $APP_ID
gh secret set AZURE_TENANT_ID       --body $TENANT
gh secret set AZURE_SUBSCRIPTION_ID --body $SUB
```

Then **Actions → Swap Staging to Production → Run workflow**, type `SWAP`. The log shows which commit is in each slot before and after.

Or swap from your machine:

```powershell
az webapp deployment slot swap -g $RG -n $APP --slot staging --target-slot production
```

### 🛡️ Approval gate for production

Repo → **Settings → Environments → production → Required reviewers**. Both workflows use the `production` environment, so deploying to production or swapping will wait for approval.

---

## 🛠️ Troubleshooting

| Symptom | Fix |
|---------|-----|
| Deploy step: `401 Unauthorized` / publish profile invalid | SCM basic auth is off (step 2), or the profile is for the wrong slot. Re-download it after enabling basic auth. |
| Default Azure page or "Application Error" | Linux Node: startup command missing on that slot. Run `az webapp config set ... --startup-file "pm2 serve /home/site/wwwroot --no-daemon"` (add `--slot staging` for staging). |
| Verify step fails but the deploy succeeded | Same as above, or the app is still restarting. Check `az webapp log tail -g $RG -n $APP [--slot staging]`. |
| Page still shows the old build | Browser cache; hard-refresh (Ctrl+F5). |
| "Currently serving from slot" is wrong | You're using a custom domain; the slot is read from the `*.azurewebsites.net` hostname. |
| `Error: Set repository variable AZURE_WEBAPP_NAME` | Add the variable (step 3). |
| Swap workflow: `AADSTS70021` / no matching federated identity | The federated credential subject must be exactly `repo:<owner>/<repo>:environment:production`. |
| Slots option missing in the portal | The plan is Free/Basic. Scale up to S1: `az appservice plan update -g $RG -n $PLAN --sku S1`. |

---

## 🧹 Clean up

```powershell
az group delete -n $RG --yes --no-wait
az ad app delete --id $APP_ID      # if you created the OIDC app
```
