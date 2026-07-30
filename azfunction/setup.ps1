# ===========================================================
#  run-all.ps1
#  ONE script: builds the project (nicer frontend + cleaner
#  output file), provisions Azure, deploys, and PROVES it works.
#
#  Run it:   cd D:\ ;  .\run-all.ps1
#
#  Prerequisites:
#    - Azure CLI            : az --version
#    - Functions Core Tools : func --version   (v4.x)
#    - Signed in            : az login
# ===========================================================

$ErrorActionPreference = "Stop"

# -----------------------------------------------------------
# 0. Config
# -----------------------------------------------------------
$location  = "centralus"
$suffix    = -join ((48..57) + (97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })

$Project   = "D:\StudentFunctionDemo"
$rg        = "rg-studentfunc-demo"
$storage   = "stgstudent$suffix"      # 3-24 chars, lowercase + digits, no hyphens
$funcApp   = "func-student-$suffix"   # https://func-student-xxxx.azurewebsites.net
$container = "uploads"

Write-Host "==========================================================="
Write-Host " Project        : $Project"
Write-Host " Resource Group : $rg"
Write-Host " Storage        : $storage"
Write-Host " Function App   : $funcApp"
Write-Host " Location       : $location"
Write-Host "==========================================================="

# -----------------------------------------------------------
# 1. Prerequisite checks
# -----------------------------------------------------------
foreach ($tool in @("az", "func")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "'$tool' is not installed or not on PATH. Install it and re-run."
    }
}
$acct = az account show --query name -o tsv 2>$null
if (-not $acct) {
    Write-Host "Not logged in. Running az login..." -ForegroundColor Yellow
    az login | Out-Null
}
Write-Host "Using subscription: $(az account show --query name -o tsv)" -ForegroundColor Cyan

# -----------------------------------------------------------
# 2. Build the project files
# -----------------------------------------------------------
Write-Host "`n[1/7] Creating project files..." -ForegroundColor Green

New-Item -ItemType Directory -Force -Path $Project | Out-Null
New-Item -ItemType Directory -Force -Path "$Project\frontend" | Out-Null
New-Item -ItemType Directory -Force -Path "$Project\StudentFunction" | Out-Null
New-Item -ItemType Directory -Force -Path "$Project\StudentFunction\CreateStudent" | Out-Null

