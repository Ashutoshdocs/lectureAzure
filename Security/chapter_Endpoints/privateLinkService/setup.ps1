<#
.SYNOPSIS
    Azure Private Link Service lab - PowerShell + Azure CLI.

.DESCRIPTION
    Creates:
      * Resource group
      * vnet-provider 10.10.0.0/16  -> vmproduction (nginx, NO public IP)
      * vnet-consumer 10.20.0.0/16  -> vmconsumer   (public IP for SSH)
      * Standard internal load balancer in front of vmproduction
      * Private Link Service on that load balancer
      * Private Endpoint in vnet-consumer that connects to the PLS
      * NAT gateway so vmproduction can reach the internet to install nginx

    The VNets are NOT peered. vmconsumer reaches the nginx page only through
    the Private Endpoint -> Private Link Service path.

    nginx serves two editions of the page from the same URL:
      * curl / wget  -> a colourised, terminal-friendly text page
      * browsers     -> a full HTML page
    Also available explicitly at /text, /html and /health.

.NOTES
    Requires: Azure CLI (az) logged in (az login). Works in Windows PowerShell
    5.1 and PowerShell 7+. Keep this file saved as UTF-8 with BOM.

    Both VMs use username + password login (no SSH keys). If -AdminPassword is
    not supplied, the script prompts for it securely.
    Password rules (Azure): 12-72 characters, and at least 3 of: lowercase,
    uppercase, digit, special character. Avoid double quotes (").

.EXAMPLE
    .\Deploy-PrivateLinkLab.ps1
    .\Deploy-PrivateLinkLab.ps1 -ResourceGroup rg-pls-lab -Location eastus
    .\Deploy-PrivateLinkLab.ps1 -AdminPassword (Read-Host -AsSecureString "Password")
#>
[CmdletBinding()]
param(
    [string]$ResourceGroup = "rg-pls-nginx-demo",
    [string]$Location      = "centralindia",
    [string]$VmSize        = "Standard_B1s",
    [string]$AdminUser     = "azureuser",
    [SecureString]$AdminPassword,
    [string]$Image         = "Canonical:ubuntu-24_04-lts:server:latest"
)

$ErrorActionPreference = "Stop"
$env:PYTHONUTF8 = "1"   # make Azure CLI (Python) use UTF-8 for file I/O on Windows

# ----------------------------------------------------------------------------
# Names and address spaces
# ----------------------------------------------------------------------------
$ProvVnet       = "vnet-provider";         $ProvCidr       = "10.10.0.0/16"
$ProvVmSubnet   = "snet-provider-vm";      $ProvVmPrefix   = "10.10.1.0/24"
$PlsSubnet      = "snet-pls-nat";          $PlsPrefix      = "10.10.2.0/24"

$ConsVnet       = "vnet-consumer";         $ConsCidr       = "10.20.0.0/16"
$ConsVmSubnet   = "snet-consumer-vm";      $ConsVmPrefix   = "10.20.1.0/24"
$PeSubnet       = "snet-private-endpoint"; $PePrefix       = "10.20.2.0/24"

$NatPip         = "pip-natgw-provider"
$NatGw          = "natgw-provider"

$LbName         = "ilb-production"
$LbFrontend     = "fe-production"
$LbFrontendIp   = "10.10.1.100"
$LbPool         = "bepool-production"
$LbProbe        = "probe-http"
$LbRule         = "rule-http-80"

$ProdVm         = "vmproduction"
$ProdNic        = "nic-vmproduction"
$ProdNsg        = "nsg-vmproduction"

$ConsVm         = "vmconsumer"
$ConsNsg        = "nsg-vmconsumer"
$ConsPip        = "pip-vmconsumer"

$PlsName        = "pls-nginx-production"
$PeName         = "pe-nginx-consumer"
$PeConnection   = "conn-to-pls-nginx"

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Assert-Az([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI command failed during: $Step" }
}

# ----------------------------------------------------------------------------
# VM password (prompt if not given, then validate against Azure's rules)
# ----------------------------------------------------------------------------
if (-not $AdminPassword) {
    $AdminPassword  = Read-Host -AsSecureString "Enter password for VM user '$AdminUser'"
    $confirmPwd     = Read-Host -AsSecureString "Confirm password"
    $p1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminPassword))
    $p2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmPwd))
    if ($p1 -cne $p2) { throw "Passwords do not match." }
    Remove-Variable p1, p2
}
$VmPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminPassword))

