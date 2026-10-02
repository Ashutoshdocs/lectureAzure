# Azure VM + Application Insights + VM Insights: End-to-End Monitoring Demo

A hands-on lab that takes you from an empty subscription to a fully monitored Linux VM:

1. Create a **password-based Ubuntu VM**
2. Deploy a small **Python (Flask) web app** instrumented with **Application Insights**
3. Enable **VM Insights** (Azure Monitor Agent + Data Collection Rule)
4. Generate **CPU load** and **URL traffic** (including slow requests and errors)
5. Watch it all show up in **Metrics, VM Insights, Application Insights and Log Analytics (KQL)**
6. Fire an **alert** when CPU goes high
7. Clean up

> ⏱️ Time: ~60–75 minutes  ·  💰 Cost: a few USD if you delete everything at the end

---

## Architecture

```
                    ┌──────────────────────── Azure ─────────────────────────┐
  You (browser,     │                                                        │
  curl, ab) ──HTTP──┼──► Public IP :8080 ──► Ubuntu VM (Standard_B2s)        │
                    │                        │                               │
                    │                        ├─ Flask app (gunicorn)         │
                    │                        │    └─ OpenTelemetry SDK ──────┼──► Application Insights
                    │                        │                               │         │
                    │                        └─ Azure Monitor Agent (AMA) ───┼──► Log Analytics Workspace
                    │                              (via DCR: VM Insights)     │         ▲
                    │                                                        │         │
                    │   Platform metrics (Percentage CPU, Network) ──────────┼──► Azure Monitor Metrics
                    │                                                        │         │
                    │                                    Alert rule ◄────────┼─────────┘
                    │                                       └─► Action Group (email)
                    └────────────────────────────────────────────────────────┘
```

| Layer | What it tells you | Where to look |
|---|---|---|
| **Platform metrics** (no agent) | Host-level CPU %, network, disk ops | VM → *Metrics* |
| **VM Insights** (AMA + DCR) | Guest OS CPU, memory, disk, processes | VM → *Insights* / `InsightsMetrics` table |
| **Application Insights** | Requests, response times, failures, exceptions, dependencies | App Insights → *Live Metrics*, *Performance*, *Failures* |
| **Alerts** | Notify when a threshold is breached | Monitor → *Alerts* |

---

## Prerequisites

- An Azure subscription (Contributor on the subscription or a resource group)
- **Azure CLI** 2.60+ — or just use **Azure Cloud Shell** (Bash) in the portal
- An SSH client (built into macOS/Linux/Windows 10+)

```bash
az login
az account set --subscription "<your-subscription-name-or-id>"

# Application Insights CLI commands live in an extension
az extension add --name application-insights --upgrade
```

---

## Step 0 — Set variables

Run these once in your shell; every later command uses them.

```bash
$RG = "rg-monitor-demo"
$LOCATION = "centralindia" # pick a region near you
$VM_NAME = "vm-demo-web"
$VM_SIZE = "Standard_B2s" # 2 vCPU / 4 GB — enough to see load clearly
$ADMIN_USER = "azureuser"
$ADMIN_PASS = 'Demo@Passw0rd!2026' # 12–72 chars, upper+lower+digit+special
$LAW_NAME = "law-monitor-demo"
$APPI_NAME = "appi-monitor-demo"
$DCR_NAME = "dcr-vminsights-demo"
$AG_NAME = "ag-monitor-demo"
$ALERT_EMAIL = "ashutoshkumarinbox@gmail.com"
```

> 🔐 Password auth is used here because the lab is about monitoring, not hardening. For anything beyond a demo, use SSH keys and restrict port 22 to your IP.

---

## Step 1 — Create the resource group

```bash
az group create --name $RG --location $LOCATION
```

---

## Step 2 — Create the password-based Linux VM

```bash
az vm create   --resource-group $RG   --name $VM_NAME --image Ubuntu2204 --size $VM_SIZE --admin-username $ADMIN_USER  --admin-password "$ADMIN_PASS"  --authentication-type password --public-ip-sku Standard   --assign-identity --output table
```

`--assign-identity` gives the VM a system-assigned managed identity, which the Azure Monitor Agent uses to authenticate.

Open the app port (8080) — SSH (22) is opened automatically by `az vm create`:

```bash
az vm open-port --resource-group $RG --name $VM_NAME --port 8080 --priority 1010
```

Grab the public IP:

