# Lab — Network Security Groups · Two-Tier Architecture

A hands-on lab that builds a **secure two-tier app** in Azure:

| Tier | VM | Subnet | Private IP | NSG | Role |
|------|----|--------|-----------|-----|------|
| Web  | `vm-dev-eus-web-01` | `snet-dev-eus-web-01` (10.0.0.0/24) | **10.0.0.4** | `nsg-dev-eus-web-01` | Python (Flask) app — reachable from the internet on port 80 |
| DB   | `vm-dev-eus-db-01`  | `snet-dev-eus-db-01` (10.0.1.0/24)  | **10.0.1.4** | `nsg-dev-eus-db-01`  | MySQL — reachable **only** from the web tier |

**Goal:** users on the internet reach the web app; only the web app reaches
the database; and neither VM can start outbound connections to the internet.

```
Internet ──80──▶ vm-dev-eus-web-01 (10.0.0.4) ──3306──▶ vm-dev-eus-db-01 (10.0.1.4)
                 (public IP, app.py)                      (MySQL, no public access)
```

---

## Files in this repo

| File | Purpose |
|------|---------|
| `app.py` | The web-tier Flask app. Connects to MySQL on `10.0.1.4`, writes/reads a `messages` table, and shows a live DB health indicator. |
| `requirements.txt` | Python dependencies (`Flask`, `PyMySQL`). |
| `README.md` | This guide. |

---

## Prerequisites

- Azure subscription + the resource group / VNet / VMs already deployed (matching the table above).
- **Azure CLI** installed and signed in from **PowerShell**:

```powershell
az login
az account set --subscription "<your-subscription-id>"

# Set these once so every command below just works
$RG   = "rg-dev-eus"          # resource group
$WEB  = "vm-dev-eus-web-01"
$DB   = "vm-dev-eus-db-01"
$NSGW = "nsg-dev-eus-web-01"  # web NSG
$NSGD = "nsg-dev-eus-db-01"   # db  NSG
```

---

## Step 1 — Install the MySQL server (run on `vm-dev-eus-db-01`)

SSH into the **DB VM**, then run:

```bash
# 1 - Install the MySQL server
sudo apt update
sudo apt install -y mysql-server
sudo systemctl enable --now mysql

# 2 - Make MySQL listen on the network
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf
# Change the bind address to the DB VM's private IP:
#   bind-address = 10.0.1.4
sudo systemctl restart mysql

# 3 - Create a new MySQL user
sudo mysql
```

Inside the `mysql>` prompt:

```sql
CREATE USER 'dbadmin'@'%' IDENTIFIED BY 'Microsoft2025';
GRANT ALL PRIVILEGES ON *.* TO 'dbadmin'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EXIT;
```

> The app creates its own database (`appdb`) and `messages` table automatically
> on first run, so no manual schema work is needed.

---

## Step 2 — Deny outbound internet from **both** VMs

Neither VM should be able to start connections out to the internet.

```powershell
# --- Web NSG: deny outbound to internet ---
az network nsg rule create --resource-group $RG --nsg-name $NSGW `
  --name DenyOutboundInternet --priority 4000 --direction Outbound --access Deny `
  --protocol "*" --source-address-prefixes "*" --source-port-ranges "*" `
  --destination-address-prefixes Internet --destination-port-ranges "*"

# --- DB NSG: deny outbound to internet ---
az network nsg rule create --resource-group $RG --nsg-name $NSGD `
  --name DenyOutboundInternet --priority 4000 --direction Outbound --access Deny `
  --protocol "*" --source-address-prefixes "*" --source-port-ranges "*" `
  --destination-address-prefixes Internet --destination-port-ranges "*"
```

---

## Step 3 — Allow internet users to reach the web app on port 80

```powershell
az network nsg rule create --resource-group $RG --nsg-name $NSGW `
  --name AllowHTTP-Inbound --priority 100 --direction Inbound --access Allow `
  --protocol Tcp --source-address-prefixes Internet --source-port-ranges "*" `
  --destination-address-prefixes 10.0.0.4 --destination-port-ranges 80
```

> If your web app will instead serve HTTPS, use `--destination-port-ranges 443`.

---

## Step 4 — Allow the web tier to reach MySQL (port 3306) on the DB tier

This is the one path that lets the two tiers talk. Source is the **web subnet**,
destination is the DB VM on the MySQL port.

```powershell
az network nsg rule create --resource-group $RG --nsg-name $NSGD `
  --name Allow-Web-to-MySQL --priority 100 --direction Inbound --access Allow `
  --protocol Tcp --source-address-prefixes 10.0.0.0/24 --source-port-ranges "*" `
  --destination-address-prefixes 10.0.1.4 --destination-port-ranges 3306
```

---

## Step 5 — Deny MySQL from anywhere else

