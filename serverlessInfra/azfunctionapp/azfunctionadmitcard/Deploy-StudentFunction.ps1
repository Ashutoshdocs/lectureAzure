# Deploy-StudentFunction.ps1
# Creates the Azure Functions Python v1 project, packages it as ZIP,
# configures the app setting, and deploys the ZIP to an EXISTING Function App.
#
# Example:
# .\Deploy-StudentFunction.ps1 `
#   -ResourceGroup "rg-studentfunc-demo" `
#   -FunctionAppName "func-student-abc123" `
#   -StorageConnectionString "DefaultEndpointsProtocol=..."
#
# Prerequisites on Windows PowerShell 5.1+ or PowerShell 7:
#   - Azure CLI installed
#   - Signed in with: az login
#   - An existing Linux Azure Function App configured for Python + Functions v4
#   - An existing Storage account and private container named "uploads"

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$FunctionAppName,

    [Parameter(Mandatory = $true)]
    [string]$StorageConnectionString,

    [string]$ProjectDirectory = (Join-Path $PWD "StudentFunction"),
    [string]$ZipPath = (Join-Path $PWD "StudentFunction-deploy.zip")
)

$ErrorActionPreference = "Stop"

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found. Install it and retry."
    }
}

Require-Command "az"

Write-Host "`n[1/6] Checking Azure login..." -ForegroundColor Cyan
$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    az login
    $account = az account show --output json | ConvertFrom-Json
}
Write-Host "Subscription: $($account.name) ($($account.id))"

Write-Host "`n[2/6] Creating project directory structure..." -ForegroundColor Cyan
$functionDirectory = Join-Path $ProjectDirectory "CreateStudent"
New-Item -ItemType Directory -Path $functionDirectory -Force | Out-Null

$hostJson = @'
{
  "version": "2.0"
}
'@
Set-Content -Path (Join-Path $ProjectDirectory "host.json") -Value $hostJson -Encoding utf8

$requirements = @'
azure-functions
azure-storage-blob
Pillow
'@
Set-Content -Path (Join-Path $ProjectDirectory "requirements.txt") -Value $requirements -Encoding utf8

$functionJson = @'
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
'@
Set-Content -Path (Join-Path $functionDirectory "function.json") -Value $functionJson -Encoding utf8

$pythonCode = @'
import base64
import io
import json
import os
import re
import uuid
from datetime import datetime, timezone

import azure.functions as func
from azure.storage.blob import BlobServiceClient, ContentSettings
from PIL import Image, ImageDraw, ImageFont

COLLEGE = "PANAMAACADEMY"
CONTAINER = "uploads"
INDIGO = (79, 70, 229)
DEEP = (55, 48, 163)
INK = (14, 19, 48)
MUTED = (91, 96, 121)
LINE = (224, 227, 238)
CYAN = (6, 182, 212)
HEADER_SUB = (219, 222, 252)


def load_font(size, bold=False):
    paths = (
        ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
         "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"]
        if bold else
        ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
         "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"]
    )
    for path in paths:
        try:
            return ImageFont.truetype(path, size)
        except Exception:
            pass
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def center(draw, cx, y, text, font, fill):
    width = draw.textlength(text, font=font)
    draw.text((cx - width / 2, y), text, font=font, fill=fill)


def fit_cover(image, width, height):
    sw, sh = image.size
    scale = max(width / sw, height / sh)
    nw, nh = max(1, int(sw * scale + 0.5)), max(1, int(sh * scale + 0.5))
    image = image.resize((nw, nh), Image.Resampling.LANCZOS)
    left, top = (nw - width) // 2, (nh - height) // 2
    return image.crop((left, top, left + width, top + height))


def decode_photo(data_url):
    if not data_url:
        return None
    try:
        raw = base64.b64decode(data_url.split(",", 1)[-1])
        return Image.open(io.BytesIO(raw)).convert("RGB")
    except Exception:
        return None


def fit_font(draw, text, max_width, start=28, min_size=16, bold=True):
    size = start
    while size > min_size:
        font = load_font(size, bold=bold)
        if draw.textlength(text, font=font) <= max_width:
            return font
        size -= 2
    return load_font(min_size, bold=bold)


def make_card(name, department, roll, year, record_id, created, photo=None):
    width, height = 1000, 640
    image = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(image)
    draw.rectangle([10, 10, width - 10, height - 10], outline=INDIGO, width=4)
    draw.rectangle([14, 14, width - 14, 150], fill=INDIGO)
    center(draw, width / 2, 38, COLLEGE, load_font(52, True), "white")
    center(draw, width / 2, 105, "ADMIT CARD  •  EXAMINATIONS", load_font(20), HEADER_SUB)
    draw.rectangle([14, 150, width - 14, 156], fill=CYAN)

    px0, py0, px1, py1 = 760, 195, 946, 405
    if photo is not None:
        image.paste(fit_cover(photo, px1 - px0, py1 - py0), (px0, py0))
    else:
        center(draw, (px0 + px1) / 2, (py0 + py1) / 2 - 10, "PHOTO", load_font(18), MUTED)
    draw.rectangle([px0, py0, px1, py1], outline=MUTED, width=2)
    draw.line([px0, 470, px1, 470], fill=INK, width=2)
    center(draw, (px0 + px1) / 2, 478, "Controller of Exams", load_font(14), MUTED)

    rows = [
        ("STUDENT NAME", name),
        ("DEPARTMENT", department),
        ("ROLL NUMBER", roll),
        ("YEAR", year),
    ]
    x, y = 60, 200
    for label, value in rows:
        draw.text((x, y), label, font=load_font(18), fill=MUTED)
        font = fit_font(draw, value or "—", 660)
        draw.text((x, y + 26), value or "—", font=font, fill=INK)
        y += 92

    footer_y = height - 96
    draw.line([60, footer_y - 14, width - 300, footer_y - 14], fill=LINE, width=2)
    draw.text((60, footer_y), "Record ID : " + record_id, font=load_font(16), fill=MUTED)
    draw.text((60, footer_y + 26), "Issued (UTC) : " + created, font=load_font(16), fill=MUTED)

    output = io.BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def get_field(req, key):
    value = req.params.get(key)
    if not value:
        try:
            value = (req.get_json() or {}).get(key)
        except ValueError:
            value = None
    if value is None:
        return ""
    return str(value).strip()