```bash
VM_IP=$(az vm show -d -g $RG -n $VM_NAME --query publicIps -o tsv)
echo "VM public IP: $VM_IP"
```

<details>
<summary>Portal alternative</summary>

*Virtual machines → Create → Azure virtual machine*
- Image: **Ubuntu Server 22.04 LTS**, Size: **B2s**
- Authentication type: **Password**, enter username/password
- Inbound ports: **SSH (22)**
- *Management* tab → **Enable system assigned managed identity**
- After creation: *Networking* → add inbound rule for **TCP 8080**
</details>

---

## Step 3 — Create Log Analytics workspace + Application Insights

```bash
# Log Analytics workspace (stores VM Insights + App Insights data)
New-AzOperationalInsightsWorkspace -ResourceGroupName $RG -Name $LAW_NAME -Location $LOCATION

$LAW_ID = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $RG -Name $LAW_NAME).ResourceId

# Workspace-based Application Insights
# Note: Ensure you have the Az.ApplicationInsights module installed
New-AzApplicationInsights -ResourceGroupName $RG -Name $APPI_NAME -Location $LOCATION -WorkspaceResourceId $LAW_ID -ApplicationType web

$APPI_CONN = (Get-AzApplicationInsights -ResourceGroupName $RG -Name $APPI_NAME).ConnectionString
Write-Output $APPI_CONN
```

Copy the connection string — you'll paste it on the VM in Step 5.

---

## Step 4 — SSH in and prepare the VM

```bash
ssh $ADMIN_USER@$VM_IP
# type the password from Step 0
```

On the VM:

```bash
sudo apt-get update
sudo apt-get install -y python3-venv python3-pip stress-ng apache2-utils htop
```

| Package | Used for |
|---|---|
| `python3-venv` | isolated Python env for the app |
| `stress-ng` | generating CPU load |
| `apache2-utils` | provides `ab` (Apache Bench) for URL load |
| `htop` | watching CPU live on the box |

---

## Step 5 — Deploy the instrumented web app

### 5.1 Create the app

```bash
sudo mkdir -p /opt/demoapp && sudo chown $USER:$USER /opt/demoapp
cd /opt/demoapp
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install flask gunicorn azure-monitor-opentelemetry requests
```

Create `/opt/demoapp/app.py`:

```python
import math
import os
import random
import time

from azure.monitor.opentelemetry import configure_azure_monitor

# Must run before Flask is imported/used so requests are auto-instrumented.
# Reads APPLICATIONINSIGHTS_CONNECTION_STRING from the environment.
configure_azure_monitor(logger_name="demoapp")

import logging
import requests
from flask import Flask, jsonify

app = Flask(__name__)
log = logging.getLogger("demoapp")
log.setLevel(logging.INFO)


@app.route("/")
def home():
    log.info("Home page hit")
    return jsonify(status="ok", host=os.uname().nodename, msg="Hello from Azure VM!")


@app.route("/cpu")
def cpu():
    """Burn CPU for ~2 seconds -> visible in VM CPU and request duration."""
    end = time.time() + 2
    n = 0
    while time.time() < end:
        math.sqrt(random.random()) * math.factorial(200)
        n += 1
    log.info("CPU burn completed", extra={"iterations": n})
    return jsonify(status="burned", iterations=n)


@app.route("/slow")
def slow():
    """Random 1–4 s latency -> shows up in App Insights Performance blade."""
    delay = random.uniform(1, 4)
    time.sleep(delay)
    return jsonify(status="slow", delay_seconds=round(delay, 2))


@app.route("/error")
def error():
    """Raise an unhandled exception -> 500 + entry in Failures blade."""
    log.warning("About to throw a demo exception")
    raise RuntimeError("Demo exception for Application Insights")


@app.route("/external")
def external():
    """Outbound HTTP call -> shows as a Dependency in Application Map."""
    r = requests.get("https://httpbin.org/delay/1", timeout=10)
    return jsonify(status="called external", upstream_status=r.status_code)


@app.route("/health")
def health():
    return "healthy", 200
```

### 5.2 Run it as a systemd service

```bash
sudo tee /etc/systemd/system/demoapp.service > /dev/null <<'EOF'
[Unit]
Description=Demo Flask app with Application Insights
After=network.target

[Service]
User=azureuser
WorkingDirectory=/opt/demoapp
Environment="APPLICATIONINSIGHTS_CONNECTION_STRING=PASTE_YOUR_CONNECTION_STRING_HERE"
Environment="OTEL_SERVICE_NAME=demo-web"
ExecStart=/opt/demoapp/venv/bin/gunicorn --workers 2 --bind 0.0.0.0:8080 app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF
```

