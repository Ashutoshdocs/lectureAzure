# 🔐 GitHub Actions → Azure Login with OIDC (no passwords)

This guide sets up **OpenID Connect (OIDC)** so a GitHub Actions workflow can sign in to Azure **without storing a password or client secret**. It is used by `swap-slots.yml` to swap the `staging` slot into `production`.

```
GitHub Actions job (environment: production)
        │  1. asks GitHub for a short-lived OIDC token
        ▼
GitHub OIDC provider ── token says: "repo:owner/repo:environment:production"
        │  2. azure/login sends the token to Microsoft Entra ID
        ▼
Microsoft Entra ID ── checks the federated credential on the app registration
        │  3. match → returns an Azure access token (valid ~1 hour)
        ▼
az webapp deployment slot swap ...   (allowed by the "Website Contributor" role)
```

**Why OIDC?**

| Old way (client secret / `AZURE_CREDENTIALS`) | OIDC (this guide) |
|---|---|
| A secret stored in GitHub | Nothing secret stored: only IDs |
| Expires; must be rotated | Nothing to rotate |
| Works from anywhere it leaks to | Only works for **your repo + the `production` environment** |

---

## ✅ Prerequisites

| Need | Check |
|------|-------|
| Azure CLI, signed in | `az login` then `az account show` |
| GitHub CLI, signed in, run from inside the repo folder | `gh auth login` then `gh repo view` |
| Permission to create app registrations in Entra ID | Default for most users; otherwise ask an admin |
| **Owner** or **User Access Administrator** on the resource group | Needed to assign a role |
| Web App with a `staging` slot already created | See the main README |

> The commands below are **PowerShell**. A Bash version is further down.

---

## 1️⃣ Set variables

`$APP` and `$RG` come from the web app setup. Set them again if this is a new terminal.

```powershell
$APP      = "webapp2slots12345"                     # ← your Web App name
$RG       = "RG-WebAppSlots"                        # ← your resource group
$REPO     = "your-github-user/your-repo"            # ← owner/repo, exactly as on GitHub

$SUB      = az account show --query id -o tsv
$TENANT   = az account show --query tenantId -o tsv
```

> Make sure `az account show` is on the **subscription that contains the web app**. Switch with `az account set --subscription "<name or id>"`.

---

## 2️⃣ Create the app registration and service principal

The **app registration** is the identity GitHub will sign in as. The **service principal** is that identity inside your tenant, and it's what roles get assigned to.

```powershell
$APP_ID = az ad app create --display-name "gh-$APP-swap" --query appId -o tsv
$SP_ID  = az ad sp create --id $APP_ID --query id -o tsv

Write-Host "Client (app) ID:          $APP_ID"
Write-Host "Service principal obj ID: $SP_ID"
```

---

## 3️⃣ Give it permission on the resource group

**Website Contributor** can manage web apps (including slot swaps) but nothing else, and only inside this one resource group.

```powershell
az role assignment create `
  --assignee-object-id $SP_ID `
  --assignee-principal-type ServicePrincipal `
  --role "Website Contributor" `
  --scope "/subscriptions/$SUB/resourceGroups/$RG"
```

> Using `--assignee-object-id` with `--assignee-principal-type` avoids the common *"Cannot find user or service principal"* error that happens when a just-created service principal hasn't replicated yet.

---

## 4️⃣ Trust GitHub: add the federated credential

This tells Entra ID: *accept tokens from GitHub, but only for this repo when the job runs in the `production` environment.*

```powershell
@"
{
  "name": "github-production-env",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:$($REPO):environment:production",
  "audiences": ["api://AzureADTokenExchange"]
}
"@ | Set-Content fedcred.json

az ad app federated-credential create --id $APP_ID --parameters fedcred.json
Remove-Item fedcred.json
```

| Field | Meaning |
|-------|---------|
| `issuer` | GitHub's OIDC token issuer (always this URL) |
| `subject` | **Must match the job exactly.** `swap-slots.yml` uses `environment: production`, so the subject is `repo:<owner>/<repo>:environment:production` |
| `audiences` | Fixed value expected by `azure/login` |

---

## 5️⃣ Save the IDs as GitHub secrets

These are identifiers, not passwords. They are stored as secrets so they stay out of logs.

```powershell
gh secret set AZURE_CLIENT_ID       --body $APP_ID
gh secret set AZURE_TENANT_ID       --body $TENANT
gh secret set AZURE_SUBSCRIPTION_ID --body $SUB

# Used by swap-slots.yml (skip if already set)
gh variable set AZURE_WEBAPP_NAME    --body $APP
gh variable set AZURE_RESOURCE_GROUP --body $RG
```

Or in the browser: repo → **Settings → Secrets and variables → Actions**.

| Type | Name | Value |
|------|------|-------|
| Secret | `AZURE_CLIENT_ID` | `$APP_ID` |
| Secret | `AZURE_TENANT_ID` | `$TENANT` |
| Secret | `AZURE_SUBSCRIPTION_ID` | `$SUB` |
| Variable | `AZURE_WEBAPP_NAME` | your web app name |
| Variable | `AZURE_RESOURCE_GROUP` | your resource group |

