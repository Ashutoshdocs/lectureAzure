# PANAMAACADEMY Admit Card Demo — Azure Portal GUI Setup

This guide recreates the solution described in the supplied `run-all-hosted.ps1` script **using the Azure Portal wherever possible**. It deploys:

- An Azure Storage account
- A private Blob Storage container named `uploads` for generated PNG files
- Static website hosting from the same storage account (`$web` container)
- A Linux Azure Function App running Python 3.11 / Functions v4
- A Python HTTP-triggered function named `CreateStudent`
- A frontend page hosted on the Storage static website endpoint

The web page collects student name, department, roll number, year, and an optional photo. The function generates an admit-card PNG with Pillow, stores it in Blob Storage, and returns the image to the browser.

> **Important scope note:** The original PowerShell script creates the source files, publishes the function, updates the frontend URL, runs proof tests, and downloads a test image. The Azure Portal can create/configure the Azure resources, but it is not a complete replacement for authoring and packaging the Python function and HTML files. This README explains the portal-only resource steps and the minimum code-upload steps needed to finish the deployment. If you require absolutely no local tools or code upload, use the Azure Portal's built-in editor where available, or deploy the function project from a repository/ZIP package.

---

## 1. Architecture

```text
Student's browser
      |
      | HTTPS: Storage static website URL
      v
Azure Storage Account
  Static website ($web/index.html)
      |
      | HTTP POST JSON (CORS enabled)
      v
Azure Function App
  Python 3.11 / Functions v4
  Function: /api/CreateStudent
      |
      | STORAGE_CONNECTION_STRING
      v
Azure Blob Storage
  Container: uploads
  Object: <roll-number>.png
```

The static website and the Blob Storage container share the same Storage account. The `uploads` container should remain private; the function accesses it using the Storage connection string stored in Function App settings.

## 2. Prerequisites

- An Azure subscription with permission to create resource groups, storage accounts, and Function Apps.
- A modern browser and access to the Azure Portal: <https://portal.azure.com>.
- The project files from the supplied script:
  - `StudentFunction/host.json`
  - `StudentFunction/requirements.txt`
  - `StudentFunction/CreateStudent/function.json`
  - `StudentFunction/CreateStudent/__init__.py`
  - `frontend/index.html`
- A deployment method for the function files, such as a ZIP package or source repository. The source code in the supplied script creates these files automatically on a Windows machine; the Portal steps below describe the Azure resource setup.

### Values used in this guide

Use these names or replace them consistently with your own globally unique names.

| Setting | Example |
|---|---|
| Resource group | `rg-studentfunc-demo` |
| Region | `Central US` |
| Storage account | `stgstudent` + six lowercase letters/digits |
| Blob container | `uploads` |
| Function App | `func-student-` + unique suffix |
| Runtime | Python 3.11 |
| Functions runtime | Version 4 |
| Function route | `/api/CreateStudent` |

Storage account names must be globally unique, 3–24 characters, and lowercase letters/numbers only. Function App names must also be globally unique.

---

## 3. Create the resource group in Azure Portal

1. Open <https://portal.azure.com> and sign in.
2. Search for **Resource groups**.
3. Select **Create**.
4. Choose your subscription.
5. Enter `rg-studentfunc-demo`.
6. Select **Central US** (or a region available to your subscription).
7. Select **Review + create**, then **Create**.
8. Open the resource group after deployment.

## 4. Create the Storage account

1. In the Portal, search **Storage accounts** → **Create**.
2. On **Basics**:
   - Subscription: your subscription
   - Resource group: `rg-studentfunc-demo`
   - Storage account name: a globally unique lowercase name, e.g. `stgstudentabc123`
   - Region: the same region as the resource group/Function App where practical
   - Performance: **Standard**
   - Redundancy: **Locally-redundant storage (LRS)**