Edit the file and replace `PASTE_YOUR_CONNECTION_STRING_HERE` with the value of `$APPI_CONN` from Step 3:

```bash
sudo nano /etc/systemd/system/demoapp.service
```

> If your admin username isn't `azureuser`, change `User=` too.

Start it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now demoapp
sudo systemctl status demoapp --no-pager
curl -s localhost:8080/
```

From **your laptop**, open `http://<VM_IP>:8080/` — you should see the JSON greeting.

> `OTEL_SERVICE_NAME` becomes the **Cloud role name** — the node label you'll see in Application Map.

---

## Step 6 — Enable VM Insights (Azure Monitor Agent + DCR)

Back on **your laptop / Cloud Shell** (not the VM).

### 6.1 Install the Azure Monitor Agent

```bash
az vm extension set \
  --resource-group $RG \
  --vm-name $VM_NAME \
  --name AzureMonitorLinuxAgent \
  --publisher Microsoft.Azure.Monitor \
  --enable-auto-upgrade true
```

### 6.2 Create a VM Insights Data Collection Rule

Save as `dcr-vminsights.json` (replace the two placeholders):

```json
{
  "location": "<LOCATION>",
  "properties": {
    "description": "VM Insights performance counters + syslog",
    "dataSources": {
      "performanceCounters": [
        {
          "name": "VMInsightsPerfCounters",
          "streams": ["Microsoft-InsightsMetrics"],
          "samplingFrequencyInSeconds": 60,
          "counterSpecifiers": ["\\VmInsights\\DetailedMetrics"]
        }
      ],
      "syslog": [
        {
          "name": "sysLogsDataSource",
          "streams": ["Microsoft-Syslog"],
          "facilityNames": ["auth", "daemon", "syslog", "user"],
          "logLevels": ["Warning", "Error", "Critical", "Alert", "Emergency"]
        }
      ]
    },
    "destinations": {
      "logAnalytics": [
        {
          "name": "lawDestination",
          "workspaceResourceId": "<LAW_ID>"
        }
      ]
    },
    "dataFlows": [
      { "streams": ["Microsoft-InsightsMetrics"], "destinations": ["lawDestination"] },
      { "streams": ["Microsoft-Syslog"],          "destinations": ["lawDestination"] }
    ]
  }
}
```

Quick way to fill the placeholders:

```bash
sed -i "s|<LOCATION>|$LOCATION|; s|<LAW_ID>|$LAW_ID|" dcr-vminsights.json
```

Create the DCR and associate it with the VM:

```bash
az monitor data-collection rule create \
  --resource-group $RG \
  --name $DCR_NAME \
  --rule-file dcr-vminsights.json

DCR_ID=$(az monitor data-collection rule show -g $RG -n $DCR_NAME --query id -o tsv)
VM_ID=$(az vm show -g $RG -n $VM_NAME --query id -o tsv)

az monitor data-collection rule association create \
  --name "${VM_NAME}-dcr-assoc" \
  --rule-id $DCR_ID \
  --resource $VM_ID
```

<details>
<summary>Portal alternative (simplest)</summary>

VM → *Monitoring* → **Insights** → **Enable** → choose **Azure Monitor Agent** → create/select a Data Collection Rule pointing to `law-monitor-demo` → **Configure**. The portal installs the agent and creates the DCR for you.
</details>

> ⏳ It takes **5–15 minutes** for the first VM Insights data to appear. Use the time to run Step 7.

---

## Step 7 — Generate load and traffic

Open **two SSH sessions** to the VM (or use `tmux`).

### Session A — watch the box

```bash
htop
```

### Session B — run the scenarios

**Baseline traffic (healthy requests):**

```bash
ab -n 2000 -c 20 http://localhost:8080/
```

**CPU load from the OS (stress-ng) — 5 minutes on both vCPUs:**

```bash
stress-ng --cpu 2 --cpu-load 90 --timeout 300s --metrics-brief
```

**CPU load through the app (shows in both VM and App Insights):**

```bash
ab -n 200 -c 4 http://localhost:8080/cpu
```

**Mixed realistic traffic — run this from your laptop so requests come from the internet:**