def main(req: func.HttpRequest) -> func.HttpResponse:
    try:
        name = get_field(req, "name")
        department = get_field(req, "department")
        roll = get_field(req, "rollno")
        year = get_field(req, "year")
        photo = decode_photo(get_field(req, "photo"))

        missing = [key for key, value in (
            ("name", name), ("department", department),
            ("rollno", roll), ("year", year)
        ) if not value]
        if missing:
            return func.HttpResponse(
                "Missing required field(s): " + ", ".join(missing),
                status_code=400
            )

        connection = os.environ.get("STORAGE_CONNECTION_STRING")
        if not connection:
            raise RuntimeError("STORAGE_CONNECTION_STRING app setting is missing")

        record_id = "STU-" + uuid.uuid4().hex[:8].upper()
        created = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        png = make_card(name, department, roll, year, record_id, created, photo)
        safe_roll = re.sub(r"[^A-Za-z0-9_-]+", "_", roll) or record_id
        blob_name = safe_roll + ".png"

        service = BlobServiceClient.from_connection_string(connection)
        blob = service.get_blob_client(container=CONTAINER, blob=blob_name)
        blob.upload_blob(
            png,
            overwrite=True,
            content_settings=ContentSettings(content_type="image/png")
        )

        payload = {
            "name": name,
            "department": department,
            "rollNo": roll,
            "year": year,
            "recordId": record_id,
            "blobName": blob_name,
            "container": CONTAINER,
            "created": created + " UTC",
            "imageBase64": "data:image/png;base64," + base64.b64encode(png).decode("ascii")
        }
        return func.HttpResponse(
            json.dumps(payload),
            status_code=200,
            mimetype="application/json"
        )
    except Exception as exc:
        # Detailed diagnostics belong in Function logs; avoid returning secrets.
        return func.HttpResponse(
            json.dumps({"error": "Admit card generation failed", "detail": str(exc)}),
            status_code=500,
            mimetype="application/json"
        )
'@
Set-Content -Path (Join-Path $functionDirectory "__init__.py") -Value $pythonCode -Encoding utf8

Write-Host "Created project files:" -ForegroundColor Green
Get-ChildItem $ProjectDirectory -Recurse | Select-Object FullName

Write-Host "`n[3/6] Configuring Function App settings..." -ForegroundColor Cyan
az functionapp config appsettings set `
    --resource-group $ResourceGroup `
    --name $FunctionAppName `
    --settings "STORAGE_CONNECTION_STRING=$StorageConnectionString" "FUNCTIONS_WORKER_RUNTIME=python" `
    --output none
if ($LASTEXITCODE -ne 0) { throw "Failed to set Function App app settings." }

Write-Host "`n[4/6] Creating ZIP package..." -ForegroundColor Cyan
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
$zipParent = Split-Path -Parent $ZipPath
if ($zipParent -and -not (Test-Path $zipParent)) {
    New-Item -ItemType Directory -Path $zipParent -Force | Out-Null
}

# ZIP must contain host.json at its root, not a top-level StudentFunction folder.
Compress-Archive -Path (Join-Path $ProjectDirectory "*") -DestinationPath $ZipPath -Force
Write-Host "ZIP created: $ZipPath"

Write-Host "`n[5/6] Deploying ZIP to Function App..." -ForegroundColor Cyan
az functionapp deployment source config-zip `
    --resource-group $ResourceGroup `
    --name $FunctionAppName `
    --src $ZipPath `
    --build-remote true
if ($LASTEXITCODE -ne 0) {
    throw "ZIP deployment failed. Check Function App deployment logs and runtime settings."
}

Write-Host "`n[6/6] Checking Function App and endpoint..." -ForegroundColor Cyan
$defaultHost = az functionapp show `
    --resource-group $ResourceGroup `
    --name $FunctionAppName `
    --query defaultHostName `
    --output tsv
if ($LASTEXITCODE -ne 0) { throw "Could not read Function App hostname." }

Write-Host ""
Write-Host "Deployment command completed." -ForegroundColor Green
Write-Host "Function endpoint: https://$defaultHost/api/CreateStudent" -ForegroundColor Cyan
Write-Host "Function authorization is Anonymous as configured in function.json." -ForegroundColor Yellow
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "1. Ensure the Storage account has a private container named 'uploads'."
Write-Host "2. Add the static website origin to Function App CORS."
Write-Host "3. Update frontend/index.html to use the endpoint shown above."
Write-Host "4. Upload the updated index.html to the Storage account's '$web' container."
Write-Host ""
Write-Host "Security note: this demo uses an anonymous HTTP trigger and a Storage connection string."
Write-Host "Do not use it as-is for production or real student records."