Right after the allow rule, block MySQL from every other source so nothing but
the web subnet can hit the database.

```powershell
az network nsg rule create --resource-group $RG --nsg-name $NSGD `
  --name DenyElementMySQL --priority 200 --direction Inbound --access Deny `
  --protocol Tcp --source-address-prefixes "*" --source-port-ranges "*" `
  --destination-address-prefixes 10.0.1.4 --destination-port-ranges 3306
```

---

## Step 6 — Deny a variety of other inbound ports on both NSGs

A catch-all deny for common management/attack ports (SSH, RDP, WinRM, etc.).

```powershell
$ports = "22 3389 5985 5986 445 135 23 21"

az network nsg rule create --resource-group $RG --nsg-name $NSGW `
  --name DenyInboundPorts --priority 3000 --direction Inbound --access Deny `
  --protocol "*" --source-address-prefixes "*" --source-port-ranges "*" `
  --destination-address-prefixes "*" --destination-port-ranges $ports.Split(" ")

az network nsg rule create --resource-group $RG --nsg-name $NSGD `
  --name DenyInboundPorts --priority 3000 --direction Inbound --access Deny `
  --protocol "*" --source-address-prefixes "*" --source-port-ranges "*" `
  --destination-address-prefixes "*" --destination-port-ranges $ports.Split(" ")
```

> Keep a temporary higher-priority SSH allow rule (e.g. from your own IP) while
> you configure the VMs, then remove it once the lab is set up.

**Verify the rules on either NSG:**

```powershell
az network nsg rule list --resource-group $RG --nsg-name $NSGD -o table
az network nsg rule list --resource-group $RG --nsg-name $NSGW -o table
```

---

## Step 7 — Deploy & run the Python app (on `vm-dev-eus-web-01`)

SSH into the **web VM** and set it up:

```bash
# System packages
sudo apt update
sudo apt install -y python3 python3-pip python3-venv

# Get the app onto the VM (copy app.py + requirements.txt here)
mkdir -p ~/twotier && cd ~/twotier
# ...place app.py and requirements.txt in this folder...

# Isolated environment + dependencies
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Run it (port 80 needs sudo). The DB defaults already point at 10.0.1.4.
sudo -E env PATH=$PATH python3 app.py
```

You can override any connection setting via environment variables:

```bash
export DB_HOST=10.0.1.4
export DB_USER=dbadmin
export DB_PASSWORD=Microsoft2025
export DB_NAME=appdb
export APP_PORT=80
```

### (Optional) Run as a service so it survives reboots

```bash
sudo tee /etc/systemd/system/twotier.service >/dev/null <<'EOF'
[Unit]
Description=Two-Tier Web App
After=network.target

[Service]
WorkingDirectory=/home/azureuser/twotier
Environment=DB_HOST=10.0.1.4
Environment=DB_USER=dbadmin
Environment=DB_PASSWORD=Microsoft2025
Environment=DB_NAME=appdb
Environment=APP_PORT=80
ExecStart=/home/azureuser/twotier/.venv/bin/python /home/azureuser/twotier/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now twotier
sudo systemctl status twotier
```

---

## Step 8 — Test it

1. Get the web VM's public IP:

   ```powershell
   az vm show -d --resource-group $RG --name $WEB --query publicIps -o tsv
   ```

2. Open `http://<public-ip>/` in a browser. You should see the app with a
   **green "Database connection healthy"** badge.
3. Post a message — it gets written to MySQL on `10.0.1.4` and read back.
4. Health check for monitoring: `http://<public-ip>/healthz` (returns JSON,
   `200` when the DB is reachable, `503` when it isn't).

---

## What "secure" looks like when you're done

- ✅ Internet → web app on **port 80** only.
- ✅ Web subnet → DB on **port 3306** only.
- ⛔ Internet → DB: **blocked**.
- ⛔ Any VM → internet (outbound): **blocked**.
- ⛔ Management ports (SSH/RDP/WinRM/etc.): **blocked** once setup is complete.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| App shows **red "Database unreachable"** | DB NSG blocks 3306, or MySQL not listening on the network | Confirm Step 4 allow rule; check `bind-address = 10.0.1.4` and `sudo systemctl status mysql` |
| `Access denied for user 'dbadmin'` | Wrong password / user not created | Re-run the `CREATE USER … GRANT …` block in Step 1 |
| Can't SSH to a VM | `DenyInboundPorts` (Step 6) is blocking 22 | Add a temporary higher-priority allow rule from your IP |
| Page won't load at all | Port 80 not allowed, or app not running | Verify Step 3 rule and `sudo systemctl status twotier` |

---

### Security note

The password `Microsoft2025` and the wide-open `dbadmin'@'%'` grant are here to
keep the **lab** simple. For anything real, use a strong secret (Azure Key Vault),
scope the grant to the specific database, and restrict the host pattern.
