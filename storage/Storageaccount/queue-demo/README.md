# Azure VM + Storage Queue Demo

A hands-on demo that proves how an Azure Storage Queue decouples a **producer**
from a **consumer (worker)**, and shows every important queue behaviour live:
buffering, visibility timeout, crash recovery, competing consumers and poison messages.

```
 ┌──────────────────┐   send_message    ┌─────────────────────────────┐   receive / delete   ┌──────────────────────┐
 │  Your laptop     │ ────────────────▶ │  Storage Account            │ ◀──────────────────  │  Azure VM (Ubuntu)   │
 │  PRODUCER        │                   │   queue: orders             │                      │  WORKER              │
 │  (az login)      │                   │   queue: orders-poison      │                      │  (managed identity)  │
 └──────────────────┘                   └─────────────────────────────┘                      └──────────────────────┘
          RBAC: Storage Queue Data Contributor for both — no keys or connection strings.
```

## Files

| File | Purpose |
|---|---|
| `deploy.sh` | Creates RG, storage account, 2 queues, VM with managed identity, RBAC, copies the script to the VM |
| `cloud-init.yaml` | Installs Python + Azure SDK on the VM at first boot |
| `queue_demo.py` | `send`, `worker`, `peek`, `stats`, `clear` |
| `cleanup.sh` | Deletes everything |

## Prerequisites

- Azure CLI, logged in: `az login` (and `az account set -s <subscription>`)
- Python 3.9+ locally: `pip install azure-storage-queue azure-identity`
- Permission to create role assignments (Owner or User Access Administrator on the subscription/RG)

## Deploy (~5 min)

```bash
chmod +x deploy.sh cleanup.sh
./deploy.sh                       # optional: LOCATION=eastus VM_SIZE=Standard_B2s ./deploy.sh
source .env                       # sets STORAGE_ACCOUNT, QUEUE_NAME, VM_IP
```

Open two terminals:
- **Terminal A (laptop – producer):** `source .env`
- **Terminal B (VM – worker):** `ssh azureuser@$VM_IP` → the alias `qd` runs the script there

---

## How a queue works (the 30-second version)

1. **Send** – a producer adds a message (up to 64 KB, lives up to 7 days by default).
2. **Receive** – a worker takes a message. It is **not removed**; it becomes **invisible** for the
   *visibility timeout* and the worker gets a **pop receipt**.
3. **Delete** – when processing succeeds, the worker deletes it using id + pop receipt.
4. If the worker crashes or fails, it never deletes → after the timeout the message **reappears**
   and `dequeue_count` goes up. This gives **at-least-once delivery** — your processing should be idempotent.

---

## Demo scenarios

### 1. Send and peek — messages are stored durably
```bash
# Terminal A
python queue_demo.py send --count 5
python queue_demo.py peek
python queue_demo.py peek        # run again: same messages, still there
```
✅ Proves: peek reads without removing. Messages sit safely in the queue.

### 2. Decoupling — producer and worker on different machines
```bash
# Terminal B (VM)
qd worker
```
Watch the VM pick up and delete the 5 orders your laptop sent. Then send more from Terminal A while
the worker runs — they're processed within seconds.
✅ Proves: producer and consumer never talk to each other directly; the queue sits between them.

### 3. Buffering / load levelling — the worker can be down
```bash
# Terminal B: Ctrl+C to stop the worker
# Terminal A
python queue_demo.py send --count 20
python queue_demo.py stats        # ~20 waiting
# Terminal B
qd worker                         # drains the backlog at its own pace
```
✅ Proves: nothing is lost while the consumer is offline; spikes are absorbed.

### 4. Visibility timeout & crash recovery
```bash
# Terminal A
python queue_demo.py send --count 1
# Terminal B — take the message and "crash" without deleting it
qd worker --crash --visibility 20
# Terminal A — immediately
python queue_demo.py peek         # shows no visible message, but total count = 1 (it's hidden)
# wait ~20 seconds
python queue_demo.py peek         # it's back, dequeue_count=1 → next receive makes it 2
# Terminal B
qd worker                         # processes it: RECV ... dequeue_count=2
```
✅ Proves: a failed worker doesn't lose work — the message automatically becomes available again.

### 5. Competing consumers — scale out
```bash
# Terminal B (VM):    qd worker --work 3
# Terminal A (laptop, a second window):
python queue_demo.py worker --work 3
# Terminal A (another window):
python queue_demo.py send --count 20
```
Each log line shows the host name. The two workers split the messages and **no message is
processed by both** (while it's invisible to one, the other can't see it).
✅ Proves: you scale throughput by adding workers, with no coordination code.

### 6. Poison messages — handling messages that always fail
```bash
# Terminal A
python queue_demo.py send --count 2 --poison
# Terminal B
qd worker --visibility 10 --max-dequeue 3
```
The malformed message fails (`FAIL ... JSONDecodeError`), reappears every 10 s, and after 3 failed
attempts is moved to `orders-poison`.
```bash
python queue_demo.py stats        # orders: 0, orders-poison: 1
```
✅ Proves: bad messages don't block the queue forever; they're parked for investigation.

### Bonus: delayed delivery
```bash
python queue_demo.py send --count 1 --delay 30   # invisible for 30 s, then any worker can get it
```

---

## Useful checks in the Azure Portal
Storage account → **Queues** → `orders` shows messages, insertion time, expiry and dequeue count.
Storage account → **Access control (IAM)** shows the two role assignments.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `AuthorizationPermissionMismatch` | RBAC propagation — wait 1–5 minutes and retry |
| `DefaultAzureCredential failed` locally | Run `az login` |
| VM size not available in region | `VM_SIZE=Standard_B2s ./deploy.sh` or another `LOCATION` |
| Can't SSH | Your network may block port 22; the NSG created by `az vm create` allows it |

## Production notes
- Restrict the SSH rule to your IP, or remove the public IP and use Azure Bastion.
- Long jobs: call `update_message` to extend the visibility timeout before it expires.
- Make processing idempotent (at-least-once delivery means duplicates are possible).
- Need ordering, sessions, topics, or messages > 64 KB? Look at Azure Service Bus.

## Cleanup (do this — the VM costs money while running)
```bash
./cleanup.sh
```