3. On **Advanced**:
   - Keep secure transfer required enabled.
   - Set **Allow Blob anonymous access** to **Disabled**.
   - For this demo, the function uses a connection string. If the Portal exposes **Allow storage account key access** / shared-key access, enable it for this configuration. Prefer managed identity and RBAC for production instead.
4. Select **Review + create** → **Create**.
5. Open the Storage account after deployment.

### 4.1 Copy the storage connection string securely

1. In the Storage account, open **Security + networking** → **Access keys** (the exact menu wording may vary).
2. Select **Show keys** if required.
3. Copy **Connection string** for `key1`.
4. Keep it private. Do not put it in the HTML page, source repository, screenshots, or public documentation. You will add it to Function App application settings in Step 7.

> If your organization disables shared-key access, the supplied code will need to be changed to use Microsoft Entra ID / managed identity rather than a connection string.

## 5. Enable Static website hosting

1. In the Storage account, open **Data management** → **Static website**.
2. Select **Enabled**.
3. Index document name: `index.html`.
4. Error document path: optionally `404.html`.
5. Select **Save**.
6. The Portal creates the special `$web` container.
7. Copy the **Primary endpoint** URL. It will look like `https://<storage-account>.<web-endpoint-domain>/`.
8. Open **Containers** and confirm that `$web` exists.

Static website hosting is served from a special endpoint. Keep Blob anonymous access disabled as configured above; do not make the `uploads` container public. The static website endpoint can serve files from `$web` without making the `uploads` container publicly readable.

## 6. Create the private uploads container

1. In the Storage account, select **Data storage** → **Containers**.
2. Select **+ Container**.
3. Name it `uploads`.
4. Set **Anonymous access level** to **Private (no anonymous access)**.
5. Select **Create**.

The function code uses the `uploads` container and names the image from the roll number, for example `PA-2025-014.png` (characters outside letters, digits, underscore, and hyphen are replaced).

---

## 7. Create the Function App

1. In the Portal, search **Function App** → **Create**.
2. Choose the option for a **Consumption** plan if available for your region/runtime. Plan options can change; select a Linux plan that supports Python 3.11 and Functions v4.
3. On **Basics**:
   - Subscription: your subscription
   - Resource group: `rg-studentfunc-demo`
   - Function App name: a globally unique name such as `func-student-abc123`
   - Publish: **Code**
   - Runtime stack: **Python**
   - Version: **3.11**
   - Region: same region as Storage where practical
   - Operating system: **Linux**
4. On **Storage**:
   - Select the Storage account created in Step 4.
5. On **Hosting/Monitoring**:
   - Choose the available Consumption hosting option.
   - Application Insights is recommended for logs and troubleshooting.
6. Select **Review + create** → **Create**.
7. Open the Function App and wait for deployment to complete.

> Portal labels and available hosting plans vary by region and Azure updates. If Python 3.11 is no longer offered for a new Function App in your region, choose a supported Python version and update/test the dependencies and deployment package accordingly.

## 8. Configure Function App application settings

1. Open the Function App.
2. Go to **Settings** → **Environment variables** (or **Configuration** in some Portal layouts).
3. Under **App settings**, add:
   - Name: `STORAGE_CONNECTION_STRING`
   - Value: the connection string copied in Step 4.1
4. Ensure the runtime settings include:
   - `FUNCTIONS_WORKER_RUNTIME` = `python`
   - `AzureWebJobsStorage` = the host storage connection string or the appropriate configured host-storage setting required by the chosen Functions setup
5. Save/apply changes and restart the Function App if prompted.

**Security:** The supplied sample uses a storage account connection string. Restrict access to the Function App and rotate the key if it is exposed. A production design should use managed identity and least-privilege RBAC.

---

## 9. Prepare and deploy the function code

The Portal resource steps do not create the application source automatically. The function project needs the following structure:

```text
StudentFunction/
├── host.json
├── requirements.txt
└── CreateStudent/
    ├── function.json
    └── __init__.py
```

The supplied PowerShell script writes the actual file contents. Reuse those generated files or copy the code from the original script into the matching files. Required Python packages in `requirements.txt` are:

```text
azure-functions
azure-storage-blob
Pillow
```

### Deployment options

**Option A — ZIP/repository deployment (recommended for repeatable deployments)**

1. Package the contents of `StudentFunction` in the layout expected by Azure Functions.
2. In the Function App, use the available **Deployment Center** / deployment option for your source repository, or deploy a prepared ZIP package using your organization's approved deployment workflow.
3. Wait for build/deployment to finish.
4. Open **Functions** in the Function App and confirm `CreateStudent` is discovered.

For Python Functions using the v1 programming model (the supplied project has `function.json` and `__init__.py`), ensure the chosen deployment process supports that model and installs `requirements.txt` on the Linux host. If deployment fails, check deployment logs and Application Insights.

**Option B — Portal editor (only if available)**

Some Function App configurations expose a code editor or in-portal function creation flow. If available:
1. Create an HTTP-triggered function named `CreateStudent`.
2. Set authorization to **Anonymous** only for a disposable demo, because the frontend does not send a function key.
3. Add the Python implementation and dependencies using the supported editor/deployment path.
4. Verify the function route is `/api/CreateStudent`.

The supplied code is a Python v1-model function; a Portal-created function may use a different programming model. Do not mix the v1 files with a v2 decorator-based function without converting the code.

### Important endpoint detail

The supplied frontend sends a **POST** request with JSON containing `name`, `department`, `rollno`, `year`, and optional `photo`. The function supports GET and POST. The frontend therefore requires the deployed function to accept POST requests and return JSON with these fields:

- `name`
- `department`
- `rollNo`
- `year`
- `recordId`
- `blobName`
- `container`
- `created`
- `imageBase64` (a `data:image/png;base64,...` URL)

---

## 10. Configure CORS

The browser page and Function App have different origins, so the Function App must allow the static website origin.

1. Open the Function App.
2. Find **API** → **CORS** (or the CORS setting available in your Portal layout).
3. Add the exact Static website **Primary endpoint origin** copied in Step 5, without a trailing path. Example: `https://stgstudentabc123.zXX.web.core.windows.net`.
4. Save the CORS configuration.
5. Do not add a wildcard origin for a production deployment. If you change the static website endpoint, update CORS.

The frontend uses `fetch()` with `Content-Type: application/json`; browsers may issue an OPTIONS preflight request, so CORS must allow the origin and the required method/headers.

---

## 11. Update the frontend API URL

The supplied HTML initially contains a placeholder:

```javascript
const API = "https://YOURFUNCTION.azurewebsites.net/api/CreateStudent";
```

Replace `YOURFUNCTION` with the actual Function App name, for example:

```javascript
const API = "https://func-student-abc123.azurewebsites.net/api/CreateStudent";
```

Also ensure the endpoint displayed in the page footer uses the same URL.

Do not put the storage connection string in the frontend. Only the public Function URL belongs here.

## 12. Upload the frontend to `$web`

1. Open the Storage account → **Containers** → **$web**.
2. Select **Upload**.
3. Choose the updated `index.html`.
4. Upload/overwrite the file.
5. Open the Static website **Primary endpoint** in a new browser tab.
6. Confirm that the PANAMAACADEMY admit-card form loads.

If the browser downloads `index.html` instead of rendering it, verify that it was uploaded as `text/html` and that you opened the **Static website Primary endpoint**, not the Blob service endpoint.

---

## 13. Test the end-to-end workflow

1. Open the Static website Primary endpoint.
2. Enter test values:
   - Student name: `Test Student`
   - Department: `Computer Science`
   - Roll number: `PA-2025-001`
   - Year: `Second Year`
   - Photo: optional
3. Select **Generate admit card**.
4. Confirm the page shows the generated PNG and metadata.
5. In the Azure Portal, open Storage account → **Containers** → `uploads`.
6. Confirm a PNG such as `PA-2025-001.png` exists.
7. Select the blob and use **Download** to verify that it can be downloaded.
8. In the Function App, inspect **Functions**, **Log stream**, and **Application Insights** (if enabled) if the request fails.

