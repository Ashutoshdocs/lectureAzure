# Deploy on an Azure Linux VM (Ubuntu)

These steps assume an **Ubuntu 22.04/24.04** VM. Adjust for other distros.

---

## STEP 1 — Create the Cosmos DB account (Azure Portal)

1. Portal → **Create a resource** → **Azure Cosmos DB** → **Azure Cosmos DB for NoSQL** (Core/SQL API).
2. Fill: Resource Group, Account Name, Region → **Review + Create**.
3. After it deploys → open the account → **Settings → Keys**.
   Copy the **URI** and the **PRIMARY KEY**. You'll paste these into `.env`.
4. (Optional — the app auto-creates them) You can pre-create:
   Database `PracticalDB`, Container `Items`, Partition key `/category`.

---

## STEP 2 — Create the Linux VM (Azure Portal)

1. Portal → **Create a resource** → **Virtual Machine**.
2. Image: **Ubuntu Server 22.04 LTS**, Size: **B1s** is fine for a practical.
3. Authentication: **SSH public key** (recommended) or password.
4. **Networking / Inbound ports:** allow **SSH (22)** and **HTTP (80)**.
   We'll also open our app port **3000** in Step 6.
5. Create → note the VM's **Public IP address**.

---

## STEP 3 — SSH into the VM

```bash
ssh azureuser@<VM_PUBLIC_IP>
```

---

## STEP 4 — Install Node.js on the VM

```bash
sudo apt update
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
node -v      # verify (should print v20.x)
npm -v
```

---

## STEP 5 — Copy the project to the VM

Option A — copy from your machine with scp (run locally):
```bash
scp -r cosmos-crud-practical azureuser@<VM_PUBLIC_IP>:~/
```

Option B — clone from git (if you pushed it to a repo):
```bash
git clone <your-repo-url> cosmos-crud-practical
```

Then on the VM:
```bash
cd ~/cosmos-crud-practical/backend
npm install
```

Create the `.env` file with your Cosmos values:
```bash
cp .env.example .env
nano .env        # paste your COSMOS_ENDPOINT and COSMOS_KEY, save (Ctrl+O, Enter, Ctrl+X)
```

---

## STEP 6 — Open the app port (Azure Network Security Group)

Portal → your VM → **Networking** → **Add inbound port rule**:
- Destination port ranges: **3000**
- Protocol: **TCP**
- Action: **Allow**
- Name: **allow-3000**

(If you serve on port 80 instead, open 80 — see Step 8 note.)

---

## STEP 7 — Run the app

Quick test:
```bash
cd ~/cosmos-crud-practical/backend
npm start
```
You should see:
```
Cosmos ready: PracticalDB / Items
Server running on http://0.0.0.0:3000
```

Now open a browser:
```
http://<VM_PUBLIC_IP>:3000
```
Add an item → it appears in **Cosmos DB → Data Explorer → PracticalDB → Items**.

Press `Ctrl+C` to stop.

---

## STEP 8 — Keep it running with PM2 (survives reboots / disconnects)

```bash
sudo npm install -g pm2
cd ~/cosmos-crud-practical/backend
pm2 start server.js --name cosmos-crud
pm2 save
pm2 startup     # run the command it prints (adds a systemd boot service)
pm2 logs cosmos-crud    # view logs
```

Useful PM2 commands:
```bash
pm2 restart cosmos-crud
pm2 stop cosmos-crud
pm2 list
```

> **Serve on port 80 (no :3000 in the URL):** either set `PORT=80` in `.env`
> and run PM2 with sudo, OR install nginx as a reverse proxy:
> `sudo apt install -y nginx`, then proxy `location / { proxy_pass http://localhost:3000; }`.

---

## STEP 9 — Verify end-to-end

1. Browser → `http://<VM_PUBLIC_IP>:3000`
2. Add / Edit / Delete items in the UI.
3. Azure Portal → Cosmos DB → **Data Explorer** → run `SELECT * FROM c` — the same data is there.

Done. Your frontend writes/reads live from Cosmos DB, hosted on a Linux VM.
