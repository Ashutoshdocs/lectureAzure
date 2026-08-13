# Azure Function Visitor Counter

Two parts:

- `backend/`  — the Azure Function (deploy this to Azure)
- `frontend/` — the static webpage (open in a browser or host as a static site)

---

## Backend — run locally, then deploy

```powershell
cd backend
npm install          # installs @azure/functions (the v4 model)
func start           # test locally -> http://localhost:7071/api/visitorcounter
```

If local returns  {"visitors":1,"ip":"..."}  you're good. Then deploy:

```powershell
func azure functionapp publish myfunctionblaze
```

One-time cloud settings (needed for the v4 model + browser access):

```powershell
# v4 model flag in the cloud
az functionapp config appsettings set --name myfunctionblaze --resource-group keep --settings "AzureWebJobsFeatureFlags=EnableWorkerIndexing"

# allow the browser to call it (use * to test, tighten later)
az functionapp cors add --name myfunctionblaze --resource-group keep --allowed-origins "*"
```

Verify:

```powershell
curl -i https://myfunctionblaze-a9cva5dzeah7gvdw.centralus-01.azurewebsites.net/api/visitorcounter
```

Expect HTTP 200 with a JSON body (not 500).

---

## Frontend

`script.js` already points at your deployed URL. Just open `frontend/index.html`.

Tip: instead of opening the file directly (file://), serve it so CORS behaves:

```powershell
cd frontend
npx serve
```

Then open the http://localhost URL it prints.

---

## Note: the counter resets

`visitorCount` is stored in memory, so it resets on restart/scale. For a real
persistent counter, switch to Azure Table Storage or Cosmos DB.

---

## Reminder: add your logo

Put your `azure.png` into `frontend/images/`. It wasn't included in this bundle.
