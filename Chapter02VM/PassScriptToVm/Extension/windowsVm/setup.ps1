<#
.SYNOPSIS
    Installs IIS and publishes a demo web page on an Azure VM.

.DESCRIPTION
    Meant to be run by the Azure Custom Script Extension (CSE) when a
    Windows Server VM is deployed. The script:
      1. Installs the IIS (Web-Server) role and its management tools
      2. Creates a styled HTML page
      3. Saves it as default.html in the IIS web root

.NOTES
    File   : setup.ps1
    Course : AZ-104 - Custom Script Extensions demo
    Runs as: SYSTEM (through the Custom Script Extension agent)
#>

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------
# Settings
# ------------------------------------------------------------
$WebRoot  = 'C:\inetpub\wwwroot'
$PageName = 'default.html'
$PagePath = Join-Path -Path $WebRoot -ChildPath $PageName

function Write-Step {
    param([string]$Message)
    Write-Output ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message)
}

try {
    # --------------------------------------------------------
    # Step 1 - Install IIS
    # --------------------------------------------------------
    Write-Step 'Installing IIS (Web-Server) role...'
    $result = Install-WindowsFeature -Name Web-Server -IncludeManagementTools
    Write-Step ("IIS install finished. Success: {0}, Restart needed: {1}" -f $result.Success, $result.RestartNeeded)

    # --------------------------------------------------------
    # Step 2 - Build the HTML page
    # --------------------------------------------------------
    Write-Step 'Building the demo HTML page...'
    $hostName = $env:COMPUTERNAME
    $deployed = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Custom Script Extensions Demo</title>
  <style>
    body {
      margin: 0; height: 100vh;
      display: flex; align-items: center; justify-content: center;
      font-family: 'Segoe UI', Arial, sans-serif;
      background: linear-gradient(135deg, #0078d4, #50e6ff);
    }
    .card {
      background: #ffffff; padding: 40px 50px; border-radius: 12px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.2); text-align: center; max-width: 600px;
    }
    h1 { color: #0078d4; margin-top: 0; }
    p  { color: #444; }
    .meta { font-size: 0.9em; color: #888; margin-top: 20px; }
  </style>
</head>
<body>
  <div class="card">
    <h1>&#9989; IIS is running</h1>
    <p>We now have Internet Information Services running on the machine.</p>
    <p>Installed automatically by the <strong>Azure Custom Script Extension</strong>.</p>
    <div class="meta">Server: $hostName &middot; Deployed: $deployed</div>
  </div>
</body>
</html>
"@

    # --------------------------------------------------------
    # Step 3 - Save the page to the IIS web root
    # --------------------------------------------------------
    Write-Step "Saving page to $PagePath ..."
    Set-Content -Path $PagePath -Value $html -Encoding UTF8 -Force

    Write-Step 'Done. Browse to http://<public-ip>/default.html'
    exit 0
}
catch {
    Write-Error ("Setup failed: {0}" -f $_.Exception.Message)
    exit 1
}