$classes = 0
if ($VmPassword -cmatch '[a-z]')        { $classes++ }
if ($VmPassword -cmatch '[A-Z]')        { $classes++ }
if ($VmPassword -match  '[0-9]')        { $classes++ }
if ($VmPassword -match  '[^a-zA-Z0-9]') { $classes++ }
if ($VmPassword.Length -lt 12 -or $VmPassword.Length -gt 72) { throw "Password must be 12-72 characters." }
if ($classes -lt 3) { throw "Password needs at least 3 of: lowercase, uppercase, digit, special character." }
if ($VmPassword.Contains('"')) { throw 'Password must not contain double quotes (").' }
if ($VmPassword -match [regex]::Escape($AdminUser)) { throw "Password must not contain the username." }

# ----------------------------------------------------------------------------
# Pre-flight
# ----------------------------------------------------------------------------
Write-Step "Checking Azure CLI and login"
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI (az) not found. Install it from https://aka.ms/installazurecli"
}
$sub = az account show --query "{name:name, id:id}" -o tsv --only-show-errors
if ($LASTEXITCODE -ne 0) { throw "Not logged in. Run 'az login' first." }
Write-Host "    Subscription: $sub"

# ----------------------------------------------------------------------------
# cloud-init for vmproduction: nginx + page (HTML for browsers, ANSI text for curl)
# ----------------------------------------------------------------------------
# ---- Page content (UTF-8). Base64-encoded into cloud-init below so the file
# ---- az reads is pure ASCII (Azure CLI on Windows reads it with the ANSI code page).
$htmlPage = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Azure Private Link Service &middot; Live Demo</title>
<style>
:root{--bg:#0b1220;--panel:#111a2e;--line:#1f2b45;--text:#e6ecf5;--muted:#93a3bd;--accent:#3b9cff;--accent2:#35d0a5;--warn:#ffb547}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:"Segoe UI",system-ui,-apple-system,Roboto,Helvetica,Arial,sans-serif;background:var(--bg);color:var(--text);line-height:1.6}
.wrap{max-width:1080px;margin:0 auto;padding:0 24px}
header{background:radial-gradient(1200px 420px at 15% -10%,rgba(59,156,255,.35),transparent),linear-gradient(180deg,#0d1730,#0b1220);border-bottom:1px solid var(--line);padding:76px 0 60px}
.badge{display:inline-flex;align-items:center;gap:8px;font-size:12px;letter-spacing:.12em;text-transform:uppercase;color:var(--accent2);border:1px solid rgba(53,208,165,.4);padding:5px 12px;border-radius:999px;margin-bottom:20px}
.dot{width:8px;height:8px;border-radius:50%;background:var(--accent2);box-shadow:0 0 10px var(--accent2)}
h1{font-size:clamp(34px,5vw,54px);line-height:1.08;font-weight:700;letter-spacing:-.02em}
h1 span{background:linear-gradient(90deg,var(--accent),var(--accent2));-webkit-background-clip:text;background-clip:text;color:transparent}
.lead{margin-top:18px;font-size:18px;color:var(--muted);max-width:720px}
section{padding:56px 0;border-bottom:1px solid var(--line)}
h2{font-size:13px;letter-spacing:.14em;text-transform:uppercase;color:var(--accent);margin-bottom:8px}
h3{font-size:26px;margin-bottom:16px;letter-spacing:-.01em}
p{color:var(--muted);max-width:780px}
.grid{display:grid;gap:18px;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));margin-top:26px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:22px}
.card b{display:block;color:var(--text);margin-bottom:6px;font-size:16px}
.card p{font-size:14px}
.flow{display:grid;grid-template-columns:1fr 150px 1fr;gap:18px;align-items:stretch;margin-top:28px}
.vnet{border:1px dashed #36507d;border-radius:16px;padding:18px 18px 8px;background:rgba(17,26,46,.6)}
.vnet h4{font-size:12px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);font-weight:600;margin-bottom:6px}
.node{background:var(--panel);border:1px solid var(--line);border-left:3px solid var(--accent);border-radius:10px;padding:10px 14px;margin:10px 0;font-size:15px}
.node small{display:block;color:var(--muted);font-family:Consolas,"Cascadia Mono",monospace;font-size:12.5px}
.node.green{border-left-color:var(--accent2)}
.node.amber{border-left-color:var(--warn)}
.down{text-align:center;color:#4e6a99;font-size:14px;line-height:1}
.bridge{display:flex;flex-direction:column;justify-content:center;align-items:center;color:var(--accent2);font-size:11px;text-transform:uppercase;letter-spacing:.12em;text-align:center}
.bridge .line{width:100%;height:2px;background:linear-gradient(90deg,var(--accent),var(--accent2));margin:10px 0}
.note{margin-top:14px;font-size:13px}
ul.checks{list-style:none;margin-top:22px;display:grid;gap:12px;grid-template-columns:repeat(auto-fit,minmax(320px,1fr))}
ul.checks li{padding-left:30px;position:relative;color:var(--text)}
ul.checks li:before{content:"\2713";position:absolute;left:0;top:0;color:var(--accent2);font-weight:700}
ol.steps{margin:22px 0 0 20px;color:var(--muted)}
ol.steps li{margin:8px 0;padding-left:6px}
ol.steps b{color:var(--text)}
.live{font-family:Consolas,"Cascadia Mono",monospace;background:#070c17;border:1px solid var(--line);border-radius:12px;padding:20px 22px;margin-top:22px;font-size:14px}
.live div{display:flex;flex-wrap:wrap;gap:4px 18px;padding:4px 0}
.live span{color:var(--muted);min-width:150px}
.live em{font-style:normal;color:var(--accent2)}
code{font-family:Consolas,"Cascadia Mono",monospace;background:#0a1122;border:1px solid var(--line);padding:2px 6px;border-radius:6px;font-size:13px;color:var(--text)}
footer{padding:30px 0;color:var(--muted);font-size:13px}
@media(max-width:780px){.flow{grid-template-columns:1fr}.bridge .line{width:2px;height:40px}}
</style>
</head>
<body>
<header><div class="wrap">
  <div class="badge"><span class="dot"></span>Live on <!--# echo var="hostname" --></div>
  <h1>Azure <span>Private Link Service</span></h1>
  <p class="lead">Publish your own application privately. Consumers in any VNet, subscription or tenant reach it through a private IP inside their own network &mdash; no peering, no public exposure, no overlapping-CIDR headaches.</p>
</div></header>

<section><div class="wrap">
  <h2>01 &middot; The concept</h2>
  <h3>What is Private Link Service?</h3>
  <p>Private Link Service (PLS) lets a service provider expose an application that runs behind an Azure <b>Standard Load Balancer</b>. Consumers connect by creating a <b>Private Endpoint</b> &mdash; a network interface with a private IP in their own VNet &mdash; that maps to your PLS. Traffic travels over the Microsoft backbone and is source-NATed by the PLS, so neither side ever needs to see, route to, or trust the other's address space.</p>
</div></section>

<section><div class="wrap">
  <h2>02 &middot; This lab</h2>
  <h3>How the request reaching you right now was delivered</h3>
  <div class="flow">
    <div class="vnet">
      <h4>Consumer VNet &middot; 10.20.0.0/16</h4>
      <div class="node">vmconsumer<small>10.20.1.0/24 &middot; runs curl</small></div>
      <div class="down">&#9660;</div>
      <div class="node green">Private Endpoint<small>10.20.2.0/24 &middot; private IP in consumer VNet</small></div>
    </div>
    <div class="bridge">Microsoft<div class="line"></div>backbone</div>
    <div class="vnet">
      <h4>Provider VNet &middot; 10.10.0.0/16</h4>
      <div class="node green">Private Link Service<small>NAT IPs from 10.10.2.0/24</small></div>
      <div class="down">&#9660;</div>
      <div class="node amber">Standard Internal Load Balancer<small>frontend 10.10.1.100 : 80</small></div>
      <div class="down">&#9660;</div>
      <div class="node">vmproduction &middot; nginx<small>10.10.1.0/24 &middot; no public IP</small></div>
    </div>
  </div>
  <p class="note">The two VNets are not peered and share no routes. The only path between them is the Private Endpoint &rarr; Private Link Service connection.</p>
</div></section>

<section><div class="wrap">
  <h2>03 &middot; Building blocks</h2>
  <h3>The components and their jobs</h3>
  <div class="grid">
    <div class="card"><b>Private Endpoint</b><p>A NIC in the consumer's subnet. Consumers talk to one private IP and never learn anything else about the provider network.</p></div>
    <div class="card"><b>Private Link Service</b><p>Attached to the load balancer frontend. SNATs incoming connections to NAT IPs from its own subnet.</p></div>
    <div class="card"><b>Standard Load Balancer</b><p>Internal LB that health-probes and distributes traffic to backend VMs. PLS requires the Standard SKU.</p></div>
    <div class="card"><b>Access control</b><p>Visibility lists restrict who can discover the service; auto-approval or manual approval governs every connection.</p></div>
  </div>
</div></section>

<section><div class="wrap">
  <h2>04 &middot; Why it matters</h2>
  <h3>What teams gain</h3>
  <ul class="checks">
    <li>No VNet peering, route tables or CIDR coordination</li>
    <li>Service never needs a public IP</li>
    <li>Traffic stays on the Microsoft backbone</li>
    <li>Consumers see one IP, never your whole network</li>
    <li>Works across subscriptions and Microsoft Entra ID tenants</li>
    <li>TCP Proxy Protocol v2 can pass the consumer's identity</li>
  </ul>
</div></section>

<section><div class="wrap">
  <h2>05 &middot; Packet walk</h2>
  <h3>One request, step by step</h3>
  <ol class="steps">
    <li><b>vmconsumer</b> sends <code>GET /</code> to the Private Endpoint IP in its own VNet.</li>
    <li>Azure carries the flow over the backbone to the <b>Private Link Service</b>.</li>
    <li>The PLS rewrites the source to one of its <b>NAT IPs</b> (10.10.2.x).</li>
    <li>The <b>internal load balancer</b> forwards it to a healthy backend.</li>
    <li><b>nginx on vmproduction</b> answers; the reply retraces the same path.</li>
  </ol>
</div></section>

<section><div class="wrap">
  <h2>06 &middot; Live</h2>
  <h3>This request, as seen by the server</h3>
  <div class="live">
    <div><span>Served by</span><em><!--# echo var="hostname" --></em></div>
    <div><span>Your source IP</span><em><!--# echo var="remote_addr" --></em></div>
    <div><span>Server time</span><em><!--# echo var="date_local" --></em></div>
  </div>
  <p class="note">Reached through the Private Endpoint, your source IP is a PLS NAT address from 10.10.2.0/24 &mdash; not the consumer's 10.20.x address.</p>
</div></section>

<footer><div class="wrap">Azure Private Link Service demo &middot; nginx on vmproduction &middot; terminal edition: <code>curl http://&lt;private-endpoint-ip&gt;/</code></div></footer>
</body>
</html>
'@

$textPage = @'
%E%[0m
%E%[1;36m  ══════════════════════════════════════════════════════════════════════════%E%[0m
%E%[1;37m     AZURE PRIVATE LINK SERVICE%E%[0m%E%[2m   ·   terminal edition, served by nginx%E%[0m
%E%[1;36m  ══════════════════════════════════════════════════════════════════════════%E%[0m
     Publish your own service privately. Consumers in other VNets reach it
     through a private IP in *their* network: no peering, no public IPs.

%E%[1;33m  ▌ 01  WHAT IS IT%E%[0m
%E%[2m  ──────────────────────────────────────────────────────────────────────────%E%[0m
  Azure Private Link Service (PLS) exposes an application that runs behind
  a Standard Load Balancer. A consumer creates a Private Endpoint that maps
  to your PLS: a NIC with a private IP inside the consumer's own VNet.
  Traffic crosses the Microsoft backbone and is SNAT'ed by the PLS, so
  neither side ever needs to see the other's address space.

%E%[1;33m  ▌ 02  HOW THIS LAB IS WIRED%E%[0m
%E%[2m  ──────────────────────────────────────────────────────────────────────────%E%[0m
%E%[1;37m  CONSUMER VNet 10.20.0.0/16              PROVIDER VNet 10.10.0.0/16%E%[0m%E%[36m
  ┌──────────────────────────┐            ┌──────────────────────────────┐
  │                          │            │                              │
  │  vmconsumer              │            │      vmproduction  nginx:80  │
  │  10.20.1.4               │            │      10.10.1.4               │
  │  │ curl http://10.20.2.4 │            │      ▲                       │
  │  ▼                       │            │      Internal LB 10.10.1.100 │
  │  Private Endpoint        │            │      ▲                       │
  │  10.20.2.4 ──────────────┼─ backbone ─┼────▶ Private Link Service    │
  │                          │            │      NAT IP 10.10.2.x        │
  │                          │            │                              │
  └──────────────────────────┘            └──────────────────────────────┘%E%[0m
%E%[2m    no VNet peering · no public IP on vmproduction · IPs illustrative%E%[0m

%E%[1;33m  ▌ 03  THE BUILDING BLOCKS%E%[0m
%E%[2m  ──────────────────────────────────────────────────────────────────────────%E%[0m
  %E%[1;36m◆ Private Endpoint    %E%[0m  NIC in the consumer VNet mapped to the PLS
  %E%[1;36m◆ Private Link Service%E%[0m  Bound to the LB frontend; SNATs to NAT IPs
  %E%[1;36m◆ Standard Internal LB%E%[0m  Health-probes and forwards to backends
  %E%[1;36m◆ Backend (nginx)     %E%[0m  vmproduction, the service being published
  %E%[1;36m◆ Access control      %E%[0m  Visibility list + auto / manual approval

%E%[1;33m  ▌ 04  WHY TEAMS USE IT%E%[0m
%E%[2m  ──────────────────────────────────────────────────────────────────────────%E%[0m
  %E%[1;32m✔%E%[0m No peering, no route tables, no overlapping-CIDR conflicts
  %E%[1;32m✔%E%[0m The service never needs a public IP address
  %E%[1;32m✔%E%[0m Traffic stays on the Microsoft backbone
  %E%[1;32m✔%E%[0m Consumers see one IP, never your whole network
  %E%[1;32m✔%E%[0m Works across subscriptions and Microsoft Entra ID tenants
  %E%[1;32m✔%E%[0m TCP Proxy Protocol v2 can pass the consumer's identity

%E%[1;33m  ▌ 05  THIS REQUEST, AS SEEN BY THE SERVER%E%[0m
%E%[2m  ──────────────────────────────────────────────────────────────────────────%E%[0m
  Served by        %E%[1;37m<!--# echo var="hostname" -->%E%[0m
  Your source IP   %E%[1;35m<!--# echo var="remote_addr" -->%E%[0m
  Server time      <!--# echo var="date_local" -->
%E%[2m    Your source IP is a PLS NAT address (10.10.2.x), not 10.20.x%E%[0m

%E%[1;33m  ▌ 06  TRY MORE%E%[0m
%E%[2m  ──────────────────────────────────────────────────────────────────────────%E%[0m
  curl http://<pe-ip>/          this terminal edition
  curl http://<pe-ip>/html      full HTML edition
  curl -I http://<pe-ip>/       response headers (X-Served-By)
  curl http://<pe-ip>/health    load balancer health probe

%E%[2m  ══════════════════════════════════════════════════════════════════════════
    Azure Private Link Service demo · provider 10.10/16 · consumer 10.20/16%E%[0m
'@
$textPage = $textPage.Replace('%E%', [string][char]27)   # ANSI escape for colours

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$htmlB64 = [Convert]::ToBase64String($utf8NoBom.GetBytes($htmlPage.Replace("`r`n", "`n")))
$textB64 = [Convert]::ToBase64String($utf8NoBom.GetBytes($textPage.Replace("`r`n", "`n")))

$cloudInit = @'
#cloud-config
package_update: true
packages:
  - nginx
  - curl

write_files:
  - path: /etc/nginx/conf.d/pls-demo.conf
    defer: true
    permissions: '0644'
    content: |
      # curl / wget / httpie get the terminal edition, browsers get HTML
      map $http_user_agent $pls_index {
          default                                   index.html;
          "~*(curl|wget|httpie|libwww|powershell)"  index.txt;
      }

      server {
          listen 80 default_server;
          listen [::]:80 default_server;
          server_name _;

          root /var/www/pls;
          charset utf-8;
          ssi on;
          ssi_types text/plain;

          add_header X-Served-By $hostname always;
          add_header X-Demo "Azure Private Link Service" always;
          add_header Vary "User-Agent" always;

          location = /       { try_files /$pls_index =404; }
          location = /html   { try_files /index.html =404; }
          location = /text   { try_files /index.txt  =404; }
          location = /health { access_log off; default_type text/plain; return 200 "healthy\n"; }
          location /         { return 404; }
      }

  - path: /var/www/pls/index.html
    defer: true
    permissions: '0644'
    encoding: b64
    content: __HTML_B64__

  - path: /var/www/pls/index.txt
    defer: true
    permissions: '0644'
    encoding: b64
    content: __TXT_B64__

runcmd:
  - rm -f /etc/nginx/sites-enabled/default
  - chown -R www-data:www-data /var/www/pls
  - nginx -t
  - systemctl enable nginx
  - systemctl restart nginx
'@
$cloudInit = $cloudInit.Replace('__HTML_B64__', $htmlB64).Replace('__TXT_B64__', $textB64)

# cloud-init needs LF line endings and no BOM
$cloudInitPath = Join-Path ([System.IO.Path]::GetTempPath()) "cloud-init-vmproduction.yaml"
[System.IO.File]::WriteAllText($cloudInitPath, $cloudInit.Replace("`r`n", "`n"), [System.Text.Encoding]::ASCII)

# ----------------------------------------------------------------------------
# 1. Resource group
# ----------------------------------------------------------------------------
Write-Step "1/10  Creating resource group $ResourceGroup in $Location"
az group create -n $ResourceGroup -l $Location -o none --only-show-errors
Assert-Az "resource group"

# ----------------------------------------------------------------------------
# 2. Provider VNet (10.10.0.0/16)
# ----------------------------------------------------------------------------
Write-Step "2/10  Creating provider VNet $ProvVnet ($ProvCidr)"
az network vnet create -g $ResourceGroup -n $ProvVnet -l $Location `
    --address-prefixes $ProvCidr `
    --subnet-name $ProvVmSubnet --subnet-prefixes $ProvVmPrefix `
    -o none --only-show-errors
Assert-Az "provider vnet"

# PLS NAT subnet: private link service network policies must be disabled
az network vnet subnet create -g $ResourceGroup --vnet-name $ProvVnet -n $PlsSubnet `
    --address-prefixes $PlsPrefix `
    --private-link-service-network-policies Disabled `
    -o none --only-show-errors
Assert-Az "PLS subnet"

# ----------------------------------------------------------------------------
# 3. Consumer VNet (10.20.0.0/16)
# ----------------------------------------------------------------------------
Write-Step "3/10  Creating consumer VNet $ConsVnet ($ConsCidr)"
az network vnet create -g $ResourceGroup -n $ConsVnet -l $Location `
    --address-prefixes $ConsCidr `
    --subnet-name $ConsVmSubnet --subnet-prefixes $ConsVmPrefix `
    -o none --only-show-errors
Assert-Az "consumer vnet"

az network vnet subnet create -g $ResourceGroup --vnet-name $ConsVnet -n $PeSubnet `
    --address-prefixes $PePrefix `
    --private-endpoint-network-policies Disabled `
    -o none --only-show-errors
Assert-Az "private endpoint subnet"

# ----------------------------------------------------------------------------
# 4. NAT gateway (outbound internet for vmproduction, which has no public IP)
# ----------------------------------------------------------------------------
Write-Step "4/10  Creating NAT gateway for provider subnet (apt/nginx install)"
az network public-ip create -g $ResourceGroup -n $NatPip -l $Location `
    --sku Standard --allocation-method Static -o none --only-show-errors
Assert-Az "NAT public IP"

az network nat gateway create -g $ResourceGroup -n $NatGw -l $Location `
    --public-ip-addresses $NatPip --idle-timeout 10 -o none --only-show-errors
Assert-Az "NAT gateway"

az network vnet subnet update -g $ResourceGroup --vnet-name $ProvVnet -n $ProvVmSubnet `
    --nat-gateway $NatGw -o none --only-show-errors
Assert-Az "attach NAT gateway"

# ----------------------------------------------------------------------------
# 5. NSG for vmproduction (HTTP from VNet; LB probes allowed by default rules)
# ----------------------------------------------------------------------------
Write-Step "5/10  Creating NSG $ProdNsg"
az network nsg create -g $ResourceGroup -n $ProdNsg -l $Location -o none --only-show-errors
Assert-Az "production NSG"

az network nsg rule create -g $ResourceGroup --nsg-name $ProdNsg -n Allow-HTTP-From-VNet `
    --priority 100 --direction Inbound --access Allow --protocol Tcp `
    --source-address-prefixes VirtualNetwork --source-port-ranges "*" `
    --destination-address-prefixes "*" --destination-port-ranges 80 `
    -o none --only-show-errors
Assert-Az "production NSG rule"

# ----------------------------------------------------------------------------
# 6. Standard internal load balancer
# ----------------------------------------------------------------------------
Write-Step "6/10  Creating Standard internal load balancer $LbName ($LbFrontendIp)"
az network lb create -g $ResourceGroup -n $LbName -l $Location --sku Standard `
    --vnet-name $ProvVnet --subnet $ProvVmSubnet `
    --frontend-ip-name $LbFrontend --private-ip-address $LbFrontendIp `
    --backend-pool-name $LbPool `
    -o none --only-show-errors
Assert-Az "load balancer"

az network lb probe create -g $ResourceGroup --lb-name $LbName -n $LbProbe `
    --protocol Http --port 80 --path /health -o none --only-show-errors
Assert-Az "LB probe"

az network lb rule create -g $ResourceGroup --lb-name $LbName -n $LbRule `
    --protocol Tcp --frontend-port 80 --backend-port 80 `
    --frontend-ip-name $LbFrontend --backend-pool-name $LbPool `
    --probe-name $LbProbe --idle-timeout 15 --enable-tcp-reset true `
    -o none --only-show-errors
Assert-Az "LB rule"

# ----------------------------------------------------------------------------
# 7. vmproduction (no public IP, in LB backend pool, nginx via cloud-init)
# ----------------------------------------------------------------------------
Write-Step "7/10  Creating $ProdVm (nginx via cloud-init, no public IP)"
az network nic create -g $ResourceGroup -n $ProdNic -l $Location `
    --vnet-name $ProvVnet --subnet $ProvVmSubnet `
    --network-security-group $ProdNsg `
    --lb-name $LbName --lb-address-pools $LbPool `
    -o none --only-show-errors
Assert-Az "production NIC"

az vm create -g $ResourceGroup -n $ProdVm -l $Location `
    --image $Image --size $VmSize `
    --admin-username $AdminUser --admin-password $VmPassword `
    --authentication-type password `
    --nics $ProdNic `
    --custom-data $cloudInitPath `
    -o none --only-show-errors
Assert-Az "vmproduction"

# ----------------------------------------------------------------------------
# 8. vmconsumer (public IP for SSH)
# ----------------------------------------------------------------------------
Write-Step "8/10  Creating $ConsVm (public IP for SSH)"
az vm create -g $ResourceGroup -n $ConsVm -l $Location `
    --image $Image --size $VmSize `
    --admin-username $AdminUser --admin-password $VmPassword `
    --authentication-type password `
    --vnet-name $ConsVnet --subnet $ConsVmSubnet `
    --public-ip-address $ConsPip --public-ip-sku Standard `
    --nsg $ConsNsg --nsg-rule SSH `
    -o none --only-show-errors
Assert-Az "vmconsumer"

# ----------------------------------------------------------------------------
# 9. Private Link Service + Private Endpoint
# ----------------------------------------------------------------------------
Write-Step "9/10  Creating Private Link Service $PlsName and Private Endpoint $PeName"
az network private-link-service create -g $ResourceGroup -n $PlsName -l $Location `
    --vnet-name $ProvVnet --subnet $PlsSubnet `
    --lb-name $LbName --lb-frontend-ip-configs $LbFrontend `
    -o none --only-show-errors
Assert-Az "private link service"

$plsId = az network private-link-service show -g $ResourceGroup -n $PlsName --query id -o tsv --only-show-errors
Assert-Az "read PLS id"

az network private-endpoint create -g $ResourceGroup -n $PeName -l $Location `
    --vnet-name $ConsVnet --subnet $PeSubnet `
    --private-connection-resource-id $plsId `
    --connection-name $PeConnection `
    -o none --only-show-errors
Assert-Az "private endpoint"

$peNicId = az network private-endpoint show -g $ResourceGroup -n $PeName --query "networkInterfaces[0].id" -o tsv --only-show-errors
$peIp    = az network nic show --ids $peNicId --query "ipConfigurations[0].privateIPAddress" -o tsv --only-show-errors
$peState = az network private-endpoint show -g $ResourceGroup -n $PeName `
    --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState.status" -o tsv --only-show-errors
Write-Host "    Private Endpoint IP : $peIp"
Write-Host "    Connection state    : $peState"

# ----------------------------------------------------------------------------
# 10. Wait for nginx, then test from vmconsumer through the Private Endpoint
# ----------------------------------------------------------------------------
Write-Step "10/10 Waiting for cloud-init on $ProdVm (a few minutes)"
az vm run-command invoke -g $ResourceGroup -n $ProdVm --command-id RunShellScript `
    --scripts "cloud-init status --wait" "systemctl is-active nginx" "curl -fsS http://localhost/health" `
    --query "value[0].message" -o tsv --only-show-errors
Assert-Az "cloud-init wait"

Write-Step "Testing from $ConsVm -> http://$peIp (Private Endpoint)"
az vm run-command invoke -g $ResourceGroup -n $ConsVm --command-id RunShellScript `
    --scripts "curl -fsS -m 15 http://$peIp/health" "curl -sI -m 15 http://$peIp/" `
    --query "value[0].message" -o tsv --only-show-errors
Assert-Az "consumer test"

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
$consPublicIp = az vm show -d -g $ResourceGroup -n $ConsVm --query publicIps -o tsv --only-show-errors

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Green
Write-Host " Deployment complete" -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Green
Write-Host " Resource group      : $ResourceGroup"
Write-Host " Provider VNet       : $ProvVnet  $ProvCidr  (vmproduction, no public IP)"
Write-Host " Consumer VNet       : $ConsVnet  $ConsCidr  (vmconsumer)"
Write-Host " Load balancer       : $LbName  frontend $LbFrontendIp"
Write-Host " Private Endpoint IP : $peIp"
Write-Host " vmconsumer public IP: $consPublicIp"
Write-Host " VM login            : $AdminUser / (the password you entered)  - same on both VMs"
Write-Host ""
Write-Host " Connect and view the page:" -ForegroundColor Yellow
Write-Host "   ssh $AdminUser@$consPublicIp        # log in with the password you set"
Write-Host "   curl http://$peIp/            # terminal edition (colour)"
Write-Host "   curl http://$peIp/html        # HTML edition"
Write-Host "   curl -I http://$peIp/         # headers"
Write-Host ""
Write-Host " Reach vmproduction (no public IP) from vmconsumer? It is in a different,"
Write-Host " un-peered VNet, so SSH only works via the Azure portal Serial Console or run-command:"
Write-Host "   az vm run-command invoke -g $ResourceGroup -n $ProdVm --command-id RunShellScript --scripts 'systemctl status nginx'"
Write-Host ""
Write-Host " Clean up when finished:" -ForegroundColor Yellow
Write-Host "   az group delete -n $ResourceGroup --yes --no-wait"
Write-Host ""

Remove-Variable VmPassword -ErrorAction SilentlyContinue