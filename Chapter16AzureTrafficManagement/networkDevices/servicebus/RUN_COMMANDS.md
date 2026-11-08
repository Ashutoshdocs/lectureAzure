# RUN COMMANDS — run these in order

Everything you type, top to bottom. Sections 1–7 are one-time setup;
section 8 onward is the live demo you repeat in class.

---

## 1. Azure Service Bus (Azure Portal or CLI)

### Option A — Azure CLI (fastest)
```bash
# variables
export LOCATION="eastus"
export RG="rg-orderdemo"
export SB_NS="orders-demo-sb-$RANDOM"     # must be globally unique
export QUEUE="orders"

az group create --name $RG --location $LOCATION

az servicebus namespace create \
  --resource-group $RG --name $SB_NS \
  --location $LOCATION --sku Standard

az servicebus queue create \
  --resource-group $RG --namespace-name $SB_NS --name $QUEUE

# limited-permission policy (Send + Listen)
az servicebus queue authorization-rule create \
  --resource-group $RG --namespace-name $SB_NS --queue-name $QUEUE \
  --name senderreceiver --rights Send Listen

# copy this connection string — you will paste it into config.py
az servicebus queue authorization-rule keys list \
  --resource-group $RG --namespace-name $SB_NS --queue-name $QUEUE \
  --name senderreceiver --query primaryConnectionString -o tsv
```

### Option B — Portal
1. Create resource → **Service Bus** → name `orders-demo-sb`, pricing **Standard**.
2. Inside the namespace → **Queues** → **+ Queue** → name `orders`.
3. Queue → **Shared access policies** → **+ Add** → name `senderreceiver`,
   tick **Send** and **Listen** → copy **Primary Connection String**.

---

## 2. Create the Azure VM (from your laptop)

```bash
az vm create \
  --resource-group $RG --name vm-orderdemo \
  --image Ubuntu2204 --size Standard_B1s \
  --admin-username azureuser --generate-ssh-keys --public-ip-sku Standard

# open the Flask port (5000) and SSH (22)
az vm open-port --resource-group $RG --name vm-orderdemo --port 5000 --priority 1001
az vm open-port --resource-group $RG --name vm-orderdemo --port 22   --priority 1002

# get the public IP
az vm show -d --resource-group $RG --name vm-orderdemo --query publicIps -o tsv
```

---

## 3. Copy the project to the VM and connect

```bash
# from the folder that CONTAINS Azure-ServiceBus-OrderSystem
scp -r Azure-ServiceBus-OrderSystem azureuser@<VM_PUBLIC_IP>:~/

ssh azureuser@<VM_PUBLIC_IP>
cd ~/Azure-ServiceBus-OrderSystem
```

---

## 4. Virtual environment + packages (on the VM)

```bash
sudo apt update
sudo apt install -y python3 python3-pip python3-venv

python3 -m venv venv
source venv/bin/activate

pip install --upgrade pip
pip install -r requirements.txt
```

---

## 5. Configure the connection string (on the VM)

Either export it (recommended)…
```bash
export SERVICE_BUS_CONNECTION_STRING="Endpoint=sb://<ns>.servicebus.windows.net/;SharedAccessKeyName=senderreceiver;SharedAccessKey=..."
export QUEUE_NAME="orders"
```
…or paste it into `config.py` (replace `PASTE_YOUR_CONNECTION_STRING_HERE`):
```bash
nano config.py
```

---

## 6. Initialise the database (on the VM)

```bash
python init_db.py
# → creates database/orders.db with the 'orders' table
```

---

## 7. Start the web app (Terminal 1, on the VM)

```bash
source venv/bin/activate          # if not already active
python app.py
# open http://<VM_PUBLIC_IP>:5000  in your browser
```

For a production-style server instead of the dev server:
```bash
gunicorn --bind 0.0.0.0:5000 --workers 2 app:app
```

---

## 8. Start a worker (Terminal 2, on the VM)

```bash
cd ~/Azure-ServiceBus-OrderSystem && source venv/bin/activate
python worker.py
```

---

## 9. THE DEMO — run these in class

```text
1. Browser → http://<VM_IP>:5000  → fill the form → Send Order
2. Watch the dashboard (/dashboard): Pending → Processing → Completed
3. Azure Portal → Service Bus → orders queue → Active message count drops
```

### 9a. Queue buffering (slow processing)
```bash
# stop the worker (Ctrl+C), then:
export PROCESS_SECONDS=8
python worker.py
# On the dashboard, click "Generate 20 orders" and watch Active: 20 → 0 slowly
```

### 9b. Competing consumers (multiple workers)
```bash
# open 3 terminals, in EACH:
cd ~/Azure-ServiceBus-OrderSystem && source venv/bin/activate && python worker.py
# generate 50 orders from the dashboard — the 3 workers share the load
```

### 9c. Failure + Dead-Letter Queue
```bash
# stop workers, then run one in fail mode:
export FAIL_MODE=1
python worker.py
# send orders → they are retried, then land in the DLQ (see 10c)
export FAIL_MODE=0   # turn it back off afterwards
```

### 9d. Peek (look without consuming)
```text
Dashboard → Admin controls → "Peek queue"
```

---

## 10. Inspecting the SQLite database (queries)

Open the DB:
```bash
sqlite3 database/orders.db
```
Then run any of these SQL queries:
```sql
-- everything, newest first
SELECT id, customer, product, quantity, status, created_on
FROM orders ORDER BY id DESC LIMIT 20;

-- counts by status
SELECT status, COUNT(*) AS n FROM orders GROUP BY status;

-- average processing time (seconds) for completed orders
SELECT AVG(strftime('%s', processed_on) - strftime('%s', created_on)) AS avg_seconds
FROM orders WHERE status='Completed';

-- only failed orders
SELECT * FROM orders WHERE status='Failed';

-- high-priority orders still waiting
SELECT * FROM orders WHERE priority='High' AND status='Pending';

.quit
```

### 10c. Read the Dead-Letter Queue with Azure CLI
```bash
az servicebus queue show \
  --resource-group $RG --namespace-name $SB_NS --name orders \
  --query 'countDetails.deadLetterMessageCount'
```

---

## 11. Clean up (stops all billing)

```bash
az group delete --name $RG --yes --no-wait
```