---

## 6️⃣ Verify the setup

```powershell
# Federated credential exists with the right subject
az ad app federated-credential list --id $APP_ID --query "[].{name:name, subject:subject}" -o table

# Role assignment exists on the resource group
az role assignment list --assignee $SP_ID --all --query "[].{role:roleDefinitionName, scope:scope}" -o table

# Secrets and variables are in the repo
gh secret list
gh variable list
```

Expected:

```
Name                   Subject
---------------------  ------------------------------------------------------
github-production-env  repo:your-github-user/your-repo:environment:production

Role                 Scope
-------------------  ------------------------------------------------------------
Website Contributor  /subscriptions/<sub-id>/resourceGroups/RG-WebAppSlots
```

---

## 7️⃣ How the workflow uses it

The parts of `swap-slots.yml` that make OIDC work:

```yaml
permissions:
  id-token: write      # lets the job request an OIDC token from GitHub
  contents: read

jobs:
  swap:
    environment: production          # → token subject ends with :environment:production
    steps:
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - run: az webapp deployment slot swap -g $RESOURCE_GROUP -n $WEBAPP_NAME --slot staging --target-slot production
```

Run it: **Actions → Swap Staging to Production → Run workflow → type `SWAP`**.

---

## ➕ Allowing other workflows or triggers

Each place GitHub runs from has a different token subject, and each needs its own federated credential (up to 20 per app). Change `name` and `subject`, then repeat step 4:

| Job runs as… | `subject` |
|---|---|
| `environment: production` (this guide) | `repo:owner/repo:environment:production` |
| `environment: staging` | `repo:owner/repo:environment:staging` |
| Push to `main`, no environment | `repo:owner/repo:ref:refs/heads/main` |
| Pull requests | `repo:owner/repo:pull_request` |
| A tag, e.g. `v1.0` | `repo:owner/repo:ref:refs/tags/v1.0` |

> If a job has an `environment:`, the subject is **always** the environment form, whatever the branch.

---

## 🐧 Bash version (Azure Cloud Shell / Linux / macOS)

```bash
APP="webapp2slots12345"
RG="RG-WebAppSlots"
REPO="your-github-user/your-repo"
SUB=$(az account show --query id -o tsv)
TENANT=$(az account show --query tenantId -o tsv)

APP_ID=$(az ad app create --display-name "gh-$APP-swap" --query appId -o tsv)
SP_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)

az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
  --role "Website Contributor" --scope "/subscriptions/$SUB/resourceGroups/$RG"

az ad app federated-credential create --id "$APP_ID" --parameters "{
  \"name\": \"github-production-env\",
  \"issuer\": \"https://token.actions.githubusercontent.com\",
  \"subject\": \"repo:$REPO:environment:production\",
  \"audiences\": [\"api://AzureADTokenExchange\"]
}"

gh secret set AZURE_CLIENT_ID       --body "$APP_ID"
gh secret set AZURE_TENANT_ID       --body "$TENANT"
gh secret set AZURE_SUBSCRIPTION_ID --body "$SUB"
```

---

## 🛠️ Troubleshooting

| Error in the workflow log | Cause → Fix |
|---|---|
| `AADSTS70021: No matching federated identity record found` | The subject doesn't match. Check owner/repo spelling and case, and that the job has `environment: production`. Compare with `az ad app federated-credential list`. |
| `AADSTS700016: Application ... was not found in the directory` | Wrong `AZURE_CLIENT_ID` or `AZURE_TENANT_ID` secret. |
| `Unable to get ACTIONS_ID_TOKEN_REQUEST_URL` | The workflow is missing `permissions: id-token: write`. |
| `AuthorizationFailed ... does not have authorization to perform action 'Microsoft.Web/sites/slots/slotsswap/action'` | Role missing or on the wrong scope or subscription. Re-run step 3; role assignments can take a few minutes to apply. |
| `No subscriptions found` | `AZURE_SUBSCRIPTION_ID` is wrong, or the role was assigned in a different subscription. |
| Workflow waits and doesn't start | The `production` environment has required reviewers; approve it on the run page. |
| `az role assignment create`: insufficient privileges | You need Owner or User Access Administrator on the resource group. |

---

## 🧹 Clean up

Deleting the app registration also removes its service principal and federated credentials. Remove the role assignment first:

```powershell
az role assignment delete --assignee $SP_ID --scope "/subscriptions/$SUB/resourceGroups/$RG"
az ad app delete --id $APP_ID

gh secret delete AZURE_CLIENT_ID
gh secret delete AZURE_TENANT_ID
gh secret delete AZURE_SUBSCRIPTION_ID
```

Forgot `$APP_ID`? Find it with:

```powershell
az ad app list --display-name "gh-$APP-swap" --query "[].appId" -o tsv
```