### Expected response

The browser should show an admit card and metadata similar to:

```json
{
  "name": "Test Student",
  "department": "Computer Science",
  "rollNo": "PA-2025-001",
  "year": "Second Year",
  "recordId": "STU-XXXXXXXX",
  "blobName": "PA-2025-001.png",
  "container": "uploads",
  "created": "2026-10-09 04:30:00 UTC",
  "imageBase64": "data:image/png;base64,..."
}
```

The record ID and timestamp are generated at runtime and will differ for each request. The PNG is returned to the browser as base64 and separately stored in Blob Storage.

---

## 14. Troubleshooting

| Symptom | Check |
|---|---|
| Function App does not start | Confirm supported Python/runtime versions, `FUNCTIONS_WORKER_RUNTIME=python`, host storage configuration, deployment logs, and Application Insights. |
| `CreateStudent` is missing | Confirm the deployed directory layout and that the deployment method supports the Python v1 programming model. |
| HTTP 404 | Confirm function discovery and exact route `/api/CreateStudent`. |
| HTTP 401/403 | Check function authorization level. The frontend as supplied does not include a function key; an Anonymous endpoint is required unless the frontend is updated to authenticate. |
| Browser CORS error | Add the exact static website origin in Function App CORS and save. Check preflight/OPTIONS behavior and browser console. |
| HTTP 400 | Fill in name, department, roll number, and year. |
| HTTP 500 | Check `STORAGE_CONNECTION_STRING`, container name `uploads`, Storage networking/firewall settings, and function logs. |
| Blob not created | Confirm the `uploads` container exists, is private, and the function identity/connection string has write access. |
| Missing Pillow or import errors | Confirm `Pillow` is in `requirements.txt` and that the deployment installs dependencies on Linux. |
| Static page shows old URL | Re-upload `index.html` after updating the API endpoint; hard-refresh the browser. |
| Image generation fails | Inspect function logs; check Pillow installation and photo decoding. |

---

## 15. Security and cost cleanup

- The sample uses an **anonymous HTTP trigger** and is intended for a teaching demo only. Anyone who obtains the URL may call it. Add authentication, rate limiting, and input/file-size validation before real use.
- The Storage connection string is a secret. Never expose it in frontend JavaScript or commit it to Git.
- Keep `uploads` private. The page displays the PNG from the function's base64 response; it does not require public Blob access.
- The function overwrites a blob if the same sanitized roll number is reused. Use unique names or change the code if records must never overwrite each other.
- After the practical, delete the resource group if it contains only demo resources: Azure Portal → **Resource groups** → `rg-studentfunc-demo` → **Delete resource group**. Confirm the exact name before deleting.
- Consumption hosting may reduce idle cost, but Storage and other enabled services may still incur charges. Review pricing and your subscription's limits before running the demo.

## 16. Final checklist

- [ ] Resource group created.
- [ ] Storage account created.
- [ ] Static website enabled and Primary endpoint copied.
- [ ] Private `uploads` container created.
- [ ] Function App created with supported Python and Functions runtime.
- [ ] `STORAGE_CONNECTION_STRING` configured securely.
- [ ] Function code deployed and `CreateStudent` discovered.
- [ ] CORS allows the exact static website origin.
- [ ] `frontend/index.html` points to the live Function URL.
- [ ] `index.html` uploaded to `$web`.
- [ ] Test form returns an admit-card PNG.
- [ ] PNG appears in `uploads` and can be downloaded.

---

## Reference URLs

- Azure Portal: <https://portal.azure.com>
- Azure Functions documentation: <https://learn.microsoft.com/azure/azure-functions/>
- Azure Storage static website: <https://learn.microsoft.com/azure/storage/blobs/storage-blob-static-website>
- Azure Functions Python developer guide: <https://learn.microsoft.com/azure/azure-functions/functions-reference-python>
