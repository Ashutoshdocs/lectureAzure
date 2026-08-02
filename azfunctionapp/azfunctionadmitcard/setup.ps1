# ===========================================================
#  run-all-hosted.ps1
#  Builds the project, provisions Azure, deploys the function,
#  AND hosts the frontend on the same storage account via the
#  static-website feature.
#
#  The HTTP function now takes  name / department / rollno / year
#  and renders a PANAMAACADEMY *admit card PNG* with Pillow, saves
#  it to Blob Storage, and returns it (base64) so the page can show
#  and download it. Proves everything works at the end.
#
#  Run it:   cd D:\ ;  .\run-all-hosted.ps1
#
#  Prerequisites:
#    - Azure CLI            : az --version   (2.88.0 confirmed OK)
#    - Functions Core Tools : func --version (v4.x)
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
Write-Host "`n[1/9] Creating project files..." -ForegroundColor Green
 
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
<title>PANAMAACADEMY &middot; Admit Card</title>
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
    max-width:460px;
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
    margin-top:14px;
  }
  label:first-of-type{margin-top:0;}
 
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
  input, select{
    border:0;
    outline:0;
    background:transparent;
    padding:13px 0;
    font-size:15px;
    font-family:inherit;
    color:var(--ink);
    width:100%;
    appearance:none;
  }
  input::placeholder{color:#a2a7be;}
  select:invalid{color:#a2a7be;}
 
  .row2{display:grid;grid-template-columns:1fr 1fr;gap:14px;}

  .photo-field{
    display:flex;align-items:center;gap:12px;
    border:1.5px dashed var(--line);
    border-radius:12px;
    padding:12px 14px;
    background:#fbfcff;
  }
  .photo-field label.pick{
    margin:0;cursor:pointer;
    font-family:"Space Grotesk",sans-serif;font-weight:600;font-size:13px;
    color:var(--indigo);
    border:1.5px solid var(--indigo);border-radius:9px;
    padding:8px 12px;white-space:nowrap;
    transition:background .15s,color .15s;
  }
  .photo-field label.pick:hover{background:var(--indigo);color:#fff;}
  .photo-field .hint{font-size:12px;color:var(--muted);}
  .photo-field input[type=file]{display:none;}
  .thumb{
    width:52px;height:52px;flex:none;
    border-radius:9px;object-fit:cover;
    border:1px solid var(--line);
    display:none;
  }
 
  button{
    width:100%;
    margin-top:20px;
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
    font-weight:600;font-size:15px;margin-bottom:12px;
  }
  .result.ok .head{color:var(--ok);}
  .result.err .head{color:var(--err);}
 
  .card-img{
    width:100%;
    border-radius:10px;
    border:1px solid #bde9d2;
    display:block;
    margin-bottom:12px;
    box-shadow:0 8px 20px -12px rgba(16,20,60,.4);
  }
 
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
 
  .dl{
    display:inline-flex;align-items:center;gap:8px;
    margin-top:14px;
    text-decoration:none;
    font-family:"Space Grotesk",sans-serif;
    font-weight:600;font-size:13px;
    color:var(--indigo);
    border:1.5px solid var(--indigo);
    border-radius:10px;
    padding:9px 14px;
    transition:background .15s,color .15s;
  }
  .dl:hover{background:var(--indigo);color:#fff;}
 
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
    <div class="eyebrow"><span class="dot"></span>PANAMAACADEMY &middot; Examinations</div>
    <h1>Generate admit card</h1>
    <p class="sub">Fill in the student details. An HTTP-triggered Azure Function renders a printable admit&nbsp;card PNG, stores it in Blob&nbsp;Storage, and returns it below.</p>
 
    <label for="name">Student name</label>
    <div class="field">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
      <input id="name" placeholder="e.g. Aditya Sharma" autocomplete="off" autofocus>
    </div>
 
    <label for="department">Department</label>
    <div class="field">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"/><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"/></svg>
      <input id="department" placeholder="e.g. Computer Science" autocomplete="off">
    </div>
 
    <div class="row2">
      <div>
        <label for="rollno">Roll number</label>
        <div class="field">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="4" y1="9" x2="20" y2="9"/><line x1="4" y1="15" x2="20" y2="15"/><line x1="10" y1="3" x2="8" y2="21"/><line x1="16" y1="3" x2="14" y2="21"/></svg>
          <input id="rollno" placeholder="e.g. PA-2025-014" autocomplete="off">
        </div>
      </div>
      <div>
        <label for="year">Year</label>
        <div class="field">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
          <select id="year" required>
            <option value="" disabled selected>Select</option>
            <option>First Year</option>
            <option>Second Year</option>
            <option>Third Year</option>
            <option>Fourth Year</option>
          </select>
        </div>
      </div>
    </div>
 
    <label for="photo">Photo <span style="color:var(--muted);font-weight:400;">(optional)</span></label>
    <div class="photo-field">
      <img id="photoPreview" class="thumb" alt="">
      <label class="pick" for="photo">Choose photo</label>
      <input id="photo" type="file" accept="image/*">
      <span class="hint" id="photoHint">JPG or PNG &middot; a passport-style photo works best</span>
    </div>

    <button id="submit" onclick="generateCard()">
      <span id="btnlabel">Generate admit card</span>
    </button>
 
    <div class="flow" id="flow">
      <div class="stage" data-stage="0">
        <div class="node"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="5" y1="12" x2="19" y2="12"/><polyline points="12 5 19 12 12 19"/></svg></div>
        <div class="cap">Request</div>
      </div>
      <div class="stage" data-stage="1">
        <div class="node"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg></div>
        <div class="cap">Render</div>
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
  const val = (id) => $(id).value.trim();
  const stages = [...document.querySelectorAll(".stage")];
 
  $("endpoint").textContent = API;
  ["name","department","rollno"].forEach(id =>
    $(id).addEventListener("keydown", (e) => { if (e.key === "Enter") generateCard(); }));
 
  // hold the chosen photo as a base64 data URL (empty = no photo)
  let photoData = "";
  $("photo").addEventListener("change", (e) => {
    const f = e.target.files[0];
    const pv = $("photoPreview");
    if (!f){ photoData = ""; pv.style.display = "none"; $("photoHint").textContent = "JPG or PNG \u00b7 a passport-style photo works best"; return; }
    const reader = new FileReader();
    reader.onload = () => {
      photoData = reader.result;          // "data:image/...;base64,...."
      pv.src = photoData; pv.style.display = "block";
      $("photoHint").textContent = f.name;
    };
    reader.readAsDataURL(f);
  });
 
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
  function showError(title, msg){
    showResult("err",
      `<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg> ${title}`,
      `<div class="msg">${msg}</div>`);
  }
 
  function loading(on){
    const btn = $("submit");
    btn.disabled = on;
    $("btnlabel").textContent = on ? "Generating\u2026" : "Generate admit card";
    let sp = btn.querySelector(".spinner");
    if (on && !sp){ sp = document.createElement("span"); sp.className = "spinner"; btn.prepend(sp); }
    if (!on && sp) sp.remove();
  }
 
  function showCard(d){
    const img = d.imageBase64; // already a data: URL
    showResult("ok",
      `<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg> Admit card ready`,
      `<img class="card-img" src="${img}" alt="Admit card for ${escapeHtml(d.name)}">
       <dl class="rec">
         <dt>Name</dt><dd>${escapeHtml(d.name)}</dd>
         <dt>Roll No</dt><dd>${escapeHtml(d.rollNo)}</dd>
         <dt>Record ID</dt><dd>${escapeHtml(d.recordId)}</dd>
         <dt>Blob</dt><dd>${escapeHtml(d.blobName)}</dd>
       </dl>
       <a class="dl" href="${img}" download="${escapeHtml(d.blobName)}">
         <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
         Download PNG
       </a>`);
  }
 
  async function generateCard(){
    const name = val("name"), dept = val("department"), roll = val("rollno"), year = val("year");
    const missing = [];
    if (!name) missing.push("name");
    if (!dept) missing.push("department");
    if (!roll) missing.push("roll number");
    if (!year) missing.push("year");
    if (missing.length){
      showError("Missing fields", "Please fill in: " + missing.join(", ") + ".");
      resetFlow();
      return;
    }
 
    loading(true);
    setStage(0, "active");
 
    try {
      setTimeout(() => setStage(1, "active"), 250);
 
      // POST as JSON so the (potentially large) photo can be included
      const res = await fetch(API, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, department: dept, rollno: roll, year, photo: photoData })
      });
      const text = (await res.text()).trim();
 
      if (!res.ok) throw new Error(text || ("Request failed (" + res.status + ")"));
 
      const data = JSON.parse(text);
      setStage(2, "done");
      showCard(data);
    } catch (err) {
      resetFlow();
      showError("Couldn't generate",
        escapeHtml(err.message) + "<br>Check that the function URL is correct and the app is running.");
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
Pillow
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
from azure.storage.blob import BlobServiceClient, ContentSettings
from datetime import datetime, timezone
from PIL import Image, ImageDraw, ImageFont
import os
import io
import re
import json
import base64
import uuid

connection = os.environ["STORAGE_CONNECTION_STRING"]
blob_service = BlobServiceClient.from_connection_string(connection)
container = "uploads"

COLLEGE = "PANAMAACADEMY"

# palette (matches the frontend)
INDIGO = (79, 70, 229)
DEEP   = (55, 48, 163)
INK    = (14, 19, 48)
MUTED  = (91, 96, 121)
LINE   = (224, 227, 238)
CYAN   = (6, 182, 212)
HEADER_SUB = (219, 222, 252)


def load_font(size, bold=False):
    """Prefer a real TrueType font; fall back to Pillow's scalable default."""
    paths = (
        ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
         "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"]
        if bold else
        ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
         "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"]
    )
    for p in paths:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            pass
    try:
        return ImageFont.load_default(size=size)   # Pillow >= 10.1 (scalable)
    except TypeError:
        return ImageFont.load_default()


def center(draw, cx, y, text, font, fill):
    w = draw.textlength(text, font=font)
    draw.text((cx - w / 2, y), text, font=font, fill=fill)


def fit_cover(im, w, h):
    """Scale + centre-crop an image to exactly fill a w x h box."""
    sw, sh = im.size
    scale = max(w / sw, h / sh)
    nw, nh = max(1, int(sw * scale + 0.5)), max(1, int(sh * scale + 0.5))
    im = im.resize((nw, nh), Image.LANCZOS)
    left, top = (nw - w) // 2, (nh - h) // 2
    return im.crop((left, top, left + w, top + h))


def decode_photo(data_url):
    """Turn a 'data:image/...;base64,...' string into a PIL image (or None)."""
    if not data_url:
        return None
    try:
        b64 = data_url.split(",", 1)[-1]
        raw = base64.b64decode(b64)
        return Image.open(io.BytesIO(raw)).convert("RGB")
    except Exception:
        return None


def fit_font(draw, text, max_w, start, min_size=16, bold=True):
    """Shrink the font until the text fits within max_w pixels."""
    size = start
    while size > min_size:
        f = load_font(size, bold=bold)
        if draw.textlength(text, font=f) <= max_w:
            return f
        size -= 2
    return load_font(min_size, bold=bold)


def make_card(name, dept, roll, year, record_id, created, photo=None):
    W, H = 1000, 640
    img = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(img)

    # outer frame
    d.rectangle([10, 10, W - 10, H - 10], outline=INDIGO, width=4)

    # header band
    d.rectangle([14, 14, W - 14, 150], fill=INDIGO)
    center(d, W / 2, 38, COLLEGE, load_font(52, bold=True), "white")
    center(d, W / 2, 105, "ADMIT CARD  \u2022  EXAMINATIONS", load_font(20), HEADER_SUB)

    # cyan accent line under header
    d.rectangle([14, 150, W - 14, 156], fill=CYAN)

    # photo box (right)
    px0, py0, px1, py1 = 760, 195, 946, 405
    if photo is not None:
        img.paste(fit_cover(photo, px1 - px0, py1 - py0), (px0, py0))
    else:
        center(d, (px0 + px1) / 2, (py0 + py1) / 2 - 10, "PHOTO", load_font(18), MUTED)
    d.rectangle([px0, py0, px1, py1], outline=MUTED, width=2)   # frame on top

    # signatory line under photo
    d.line([px0, 470, px1, 470], fill=INK, width=2)
    center(d, (px0 + px1) / 2, 478, "Controller of Exams", load_font(14), MUTED)

    # details (left column)
    label_f = load_font(18)
    rows = [
        ("STUDENT NAME", name),
        ("DEPARTMENT", dept),
        ("ROLL NUMBER", roll),
        ("YEAR", year),
    ]
    x, y = 60, 200
    for lab, value in rows:
        d.text((x, y), lab, font=label_f, fill=MUTED)
        vf = fit_font(d, value or "\u2014", 660, 28)
        d.text((x, y + 26), value or "\u2014", font=vf, fill=INK)
        y += 92

    # footer meta
    fy = H - 96
    d.line([60, fy - 14, W - 300, fy - 14], fill=LINE, width=2)
    meta_f = load_font(16)
    d.text((60, fy), "Record ID  : " + record_id, font=meta_f, fill=MUTED)
    d.text((60, fy + 26), "Issued (UTC) : " + created, font=meta_f, fill=MUTED)

    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def get_field(req, key):
    v = req.params.get(key)
    if not v:
        try:
            v = (req.get_json() or {}).get(key)
        except ValueError:
            v = None
    return (v or "").strip()


def main(req: func.HttpRequest) -> func.HttpResponse:
    name = get_field(req, "name")
    dept = get_field(req, "department")
    roll = get_field(req, "rollno")
    year = get_field(req, "year")
    photo = decode_photo(get_field(req, "photo"))

    missing = [k for k, v in
               (("name", name), ("department", dept), ("rollno", roll), ("year", year))
               if not v]
    if missing:
        return func.HttpResponse(
            "Missing required field(s): " + ", ".join(missing),
            status_code=400)

    record_id = "STU-" + uuid.uuid4().hex[:8].upper()
    created = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

    png = make_card(name, dept, roll, year, record_id, created, photo)

    safe = re.sub(r"[^A-Za-z0-9_-]+", "_", roll) or record_id
    blob_name = safe + ".png"

    blob = blob_service.get_blob_client(container=container, blob=blob_name)
    blob.upload_blob(
        png, overwrite=True,
        content_settings=ContentSettings(content_type="image/png"))

    payload = {
        "name": name,
        "department": dept,
        "rollNo": roll,
        "year": year,
        "recordId": record_id,
        "blobName": blob_name,
        "container": container,
        "created": created + " UTC",
        "imageBase64": "data:image/png;base64," + base64.b64encode(png).decode(),
    }
    return func.HttpResponse(
        json.dumps(payload), status_code=200, mimetype="application/json")
'@ | Set-Content "$Project\StudentFunction\CreateStudent\__init__.py"
 
# -----------------------------------------------------------
# 3. Resource group
# -----------------------------------------------------------
Write-Host "[2/9] Creating resource group..." -ForegroundColor Green
az group create --name $rg --location $location --output none
 
# -----------------------------------------------------------
# 4. Storage account (+ uploads container)
#    shared-key access ON: the function uses a connection string
# -----------------------------------------------------------
Write-Host "[3/9] Creating storage account..." -ForegroundColor Green
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
# 4b. Enable static website hosting on the SAME storage account.
#     This auto-creates the special '$web' container. It works
#     even with --allow-blob-public-access false, because the
#     static web endpoint has its own anonymous access path.
# -----------------------------------------------------------
Write-Host "[4/9] Enabling static website hosting..." -ForegroundColor Green
az storage blob service-properties update `
    --account-name $storage `
    --static-website `
    --index-document index.html `
    --connection-string $conn `
    --output none
 
$webUrl = az storage account show `
    --name $storage --resource-group $rg `
    --query "primaryEndpoints.web" -o tsv
Write-Host "      Static site endpoint: $webUrl" -ForegroundColor DarkGray
 
# -----------------------------------------------------------
# 5. Function app (Linux, Python 3.11, Functions v4, Consumption)
# -----------------------------------------------------------
Write-Host "[5/9] Creating function app (takes a minute)..." -ForegroundColor Green
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
# 5b. CORS: allow the static-site origin to call the function.
#     Once index.html is served from $webUrl, the browser origin
#     becomes that domain and the function rejects fetch() without
#     this. (Use "*" instead for a quick demo, but you can't mix
#     "*" with specific origins.)
# -----------------------------------------------------------
Write-Host "      Adding CORS rule for the static site..." -ForegroundColor Green
$webOrigin = $webUrl.TrimEnd('/')
az functionapp cors add `
    --name $funcApp --resource-group $rg `
    --allowed-origins $webOrigin --output none
 
# -----------------------------------------------------------
# 6. Deploy (remote build installs pip packages, incl. Pillow, on Linux)
# -----------------------------------------------------------
Write-Host "[6/9] Deploying code..." -ForegroundColor Green
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
$fnUrl  = "https://$funcApp.azurewebsites.net/api/CreateStudent"
$testQS = "name=Test%20Student&department=Computer%20Science&rollno=PA-2025-001&year=Second%20Year"
 
Write-Host "`n[7/9] Warming up..." -ForegroundColor Green
Start-Sleep -Seconds 30
 
Write-Host "[8/9] Calling the function as proof..." -ForegroundColor Green
Write-Host "      GET $fnUrl?$testQS" -ForegroundColor DarkGray
 
$response = $null
for ($i = 1; $i -le 6; $i++) {
    try {
        $response = Invoke-RestMethod -Uri "$fnUrl`?$testQS" -Method Get -TimeoutSec 40
        break
    } catch {
        Write-Host "      attempt $i failed, retrying in 15s..." -ForegroundColor Yellow
        Start-Sleep -Seconds 15
    }
}
 
Write-Host "`n----------  PROOF 1: JSON RESPONSE (metadata)  ----------" -ForegroundColor Magenta
if ($response) {
    $response | Select-Object name, department, rollNo, year, recordId, blobName, created | Format-List
    # decode the returned PNG and save it locally
    $b64      = $response.imageBase64 -replace '^data:image/png;base64,', ''
    $bytes    = [Convert]::FromBase64String($b64)
    $savedPng = Join-Path $env:TEMP $response.blobName
    [IO.File]::WriteAllBytes($savedPng, $bytes)
    Write-Host "      Admit card PNG returned in response: $($bytes.Length) bytes" -ForegroundColor DarkGray
    Write-Host "      Saved to: $savedPng" -ForegroundColor DarkGray
} else {
    Write-Host "No response (check portal logs)." -ForegroundColor Red
}
 
Write-Host "`n----------  PROOF 2: BLOB CREATED  ----------" -ForegroundColor Magenta
az storage blob list --container-name $container --connection-string $conn `
    --query "[].{Name:name, Size:properties.contentLength, Modified:properties.lastModified}" `
    --output table
 
Write-Host "`n----------  PROOF 3: BLOB DOWNLOADED  ----------" -ForegroundColor Magenta
if ($response) {
    $tmp = Join-Path $env:TEMP ("dl_" + $response.blobName)
    az storage blob download --container-name $container --name $response.blobName `
        --connection-string $conn --file $tmp --output none
    $len = (Get-Item $tmp).Length
    Write-Host "      Downloaded $($response.blobName) from Blob Storage: $len bytes" -ForegroundColor DarkGray
    Write-Host "      Opening the admit card..." -ForegroundColor DarkGray
    Start-Process $tmp
}
 
# -----------------------------------------------------------
# 8. Wire the live URL into the frontend, THEN upload to $web
#    (upload the corrected file, not the YOURFUNCTION placeholder)
# -----------------------------------------------------------
$frontend = "$Project\frontend\index.html"
if (Test-Path $frontend) {
    (Get-Content $frontend) `
        -replace "https://YOURFUNCTION\.azurewebsites\.net", "https://$funcApp.azurewebsites.net" `
        | Set-Content $frontend
    Write-Host "`nUpdated frontend\index.html with the live Function URL." -ForegroundColor Cyan
}
 
Write-Host "[9/9] Uploading frontend to the `$web container..." -ForegroundColor Green
# NOTE: single quotes around '$web' stop PowerShell expanding it as a variable,
# and --content-type text/html makes the browser render (not download) the page.
az storage blob upload `
    --account-name $storage `
    --container-name '$web' `
    --name index.html `
    --file $frontend `
    --content-type "text/html" `
    --connection-string $conn `
    --overwrite `
    --output none
 
# -----------------------------------------------------------
# 9. Done
# -----------------------------------------------------------
Write-Host "`n===========================================================" -ForegroundColor Green
Write-Host " DONE"
Write-Host "===========================================================" -ForegroundColor Green
Write-Host " Function : $fnUrl?name=Aditya&department=CSE&rollno=PA-2025-014&year=Second%20Year"
Write-Host " Live site: $webUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host " Tear down (stops billing):"
Write-Host "   az group delete --name $rg --yes --no-wait"
Write-Host "==========================================================="
 
#Start-Process $webUrl