```bash
VM_IP=<your VM public IP>
for i in $(seq 1 300); do
  curl -s -o /dev/null -w "%{http_code} /\n"        http://$VM_IP:8080/
  curl -s -o /dev/null -w "%{http_code} /slow\n"    http://$VM_IP:8080/slow &
  [ $((i % 5))  -eq 0 ] && curl -s -o /dev/null -w "%{http_code} /error\n"    http://$VM_IP:8080/error
  [ $((i % 10)) -eq 0 ] && curl -s -o /dev/null -w "%{http_code} /external\n" http://$VM_IP:8080/external
  sleep 0.5
done
wait
```

What each scenario produces:

| Scenario | VM Metrics / VM Insights | Application Insights |
|---|---|---|
| `ab /` | small CPU bump | spike in request rate, low latency |
| `stress-ng` | CPU ~90% for 5 min → **alert fires** | nothing (not app traffic) |
| `ab /cpu` | high CPU | high server response time on `/cpu` |
| `/slow` | none | 1–4 s durations in *Performance* |
| `/error` | none | 500s + `RuntimeError` in *Failures* |
| `/external` | small network out | dependency on `httpbin.org` in *Application Map* |

---

## Step 8 — See the monitoring in action

### 8.1 Platform metrics (instant, no agent)

Portal → **VM** → *Monitoring* → **Metrics**
- Metric: **Percentage CPU**, Aggregation: **Avg**, time range: last 30 min
- Add metric: **Network In Total** / **Network Out Total**
- Click **Pin to dashboard** to keep it

You'll see the CPU plateau during `stress-ng` and spikes during `ab /cpu`.

### 8.2 VM Insights (guest OS view)

Portal → **VM** → *Monitoring* → **Insights**
- **Performance** tab: CPU utilization %, available memory, logical disk IOPS, bytes sent/received — from inside the OS
- Compare with `htop` in Session A: the numbers should line up

### 8.3 Application Insights

Portal → **Application Insights** → `appi-monitor-demo`

| Blade | What to show |
|---|---|
| **Live Metrics** | Open it *while* the traffic loop runs — incoming requests, failures, CPU and memory stream in with ~1 s delay |
| **Application Map** | `demo-web` node → `httpbin.org` dependency, with call counts and failure % |
| **Performance** | Operations sorted by duration — `/slow` and `/cpu` stand out; drill into samples to see an end-to-end transaction |
| **Failures** | `GET /error` with 500 responses; *Exceptions* tab shows `RuntimeError: Demo exception…` with the stack trace |
| **Transaction search** | Find one request and open the full trace, including log messages emitted by `log.info()` |

> Telemetry is batched, so standard blades lag by ~1–3 minutes. Live Metrics is real-time.

### 8.4 Log Analytics — KQL queries

Portal → **Log Analytics workspace** → **Logs** (or App Insights → **Logs**).
Tables in the workspace use the `App*` names below; inside App Insights → Logs you can also use the classic names (`requests`, `exceptions`, `dependencies`).

**VM CPU from VM Insights (5-min avg):**

```kusto
InsightsMetrics
| where TimeGenerated > ago(1h)
| where Namespace == "Processor" and Name == "UtilizationPercentage"
| summarize AvgCPU = avg(Val) by bin(TimeGenerated, 5m), Computer
| render timechart
```

**Available memory (MB):**

```kusto
InsightsMetrics
| where TimeGenerated > ago(1h)
| where Namespace == "Memory" and Name == "AvailableMB"
| summarize AvgAvailableMB = avg(Val) by bin(TimeGenerated, 5m)
| render timechart
```

**Request count and failure rate per endpoint:**

```kusto
AppRequests
| where TimeGenerated > ago(1h)
| summarize Requests = count(),
            Failed   = countif(Success == false),
            P95ms    = percentile(DurationMs, 95)
          by Name
| extend FailureRate = round(100.0 * Failed / Requests, 1)
| order by Requests desc
```

**Requests per minute (traffic shape):**

```kusto
AppRequests
| where TimeGenerated > ago(1h)
| summarize count() by bin(TimeGenerated, 1m), ResultCode
| render timechart
```

**Exceptions:**

```kusto
AppExceptions
| where TimeGenerated > ago(1h)
| summarize Count = count() by ExceptionType, OuterMessage
```

**Correlate high CPU with slow requests:**

