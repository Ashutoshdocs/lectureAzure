# ==========================================================
# Azure Service Bus Order Processing Demo (PowerShell)
# ==========================================================

# ==========================================================
# 1. Create Azure Service Bus
# ==========================================================

# Variables
$LOCATION = "centralus"
$RG = "rg-orderdemo"
$SB_NS = "orders-demo-sb-$((Get-Random -Maximum 99999))"
$QUEUE = "orders"

# Create Resource Group
az group create --name $RG --location $LOCATION

# Create Service Bus Namespace
az servicebus namespace create --resource-group $RG --name $SB_NS --location $LOCATION --sku Standard

# Create Queue
az servicebus queue create --resource-group $RG --namespace-name $SB_NS --name $QUEUE

# Create Send + Listen Policy
az servicebus queue authorization-rule create `
    --resource-group $RG `
    --namespace-name $SB_NS `
    --queue-name $QUEUE `
    --name senderreceiver `
    --rights Send Listen

# Get Connection String
$CONNECTION_STRING = az servicebus queue authorization-rule keys list `
    --resource-group $RG `
    --namespace-name $SB_NS `
    --queue-name $QUEUE `
    --name senderreceiver `
    --query primaryConnectionString `
    -o tsv

Write-Host ""
Write-Host "=============================================="
Write-Host "Connection String"
Write-Host "=============================================="
Write-Host $CONNECTION_STRING
Write-Host ""

# ==========================================================
# 2. Create Azure VM
# ==========================================================

az vm create `
    --resource-group $RG `
    --name vm-orderdemo `
    --image Ubuntu2204 `
    --size Standard_B1s `
    --admin-username azureuser `
    --generate-ssh-keys `
    --public-ip-sku Standard

# Open Ports
az vm open-port `
    --resource-group $RG `
    --name vm-orderdemo `
    --port 5000 `
    --priority 1001

az vm open-port `
    --resource-group $RG `
    --name vm-orderdemo `
    --port 22 `
    --priority 1002

# Get Public IP
$VMIP = az vm show -d `
    --resource-group $RG `
    --name vm-orderdemo `
    --query publicIps `
    -o tsv

Write-Host ""
Write-Host "VM Public IP : $VMIP"
Write-Host ""

# ==========================================================
# 3. Copy Project to VM
# ==========================================================

scp -r Azure-ServiceBus-OrderSystem azureuser@$VMIP`:~/

ssh azureuser@$VMIP

cd ~/Azure-ServiceBus-OrderSystem

# ==========================================================
# 4. Install Python (Run on VM)
# ==========================================================

sudo apt update

sudo apt install -y python3 python3-pip python3-venv

python3 -m venv venv

source venv/bin/activate

pip install --upgrade pip

pip install -r requirements.txt

# ==========================================================
# 5. Configure Service Bus (Run on VM)
# ==========================================================

export SERVICE_BUS_CONNECTION_STRING="$CONNECTION_STRING"

export QUEUE_NAME="orders"

# OR

nano config.py

# ==========================================================
# 6. Initialize Database
# ==========================================================

python init_db.py

# ==========================================================
# 7. Start Flask App
# ==========================================================

source venv/bin/activate

python app.py

# OR

gunicorn --bind 0.0.0.0:5000 --workers 2 app:app

# ==========================================================
# 8. Start Worker
# ==========================================================

cd ~/Azure-ServiceBus-OrderSystem

source venv/bin/activate

python worker.py

# ==========================================================
# 9. Classroom Demo
# ==========================================================

# Browser
# http://<VMIP>:5000

# Dashboard
# Pending -> Processing -> Completed

# Azure Portal
# Active Messages decrease

# ==========================================================
# 9a. Slow Processing
# ==========================================================

export PROCESS_SECONDS=8

python worker.py


# Generate 20 Orders

# ==========================================================
# 9b. Multiple Workers
# ==========================================================

cd ~/Azure-ServiceBus-OrderSystem

source venv/bin/activate

python worker.py

# Open 3 terminals

# ==========================================================
# 9c. Failure Demo
# ==========================================================

export FAIL_MODE=1

python worker.py

# Later

export FAIL_MODE=0

# ==========================================================
# 10. SQLite Queries
# ==========================================================

sqlite3 database/orders.db

SELECT id,
       customer,
       product,
       quantity,
       status,
       created_on
FROM orders
ORDER BY id DESC
LIMIT 20;

SELECT status,
       COUNT(*) AS n
FROM orders
GROUP BY status;

SELECT AVG(strftime('%s', processed_on) -
           strftime('%s', created_on))
FROM orders
WHERE status='Completed';

SELECT *
FROM orders
WHERE status='Failed';

SELECT *
FROM orders
WHERE priority='High'
AND status='Pending';

.quit

# ==========================================================
# 10c. Dead Letter Count
# ==========================================================

az servicebus queue show `
    --resource-group $RG `
    --namespace-name $SB_NS `
    --name orders `
    --query "countDetails.deadLetterMessageCount"

# ==========================================================
# 11. Cleanup
# ==========================================================

az group delete `
    --name $RG `
    --yes `
    --no-wait