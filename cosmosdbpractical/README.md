# Cosmos DB CRUD Practical

A complete hands-on practical: a **browser frontend** you hit from any browser, a
**Node.js + Express API**, and **Azure Cosmos DB (Core / SQL API)** as the database.
Anything you add/edit/delete in the UI is reflected live in Cosmos DB.
Deployed on an **Azure Linux (Ubuntu) VM**.

```
Browser  ──►  Linux VM (Express :3000)  ──►  Azure Cosmos DB
  (UI)          serves frontend + API          PracticalDB / Items
```

## Directory structure

```
cosmos-crud-practical/
├── README.md                     ← you are here
├── backend/
│   ├── server.js                 ← Express API + serves the frontend + Cosmos CRUD
│   ├── package.json              ← dependencies (@azure/cosmos, express, dotenv)
│   └── .env.example              ← copy to .env and add your Cosmos keys
├── frontend/
│   ├── index.html                ← the page you open in the browser
│   ├── style.css                 ← styling
│   └── script.js                 ← calls the API (fetch) for add/read/update/delete
├── queries/
│   └── cosmos-queries.md         ← all Cosmos queries for ADD/READ/UPDATE/DELETE
└── deploy/
    └── deploy-steps.md           ← step-by-step Linux VM deployment
```

## What each CRUD action does

| UI action | HTTP endpoint                     | Cosmos operation                       |
|-----------|-----------------------------------|----------------------------------------|
| List      | `GET /api/items`                  | `SELECT * FROM c`                      |
| Add       | `POST /api/items`                 | `container.items.create(item)`         |
| Edit      | `PUT /api/items/:id`              | read → modify → `replace(item)`        |
| Delete    | `DELETE /api/items/:id?category=` | `container.item(id, pk).delete()`      |

Data model (one item):
```json
{ "id": "1712345678900", "name": "Laptop", "category": "electronics", "price": 999 }
```
Partition key = `/category`.

## Run locally (before the VM, optional)

```bash
cd backend
npm install
cp .env.example .env      # add your COSMOS_ENDPOINT + COSMOS_KEY
npm start
# open http://localhost:3000
```

## Deploy to the Linux VM

Follow **`deploy/deploy-steps.md`** — it covers creating the Cosmos account,
creating the Ubuntu VM, installing Node, copying files, opening port 3000,
and keeping the app alive with PM2.

## Cosmos queries

See **`queries/cosmos-queries.md`** for every add / read / update / delete query
and how to run the read queries in the Azure **Data Explorer**.

## Key thing to remember

Cosmos DB's SQL API query language is **read-only** (`SELECT` only).
Add / update / delete are **point operations via the SDK** using `id` + partition key —
there is no `INSERT` / `UPDATE` / `DELETE` statement.
