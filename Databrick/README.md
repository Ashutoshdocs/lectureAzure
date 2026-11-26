# Azure Databricks ↔ SharePoint / OneDrive Integration

Read an Excel file stored in **SharePoint** (or **OneDrive for Business**), process it in **Azure Databricks**, find issues and recommendations, and write the results back to SharePoint.

```
 ┌──────────────────────┐   1. token (client credentials)   ┌─────────────────────┐
 │  Azure Databricks    │ ────────────────────────────────▶ │  Microsoft Entra ID │
 │  notebook / job      │ ◀──────────── access token ────── │  (App Registration) │
 │                      │                                   └─────────────────────┘
 │  secrets: tenant-id, │   2. GET file  /  4. PUT report   ┌─────────────────────┐
 │  client-id, secret   │ ◀───────────────────────────────▶ │  Microsoft Graph    │
 └─────────┬────────────┘                                   │  graph.microsoft.com│
           │ 3. Delta tables (bronze → silver → gold)       └─────────┬───────────┘
           ▼                                                          │
   Unity Catalog: main.sharepoint_demo.*                  SharePoint site / OneDrive
```

**How the connection works:** Databricks never talks to SharePoint directly. It authenticates as an Entra ID app (service principal), gets an OAuth token, and calls the **Microsoft Graph API** to download and upload files. OneDrive for Business runs on SharePoint, so the same code handles both. Only the "drive" lookup is different.

---

## Files in this package

| File | Purpose |
|---|---|
| `README.md` | This guide |
| `sample_sales_data.xlsx` | Sample document to **upload to SharePoint**. It has two sheets: `Sales` (600 orders) and `Targets` (monthly revenue target per region) |
| `sharepoint_to_databricks.py` | Databricks notebook (source format). It connects, downloads the file, builds Delta tables, analyses the data, and uploads `sales_insights.xlsx` back to SharePoint |

---

## Prerequisites

- An Azure subscription with an **Azure Databricks workspace** (Premium tier recommended for Unity Catalog and secret ACLs)
- A **Microsoft 365** tenant with SharePoint Online / OneDrive for Business
- Rights to create an **App Registration** in Entra ID, plus a **Global Admin / Privileged Role Admin** to grant admin consent
- Databricks CLI (`pip install databricks-cli`, or the new `databricks` CLI) **or** you can create secrets in the UI
- A cluster on **Databricks Runtime 14.3 LTS or later**

---

## Step 1: Upload the document to SharePoint

1. Open your SharePoint site, for example `https://yourcompany.sharepoint.com/sites/DataTeam`.
2. Go to **Documents** (the default library is called *Documents* in Graph; the URL shows *Shared Documents*).
3. Create the folders `Databricks/input` and `Databricks/output`.
4. Upload `sample_sales_data.xlsx` into `Databricks/input`.

> **Using OneDrive instead?** Upload the file to `OneDrive → My files → Databricks/input`. In the notebook, set `source_type = onedrive` and `onedrive_user = your UPN`.

Note these values for later:

| Value | Example |
|---|---|
| SharePoint hostname | `yourcompany.sharepoint.com` |
| Site path | `/sites/DataTeam` |
| Library name | `Documents` |
| File path inside the library | `Databricks/input/sample_sales_data.xlsx` |

> ⚠️ The path is **relative to the library root**. Do **not** start it with `Shared Documents/`.

---

## Step 2: Create an App Registration (service principal) in Entra ID

1. Go to **Azure Portal → Microsoft Entra ID → App registrations → New registration**.
   - Name: `databricks-sharepoint-connector`
   - Supported account types: *Single tenant*
   - Leave the Redirect URI empty → **Register**
2. Copy the **Application (client) ID** and the **Directory (tenant) ID**.
3. Go to **Certificates & secrets → New client secret**, set an expiry (for example 12 months), and **copy the Value now**. It is shown only once.
4. Go to **API permissions → Add a permission → Microsoft Graph → Application permissions**. Pick **one** option:

| Option | Permission | When to use |
|---|---|---|
| **A. Least privilege (recommended)** | `Sites.Selected` | The app can reach **only** the sites you grant it in Step 3 |
| B. Simple, broad | `Sites.ReadWrite.All` | Read/write on **all** sites. Fine for a PoC, but avoid it in production |
| OneDrive files | `Files.ReadWrite.All` | Needed when you read from a user's OneDrive |

   For read-only access, use `Sites.Read.All` / `Files.Read.All` and remove the upload step.

5. Click **Grant admin consent for <tenant>**. The status should show a green ✔.

---

## Step 3: Grant the app access to the site (only if you used `Sites.Selected`)

A SharePoint/Global admin runs this once. They use their own **delegated** token with `Sites.FullControl.All`, for example in Graph Explorer (https://developer.microsoft.com/graph/graph-explorer):

```http
# 1) Get the site ID
GET https://graph.microsoft.com/v1.0/sites/yourcompany.sharepoint.com:/sites/DataTeam

# 2) Grant the app write access to that site
POST https://graph.microsoft.com/v1.0/sites/{site-id}/permissions
Content-Type: application/json

{
  "roles": ["write"],
  "grantedToIdentities": [{
    "application": {
      "id": "<APPLICATION-CLIENT-ID>",
      "displayName": "databricks-sharepoint-connector"
    }
  }]
}
```

Or with PnP PowerShell:

```powershell
Connect-PnPOnline -Url https://yourcompany-admin.sharepoint.com -Interactive
Grant-PnPAzureADAppSitePermission -AppId "<APPLICATION-CLIENT-ID>" `
  -DisplayName "databricks-sharepoint-connector" `
  -Site "https://yourcompany.sharepoint.com/sites/DataTeam" -Permissions Write
```

---

## Step 4: Store the credentials in a Databricks secret scope

**Option A: Databricks CLI**

```bash
databricks auth login --host https://adb-<workspace-id>.<n>.azuredatabricks.net

databricks secrets create-scope sharepoint
databricks secrets put-secret sharepoint tenant-id     --string-value "<TENANT-ID>"
databricks secrets put-secret sharepoint client-id     --string-value "<CLIENT-ID>"
databricks secrets put-secret sharepoint client-secret --string-value "<CLIENT-SECRET>"

databricks secrets list-secrets sharepoint
```

**Option B: Azure Key Vault-backed scope**
Store the three values in Key Vault. Then open `https://<workspace-url>#secrets/createScope`, set the scope name to `sharepoint`, and enter the Key Vault *DNS name* and *Resource ID*. The secret names in Key Vault must be `tenant-id`, `client-id` and `client-secret`.

> Never paste secrets into a notebook. `dbutils.secrets.get()` values are redacted in notebook output.

---

## Step 5: Network check (only for locked-down workspaces)

If your workspace uses **VNet injection / NSG / Azure Firewall / no-public-egress**, allow outbound HTTPS (443) to:

- `login.microsoftonline.com` (token)
- `graph.microsoft.com` (files)
- `*.sharepoint.com` (download redirects)
- `pypi.org`, `files.pythonhosted.org` (for `%pip install`, or host the wheels in a Volume)

Quick test from a notebook cell:

```python
import requests; print(requests.get("https://graph.microsoft.com/v1.0/$metadata", timeout=10).status_code)  # 200 expected
```

---

## Step 6: Import and run the notebook

1. In Databricks, go to **Workspace → (your folder) → ⋮ → Import → File** and choose `sharepoint_to_databricks.py`. It opens as a notebook.
2. Attach it to a cluster (DBR 14.3 LTS+, single-user or shared access mode with Unity Catalog).
3. Fill in the widgets at the top:

| Widget | Value |
|---|---|
| `source_type` | `sharepoint` or `onedrive` |
| `sp_hostname` | `yourcompany.sharepoint.com` |
| `sp_site_path` | `/sites/DataTeam` |
| `library_name` | `Documents` |
| `onedrive_user` | `user@yourcompany.com` (OneDrive only) |
| `input_path` | `Databricks/input/sample_sales_data.xlsx` |
| `output_path` | `Databricks/output/sales_insights.xlsx` |
| `catalog_schema` | `main.sharepoint_demo` (you need `CREATE SCHEMA` rights, or use an existing schema) |

4. Click **Run all**.

### What the notebook does

| Stage | Output |
|---|---|
| Connect | MSAL client-credentials token → Graph → resolves site and library → drive ID |
| Download | Reads the `.xlsx` bytes in memory (nothing is stored on local disk) |
| Bronze | `sales_raw`, `targets_raw` Delta tables |
| Silver | `sales_clean`: duplicates removed, revenue calculated (returned orders = 0), month column added |
| Gold / analysis | `gold_vs_target`: actual vs target per region per month (On target / At risk / Missed)<br>`gold_returns`: return rate and revenue lost by region × category<br>`gold_products`: units, revenue and average discount per product<br>`gold_reps`: sales rep leaderboard<br>`gold_recommendations`: **findings + suggested solutions** |
| Write back | `sales_insights.xlsx` is uploaded to `Databricks/output/` in SharePoint |

With the sample data you should see, for example, a high **Electronics return rate in East**, regions that **missed revenue targets** in several months, and recommendations for each.

---

## Step 7: Schedule it as a Job (optional)

**Workflows → Jobs → Create job**
- Task type: *Notebook* → pick `sharepoint_to_databricks`
- Parameters: same keys as the widgets
- Cluster: a job cluster (cheaper than all-purpose)
- Trigger: *Scheduled* (for example daily 07:00 IST). Databricks' *File arrival* trigger doesn't watch SharePoint, so use a schedule

To run only when the file changed, keep the file's `lastModifiedDateTime` (from `GET /drives/{id}/root:/{path}`) in a small Delta table, and skip the run if it hasn't changed.

---

## Using your own document

1. Upload your file to SharePoint and update `input_path`.
2. In section 4 of the notebook, change `sheet_name` and the column names.
   - **CSV:** `pd.read_csv(io.BytesIO(file_bytes))`
   - **Many files in a folder:** loop over `list_folder()` and download each file
   - **Large files (> ~200 MB):** write the bytes to a UC Volume (`/Volumes/<cat>/<schema>/<vol>/file.xlsx`) and read them with Spark instead of pandas
3. Change the rules in section 6e to fit your business logic.

**Alternative (no custom code):** Databricks **Lakeflow Connect** offers a managed SharePoint connector in some regions or editions. Check the Databricks docs for its current availability. The Graph approach in this repo works everywhere.

---

## Troubleshooting

| Error | Cause / fix |
|---|---|
| `AADSTS7000215: Invalid client secret` | You copied the secret **ID** instead of the **Value**, or the secret expired |
| `AADSTS700016: Application not found` | Wrong `client-id` or `tenant-id` |
| `403 accessDenied` on `/sites/...` | Admin consent is missing, or with `Sites.Selected` the site grant (Step 3) wasn't done |
| `404 itemNotFound` | The path is wrong. It must be relative to the library root (drop `Shared Documents/`), and it is case- and space-sensitive |
| `Library 'X' not found` | The error message lists the library names. Use one of them exactly |
| `403` on `/users/.../drive` | The OneDrive user has never signed in, or the app lacks `Files.Read(Write).All` |
| `429 Too Many Requests` | The notebook already retries using `Retry-After`. Reduce how often the job runs |
| Connection timeout | See Step 5 (egress firewall) |
| `PERMISSION_DENIED: CREATE SCHEMA` | Use a schema you own, or ask a UC admin for the grant |

---

## Security checklist

- [ ] Use `Sites.Selected` instead of `*.All` in production
- [ ] Keep secrets in a Key Vault-backed scope; give **READ** on the scope only to the job's service principal or group
- [ ] Rotate the client secret before it expires, or use a **certificate** credential: `msal.ConfidentialClientApplication(client_credential={"private_key": ..., "thumbprint": ...})`
- [ ] Run scheduled jobs as a **Databricks service principal**, not a personal user
- [ ] Don't keep downloaded files on cluster local disk. Use memory or UC Volumes with ACLs
