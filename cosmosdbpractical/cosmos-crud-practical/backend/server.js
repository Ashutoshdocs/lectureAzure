// server.js — Express API + static frontend, backed by Azure Cosmos DB (Core / SQL API)
require("dotenv").config();

const express = require("express");
const path = require("path");
const { CosmosClient } = require("@azure/cosmos");

// ---------- Config (from .env) ----------
const {
  COSMOS_ENDPOINT,
  COSMOS_KEY,
  COSMOS_DATABASE = "PracticalDB",
  COSMOS_CONTAINER = "Items",
  PORT = 3000,
} = process.env;

if (!COSMOS_ENDPOINT || !COSMOS_KEY) {
  console.error("Missing COSMOS_ENDPOINT or COSMOS_KEY in .env");
  process.exit(1);
}

// ---------- Cosmos client ----------
const client = new CosmosClient({ endpoint: COSMOS_ENDPOINT, key: COSMOS_KEY });
let container; // set after init

// Create DB + container if they don't exist. Partition key = /category
async function initCosmos() {
  const { database } = await client.databases.createIfNotExists({ id: COSMOS_DATABASE });
  const { container: c } = await database.containers.createIfNotExists({
    id: COSMOS_CONTAINER,
    partitionKey: { paths: ["/category"] },
  });
  container = c;
  console.log(`Cosmos ready: ${COSMOS_DATABASE} / ${COSMOS_CONTAINER}`);
}

// ---------- App ----------
const app = express();
app.use(express.json());
// Serve the frontend (../frontend) as static files
app.use(express.static(path.join(__dirname, "..", "frontend")));

// health check
app.get("/api/health", (req, res) => res.json({ ok: true }));

// READ ALL — SQL query: SELECT * FROM c
app.get("/api/items", async (req, res) => {
  try {
    const { resources } = await container.items
      .query("SELECT * FROM c ORDER BY c._ts DESC")
      .fetchAll();
    res.json(resources);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// READ ONE — SQL query: SELECT * FROM c WHERE c.id = @id
app.get("/api/items/:id", async (req, res) => {
  try {
    const { resources } = await container.items
      .query({
        query: "SELECT * FROM c WHERE c.id = @id",
        parameters: [{ name: "@id", value: req.params.id }],
      })
      .fetchAll();
    if (!resources.length) return res.status(404).json({ error: "Not found" });
    res.json(resources[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// CREATE — point write via SDK (Cosmos SQL has no INSERT statement)
app.post("/api/items", async (req, res) => {
  try {
    const { name, category, price } = req.body;
    if (!name || !category) {
      return res.status(400).json({ error: "name and category are required" });
    }
    const item = {
      id: Date.now().toString(),      // simple unique id
      name,
      category,                        // partition key
      price: Number(price) || 0,
      createdAt: new Date().toISOString(),
    };
    const { resource } = await container.items.create(item);
    res.status(201).json(resource);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// UPDATE — read then replace (needs id + partition key)
app.put("/api/items/:id", async (req, res) => {
  try {
    const { name, category, price, oldCategory } = req.body;
    // partition key value needed to locate the item; frontend sends the current category
    const pk = oldCategory || category;
    const { resource: existing } = await container.item(req.params.id, pk).read();
    if (!existing) return res.status(404).json({ error: "Not found" });

    const updated = {
      ...existing,
      name: name ?? existing.name,
      category: category ?? existing.category,
      price: price !== undefined ? Number(price) : existing.price,
      updatedAt: new Date().toISOString(),
    };

    // If the partition key (category) changed, delete old + create new
    if (updated.category !== existing.category) {
      await container.item(req.params.id, existing.category).delete();
      const { resource } = await container.items.create(updated);
      return res.json(resource);
    }

    const { resource } = await container.item(req.params.id, pk).replace(updated);
    res.json(resource);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE — point delete via SDK (needs id + partition key)
app.delete("/api/items/:id", async (req, res) => {
  try {
    const pk = req.query.category; // frontend passes ?category=<partitionKey>
    if (!pk) return res.status(400).json({ error: "category query param required" });
    await container.item(req.params.id, pk).delete();
    res.json({ deleted: req.params.id });
  } catch (err) {
    if (err.code === 404) return res.status(404).json({ error: "Not found" });
    res.status(500).json({ error: err.message });
  }
});

// ---------- Start ----------
initCosmos()
  .then(() => {
    app.listen(PORT, "0.0.0.0", () =>
      console.log(`Server running on http://0.0.0.0:${PORT}`)
    );
  })
  .catch((err) => {
    console.error("Failed to init Cosmos:", err.message);
    process.exit(1);
  });