```kusto
let cpu = InsightsMetrics
  | where TimeGenerated > ago(1h)
  | where Namespace == "Processor" and Name == "UtilizationPercentage"
  | summarize AvgCPU = avg(Val) by bin(TimeGenerated, 1m);
let req = AppRequests
  | where TimeGenerated > ago(1h)
  | summarize AvgDurationMs = avg(DurationMs) by bin(TimeGenerated, 1m);
cpu
| join kind=inner req on TimeGenerated
| project TimeGenerated, AvgCPU, AvgDurationMs
| render timechart
```

**Syslog warnings and errors from the VM:**

```kusto
Syslog
| where TimeGenerated > ago(1h)
| project TimeGenerated, Facility, SeverityLevel, ProcessName, SyslogMessage
| order by TimeGenerated desc
```

---

## Step 9 — Alerts: get notified on high CPU and failures

### 9.1 Action group (email)

```bash
az monitor action-group create \
  --resource-group $RG \
  --name $AG_NAME \
  --short-name demoag \
  --action email admin $ALERT_EMAIL

AG_ID=$(az monitor action-group show -g $RG -n $AG_NAME --query id -o tsv)
```

### 9.2 Metric alert — CPU > 70% for 5 minutes

```bash
az monitor metrics alert create \
  --name "alert-high-cpu" \
  --resource-group $RG \
  --scopes $VM_ID \
  --condition "avg Percentage CPU > 70" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 2 \
  --action $AG_ID \
  --description "VM CPU above 70% for 5 minutes"
```

### 9.3 Metric alert — app failures

```bash
APPI_ID=$(az monitor app-insights component show -g $RG --app $APPI_NAME --query id -o tsv)

az monitor metrics alert create \
  --name "alert-failed-requests" \
  --resource-group $RG \
  --scopes $APPI_ID \
  --condition "count requests/failed > 5" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 3 \
  --action $AG_ID \
  --description "More than 5 failed requests in 5 minutes"
```

### 9.4 Trigger them

```bash
# on the VM
stress-ng --cpu 2 --cpu-load 95 --timeout 600s
```

```bash
# from your laptop
for i in $(seq 1 30); do curl -s -o /dev/null http://$VM_IP:8080/error; done
```

Within ~5–10 minutes:
- Portal → **Monitor** → **Alerts** shows both alerts as **Fired**
- You get an email for each
- After load stops, the CPU alert auto-resolves and you get a "Resolved" email

---

## Step 10 — (Optional) Dashboard

Portal → **Dashboard** → **New dashboard**, then pin:
- VM *Metrics* → Percentage CPU chart
- VM *Insights* → Performance charts
- App Insights → *Server requests*, *Failed requests*, *Server response time*
- Any KQL query result → **Pin to dashboard**

This gives a single screen to show during a demo.

---

## Troubleshooting

| Symptom | Check |
|---|---|
| Can't reach `http://<IP>:8080` | `sudo systemctl status demoapp`; NSG rule for 8080 exists; `curl localhost:8080` on the VM |
| No data in App Insights | Connection string pasted correctly in the service file? `sudo journalctl -u demoapp -n 50`; wait 2–3 min; try Live Metrics |
| VM Insights says "not configured" | `az vm extension list -g $RG --vm-name $VM_NAME -o table` shows `AzureMonitorLinuxAgent` *Succeeded*; DCR association exists; wait up to 15 min |
| `InsightsMetrics` empty | On the VM: `systemctl status azuremonitoragent`; confirm the VM has a managed identity |
| Alert didn't fire | CPU must stay above threshold for the whole window — run `stress-ng` for at least 10 min |
| `az monitor app-insights` not found | `az extension add --name application-insights` |

---

## Step 11 — Clean up

Delete everything so you stop paying:

```bash
az group delete --name $RG --yes --no-wait
```

---

## Recap: what we demonstrated

1. **Provisioned** a password-auth Ubuntu VM with a managed identity
2. **Instrumented** a Flask app with the Azure Monitor OpenTelemetry distro (one line: `configure_azure_monitor()`)
3. **Collected guest metrics** with the Azure Monitor Agent and a VM Insights DCR into Log Analytics
4. **Generated** CPU load (`stress-ng`, `/cpu`) and URL traffic (`ab`, curl loop with slow/error/external calls)
5. **Observed** the same incident from three angles — platform metrics, VM Insights, Application Insights — and **correlated** them with KQL
6. **Alerted** on CPU and failed requests via an action group

The key idea: **infrastructure monitoring tells you the box is busy; application monitoring tells you which requests are hurting and why.** You need both to go from "something is slow" to "`/cpu` is burning CPU and dragging p95 latency up".