@'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Student Registration &middot; Azure Functions</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@500;600;700&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
  :root{
    --ink:#0e1330;
    --muted:#5b6079;
    --line:#e6e8f0;
    --indigo:#4f46e5;
    --indigo-deep:#3730a3;
    --cyan:#06b6d4;
    --ok:#0f9d63;
    --ok-bg:#e9f8f0;
    --err:#d64550;
    --err-bg:#fdecec;
    --card:#ffffff;
  }

  *{box-sizing:border-box;}

  html,body{height:100%;}

  body{
    margin:0;
    font-family:"Inter",system-ui,sans-serif;
    color:var(--ink);
    background:
      radial-gradient(1100px 600px at 15% -10%, #dbe4ff 0%, transparent 55%),
      radial-gradient(900px 600px at 110% 20%, #d3f4fb 0%, transparent 50%),
      linear-gradient(180deg,#f6f8ff 0%,#eef1fb 100%);
    display:flex;
    align-items:center;
    justify-content:center;
    padding:24px;
  }

  .card{
    width:100%;
    max-width:440px;
    background:var(--card);
    border:1px solid var(--line);
    border-radius:20px;
    padding:34px 32px 28px;
    box-shadow:0 1px 2px rgba(16,20,60,.04), 0 24px 48px -24px rgba(16,20,60,.28);
  }

  .eyebrow{
    font-family:"JetBrains Mono",monospace;
    font-size:11px;
    letter-spacing:.18em;
    text-transform:uppercase;
    color:var(--indigo);
    display:flex;
    align-items:center;
    gap:8px;
    margin-bottom:14px;
  }
  .eyebrow .dot{
    width:7px;height:7px;border-radius:50%;
    background:var(--cyan);
    box-shadow:0 0 0 4px rgba(6,182,212,.15);
  }

  h1{
    font-family:"Space Grotesk",sans-serif;
    font-weight:700;
    font-size:27px;
    line-height:1.15;
    margin:0 0 6px;
    letter-spacing:-.01em;
  }

  .sub{
    color:var(--muted);
    font-size:14px;
    margin:0 0 24px;
    line-height:1.5;
  }

  label{
    display:block;
    font-size:13px;
    font-weight:600;
    margin-bottom:7px;
  }

  .field{
    display:flex;
    align-items:center;
    gap:10px;
    border:1.5px solid var(--line);
    border-radius:12px;
    padding:0 14px;
    background:#fbfcff;
    transition:border-color .15s, box-shadow .15s, background .15s;
  }
  .field:focus-within{
    border-color:var(--indigo);
    background:#fff;
    box-shadow:0 0 0 4px rgba(79,70,229,.12);
  }
  .field svg{flex:none;color:var(--muted);}
  input{
    border:0;
    outline:0;
    background:transparent;
    padding:13px 0;
    font-size:15px;
    font-family:inherit;
    color:var(--ink);
    width:100%;
  }
  input::placeholder{color:#a2a7be;}

  button{
    width:100%;
    margin-top:16px;
    padding:13px 18px;
    font-family:"Space Grotesk",sans-serif;
    font-weight:600;
    font-size:15px;
    color:#fff;
    background:linear-gradient(180deg,var(--indigo) 0%,var(--indigo-deep) 100%);
    border:0;
    border-radius:12px;
    cursor:pointer;
    display:flex;
    align-items:center;
    justify-content:center;
    gap:9px;
    transition:transform .12s, box-shadow .2s, opacity .2s;
    box-shadow:0 10px 20px -10px rgba(79,70,229,.7);
  }
  button:hover:not(:disabled){transform:translateY(-1px);}
  button:active:not(:disabled){transform:translateY(0);}
  button:disabled{opacity:.7;cursor:default;box-shadow:none;}

  .spinner{
    width:16px;height:16px;flex:none;
    border:2px solid rgba(255,255,255,.4);
    border-top-color:#fff;
    border-radius:50%;
    animation:spin .7s linear infinite;
  }
  @keyframes spin{to{transform:rotate(360deg);}}

  /* ---- signature: request lifecycle ---- */
  .flow{
    display:flex;
    align-items:flex-start;
    justify-content:space-between;
    margin:26px 2px 4px;
    position:relative;
  }
  .flow::before{
    content:"";
    position:absolute;
    top:15px;left:14%;right:14%;
    height:2px;
    background:var(--line);
    z-index:0;
  }
  .stage{
    position:relative;
    z-index:1;
    text-align:center;
    width:33%;
  }
  .stage .node{
    width:30px;height:30px;
    margin:0 auto 8px;
    border-radius:50%;
    background:#fff;
    border:2px solid var(--line);
    display:flex;align-items:center;justify-content:center;
    color:var(--muted);
    transition:all .3s ease;
  }
  .stage .node svg{width:15px;height:15px;}
  .stage .cap{
    font-family:"JetBrains Mono",monospace;
    font-size:10px;
    letter-spacing:.06em;
    text-transform:uppercase;
    color:var(--muted);
    transition:color .3s;
  }
  .stage.active .node{
    border-color:var(--indigo);
    color:var(--indigo);
    box-shadow:0 0 0 5px rgba(79,70,229,.12);
  }
  .stage.done .node{
    border-color:var(--ok);
    background:var(--ok);
    color:#fff;
  }
  .stage.done .cap{color:var(--ok);}

  /* ---- result ---- */
  .result{
    margin-top:22px;
    border-radius:13px;
    padding:16px 16px 14px;
    font-size:14px;
    display:none;
    animation:rise .35s ease;
  }
  @keyframes rise{from{opacity:0;transform:translateY(6px);}to{opacity:1;transform:none;}}
  .result.show{display:block;}
  .result.ok{background:var(--ok-bg);border:1px solid #bde9d2;}
  .result.err{background:var(--err-bg);border:1px solid #f6c9cc;}

  .result .head{
    display:flex;align-items:center;gap:9px;
    font-family:"Space Grotesk",sans-serif;
    font-weight:600;font-size:15px;margin-bottom:10px;
  }
  .result.ok .head{color:var(--ok);}
  .result.err .head{color:var(--err);}

  .rec{
    display:grid;
    grid-template-columns:auto 1fr;
    gap:6px 14px;
    font-size:13px;
  }
  .rec dt{color:var(--muted);}
  .rec dd{
    margin:0;
    font-family:"JetBrains Mono",monospace;
    color:var(--ink);
    word-break:break-all;
  }
  .result.err .msg{color:#8a2b32;line-height:1.5;}

  .foot{
    margin-top:22px;
    padding-top:16px;
    border-top:1px solid var(--line);
    font-family:"JetBrains Mono",monospace;
    font-size:11px;
    color:#9aa0ba;
    display:flex;align-items:center;gap:8px;
    overflow:hidden;
  }
  .foot .verb{color:var(--indigo);}
  .foot .ep{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}

  @media (prefers-reduced-motion: reduce){
    *{animation:none !important; transition:none !important;}
  }
</style>
</head>
<body>
  <main class="card">
    <div class="eyebrow"><span class="dot"></span>Azure Functions Demo</div>
    <h1>Register a student</h1>
    <p class="sub">Enter a name. An HTTP-triggered function writes the record to Blob&nbsp;Storage and hands back the result.</p>

    <label for="name">Student name</label>
    <div class="field">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
      <input id="name" placeholder="e.g. Aditya Sharma" autocomplete="off" autofocus>
    </div>

    <button id="submit" onclick="submitStudent()">
      <span id="btnlabel">Register student</span>
    </button>

    <div class="flow" id="flow">
      <div class="stage" data-stage="0">
        <div class="node"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="5" y1="12" x2="19" y2="12"/><polyline points="12 5 19 12 12 19"/></svg></div>
        <div class="cap">Request</div>
      </div>
      <div class="stage" data-stage="1">
        <div class="node"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg></div>
        <div class="cap">Function</div>
      </div>
      <div class="stage" data-stage="2">
        <div class="node"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14a9 3 0 0 0 18 0V5"/><path d="M3 12a9 3 0 0 0 18 0"/></svg></div>
        <div class="cap">Blob</div>
      </div>
    </div>

    <div class="result" id="result">
      <div class="head" id="resultHead"></div>
      <div id="resultBody"></div>
    </div>

    <div class="foot">
      <span class="verb">GET</span>
      <span class="ep" id="endpoint">https://YOURFUNCTION.azurewebsites.net/api/CreateStudent</span>
    </div>
  </main>

<script>
  const API = "https://YOURFUNCTION.azurewebsites.net/api/CreateStudent";
  const $ = (id) => document.getElementById(id);
  const stages = [...document.querySelectorAll(".stage")];

  document.getElementById("endpoint").textContent = API;
  $("name").addEventListener("keydown", (e) => { if (e.key === "Enter") submitStudent(); });

  function setStage(i, state){
    stages.forEach((s, idx) => {
      s.classList.remove("active","done");
      if (idx < i) s.classList.add("done");
      else if (idx === i) s.classList.add(state || "active");
    });
  }
  function resetFlow(){ stages.forEach(s => s.classList.remove("active","done")); }

  function showResult(kind, headHTML, bodyHTML){
    const r = $("result");
    r.className = "result show " + kind;
    $("resultHead").innerHTML = headHTML;
    $("resultBody").innerHTML = bodyHTML;
  }

  function loading(on){
    const btn = $("submit");
    btn.disabled = on;
    $("btnlabel").textContent = on ? "Registering\u2026" : "Register student";
    let sp = btn.querySelector(".spinner");
    if (on && !sp){ sp = document.createElement("span"); sp.className = "spinner"; btn.prepend(sp); }
    if (!on && sp) sp.remove();
  }

  function parse(text){
    const out = {};
    text.split(/\r?\n/).forEach(line => {
      const m = line.match(/^\s*([A-Za-z ]+?)\s*:\s*(.+?)\s*$/);
      if (m) out[m[1].trim().toLowerCase()] = m[2].trim();
    });
    return out;
  }

  async function submitStudent(){
    const name = $("name").value.trim();
    if (!name){
      showResult("err",
        `<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg> Name required`,
        `<div class="msg">Type a student name before registering.</div>`);
      resetFlow();
      $("name").focus();
      return;
    }

    loading(true);
    setStage(0, "active");

    try {
      // stage: hitting the function
      setTimeout(() => setStage(1, "active"), 250);

      const res = await fetch(API + "?name=" + encodeURIComponent(name));
      const text = (await res.text()).trim();

      if (!res.ok) throw new Error(text || ("Request failed (" + res.status + ")"));

      // stage: written to blob
      setStage(2, "done");

      const info = parse(text);
      const blob = info["blob name"] || (name + ".txt");
      const rid  = info["record id"] || "\u2014";

      showResult("ok",
        `<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg> Registered ${escapeHtml(name)}`,
        `<dl class="rec">
           <dt>Blob</dt><dd>${escapeHtml(blob)}</dd>
           <dt>Record ID</dt><dd>${escapeHtml(rid)}</dd>
           <dt>Container</dt><dd>uploads</dd>
         </dl>`);
    } catch (err) {
      resetFlow();
      showResult("err",
        `<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg> Couldn't register`,
        `<div class="msg">${escapeHtml(err.message)}<br>Check that the function URL is correct and the app is running.</div>`);
    } finally {
      loading(false);
    }
  }

  function escapeHtml(s){
    return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  }
</script>
</body>
</html>
'@ | Set-Content "$Project\frontend\index.html"

@'
{
  "version": "2.0"
}
'@ | Set-Content "$Project\StudentFunction\host.json"

@'
azure-functions
azure-storage-blob
'@ | Set-Content "$Project\StudentFunction\requirements.txt"

@'
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "",
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "STORAGE_CONNECTION_STRING": ""
  }
}
'@ | Set-Content "$Project\StudentFunction\local.settings.json"

@'
{
  "scriptFile": "__init__.py",
  "bindings": [
    {
      "authLevel": "anonymous",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": [ "get", "post" ]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "$return"
    }
  ]
}
'@ | Set-Content "$Project\StudentFunction\CreateStudent\function.json"

@'
import azure.functions as func
from azure.storage.blob import BlobServiceClient
from datetime import datetime, timezone
import os
import uuid

connection = os.environ["STORAGE_CONNECTION_STRING"]
blob_service = BlobServiceClient.from_connection_string(connection)
container = "uploads"


def build_record(name: str, record_id: str, created: str) -> str:
    """Return a clean, aligned text record for the blob file."""
    return (
        "============================================================\n"
        "                STUDENT REGISTRATION RECORD\n"
        "============================================================\n"
        "\n"
        f"   Student Name   : {name}\n"
        f"   Record ID      : {record_id}\n"
        f"   Status         : Registered\n"
        f"   Created (UTC)  : {created}\n"
        f"   Container      : {container}\n"
        f"   Blob Name      : {name}.txt\n"
        "\n"
        "------------------------------------------------------------\n"
        "   Generated automatically by an HTTP-triggered Azure\n"
        "   Function and stored in Azure Blob Storage.\n"
        "============================================================\n"
    )


def main(req: func.HttpRequest) -> func.HttpResponse:
    # accept name from query string or JSON body
    name = req.params.get("name")
    if not name:
        try:
            name = (req.get_json() or {}).get("name")
        except ValueError:
            name = None

    if not name or not name.strip():
        return func.HttpResponse("Please provide a student name.", status_code=400)

    name = name.strip()
    record_id = "STU-" + uuid.uuid4().hex[:8].upper()
    created = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    # write the formatted record to the 'uploads' container as <name>.txt
    blob = blob_service.get_blob_client(container=container, blob=f"{name}.txt")
    blob.upload_blob(build_record(name, record_id, created), overwrite=True)

    # response body (the frontend parses the "Key : Value" lines)
    reply = (
        f"Hello {name}\n"
        "File created successfully.\n"
        f"Blob Name : {name}.txt\n"
        f"Record ID : {record_id}\n"
        f"Created : {created}\n"
    )
    return func.HttpResponse(reply, status_code=200, mimetype="text/plain")
'@ | Set-Content "$Project\StudentFunction\CreateStudent\__init__.py"

# -----------------------------------------------------------
# 3. Resource group
# -----------------------------------------------------------
Write-Host "[2/7] Creating resource group..." -ForegroundColor Green
az group create --name $rg --location $location --output none

# -----------------------------------------------------------
# 4. Storage account (+ uploads container)
#    shared-key access ON: the function uses a connection string
# -----------------------------------------------------------
Write-Host "[3/7] Creating storage account..." -ForegroundColor Green
az storage account create `
    --name $storage `
    --resource-group $rg `
    --location $location `
    --sku Standard_LRS `
    --allow-blob-public-access false `
    --allow-shared-key-access true `
    --output none

$conn = az storage account show-connection-string `
    --name $storage --resource-group $rg --query connectionString -o tsv

Write-Host "      Creating '$container' container..." -ForegroundColor Green
az storage container create --name $container --connection-string $conn --output none

# -----------------------------------------------------------
# 5. Function app (Linux, Python 3.11, Functions v4, Consumption)
# -----------------------------------------------------------
Write-Host "[4/7] Creating function app (takes a minute)..." -ForegroundColor Green
az functionapp create `
    --name $funcApp `
    --resource-group $rg `
    --storage-account $storage `
    --consumption-plan-location $location `
    --os-type Linux `
    --runtime python `
    --runtime-version 3.11 `
    --functions-version 4 `
    --output none

Write-Host "      Setting STORAGE_CONNECTION_STRING..." -ForegroundColor Green
az functionapp config appsettings set `
    --name $funcApp --resource-group $rg `
    --settings "STORAGE_CONNECTION_STRING=$conn" --output none

# -----------------------------------------------------------
# 6. Deploy (remote build installs pip packages on Linux)
# -----------------------------------------------------------
Write-Host "[5/7] Deploying code..." -ForegroundColor Green
Push-Location "$Project\StudentFunction"
try {
    func azure functionapp publish $funcApp --build remote
}
finally {
    Pop-Location
}

# -----------------------------------------------------------
# 7. PROOF IT WORKS
# -----------------------------------------------------------
$fnUrl    = "https://$funcApp.azurewebsites.net/api/CreateStudent"
$testName = "TestStudent"

Write-Host "`n[6/7] Warming up..." -ForegroundColor Green
Start-Sleep -Seconds 30

Write-Host "[7/7] Calling the function as proof..." -ForegroundColor Green
Write-Host "      GET $fnUrl?name=$testName" -ForegroundColor DarkGray

$response = $null
for ($i = 1; $i -le 6; $i++) {
    try {
        $response = Invoke-RestMethod -Uri "$fnUrl`?name=$testName" -Method Get -TimeoutSec 30
        break
    } catch {
        Write-Host "      attempt $i failed, retrying in 15s..." -ForegroundColor Yellow
        Start-Sleep -Seconds 15
    }
}

Write-Host "`n----------  PROOF 1: HTTP RESPONSE  ----------" -ForegroundColor Magenta
if ($response) { $response } else { Write-Host "No response (check portal logs)." -ForegroundColor Red }

Write-Host "`n----------  PROOF 2: BLOB CREATED  ----------" -ForegroundColor Magenta
az storage blob list --container-name $container --connection-string $conn `
    --query "[].{Name:name, Size:properties.contentLength, Modified:properties.lastModified}" `
    --output table

Write-Host "`n----------  PROOF 3: BLOB CONTENTS  ----------" -ForegroundColor Magenta
$tmp = Join-Path $env:TEMP "$testName.txt"
az storage blob download --container-name $container --name "$testName.txt" `
    --connection-string $conn --file $tmp --output none
Get-Content $tmp

# -----------------------------------------------------------
# 8. Wire the live URL into the frontend
# -----------------------------------------------------------
$frontend = "$Project\frontend\index.html"
if (Test-Path $frontend) {
    (Get-Content $frontend) `
        -replace "https://YOURFUNCTION\.azurewebsites\.net", "https://$funcApp.azurewebsites.net" `
        | Set-Content $frontend
    Write-Host "`nUpdated frontend\index.html with the live Function URL." -ForegroundColor Cyan
}

Write-Host "`n===========================================================" -ForegroundColor Green
Write-Host " DONE"
Write-Host "===========================================================" -ForegroundColor Green
Write-Host " Endpoint : $fnUrl?name=YourName"
Write-Host " Frontend : open $Project\frontend\index.html"
Write-Host ""
Write-Host " Tear down (stops billing):"
Write-Host "   az group delete --name $rg --yes --no-wait"
Write-Host "==========================================================="





#az functionapp cors add --name func-student-re3fcm --resource-group rg-studentfunc-demo --allowed-origins "*"
#https://func-student-re3fcm.azurewebsites.net/api/CreateStudent?name=test
#Start-Process "D:\StudentFunctionDemo\frontend\index.html"


