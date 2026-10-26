# =====================================================================
#  Hit the web app N times and show which instance answered each request
#  Usage:  .\test-lb.ps1 -App scaledemo123456 -Count 30
# =====================================================================
param(
  [string]$App   = "scaledemo123456",
  [int]   $Count = 30
)

$url = "https://$App.azurewebsites.net/instance"
Write-Host "Sending $Count requests to $url`n" -ForegroundColor Cyan

$results = 1..$Count | ForEach-Object {
  try {
    # -DisableKeepAlive = new connection each time, like separate users
    $id = (Invoke-WebRequest -Uri "$url`?r=$_" -UseBasicParsing -DisableKeepAlive -Headers @{ "Cache-Control" = "no-cache" }).Content.Trim()
    Write-Host ("{0,3}  {1}" -f $_, $id)
    $id
  } catch {
    Write-Host ("{0,3}  ERROR {1}" -f $_, $_.Exception.Message) -ForegroundColor Red
  }
}

Write-Host "`nDistribution:" -ForegroundColor Cyan
$results | Group-Object | Sort-Object Count -Descending |
  Format-Table @{ n = "Instance"; e = { $_.Name } },
               Count,
               @{ n = "Share"; e = { "{0:P0}" -f ($_.Count / $Count) } },
               @{ n = "Bar"; e = { "#" * $_.Count } } -AutoSize

$distinct = ($results | Select-Object -Unique).Count
if ($distinct -gt 1) {
  Write-Host "Load balancing works: $distinct instances answered." -ForegroundColor Green
} else {
  Write-Host "Only 1 instance answered. Check scale-out (instance count) and that ARR affinity is off." -ForegroundColor Yellow
}
