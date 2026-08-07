# Cosmos DB Queries — Add, Read, Update, Delete

**Important concept:** The Cosmos DB **Core (SQL) API query language only does reads (`SELECT`).**
There is **no `INSERT`, `UPDATE`, or `DELETE` statement** like in a relational database.
Writes (create / update / delete) are **point operations** done through the SDK or REST API,
using the item's `id` **and** its **partition key** (here: `category`).

This project uses partition key `/category`.

---

## 1. READ — SQL queries (run these in Data Explorer → "New SQL Query")

Read everything:
```sql
SELECT * FROM c
```

Read newest first:
```sql
SELECT * FROM c ORDER BY c._ts DESC
```

Read one item by id:
```sql
SELECT * FROM c WHERE c.id = "1712345678900"
```

Filter by partition key (category):
```sql
SELECT * FROM c WHERE c.category = "electronics"
```

Filter + projection (only some fields):
```sql
SELECT c.name, c.price FROM c WHERE c.price > 100
```

Count:
```sql
SELECT VALUE COUNT(1) FROM c
```

Aggregate per category:
```sql
SELECT c.category, COUNT(1) AS total
FROM c
GROUP BY c.category
```

---

## 2. ADD (Create) — done via SDK, not SQL

In `server.js`:
```js
await container.items.create({
  id: "1712345678900",
  name: "Laptop",
  category: "electronics",   // partition key
  price: 999
});
```

Equivalent raw REST call (Data Explorer does this under the hood when you click **New Item**):
```json
{
  "id": "1712345678900",
  "name": "Laptop",
  "category": "electronics",
  "price": 999
}
```

---

## 3. UPDATE — read, modify, replace (needs id + partition key)

```js
const { resource: item } = await container.item("1712345678900", "electronics").read();
item.price = 1099;
await container.item("1712345678900", "electronics").replace(item);
```

Partial update (patch) is also supported:
```js
await container.item("1712345678900", "electronics").patch([
  { op: "replace", path: "/price", value: 1099 }
]);
```

---

## 4. DELETE — point delete (needs id + partition key)

```js
await container.item("1712345678900", "electronics").delete();
```

Bulk-style delete by query: first `SELECT` the ids, then delete each one
(Cosmos SQL has no `DELETE FROM ... WHERE`):
```js
const { resources } = await container.items
  .query("SELECT c.id, c.category FROM c WHERE c.price = 0")
  .fetchAll();
for (const r of resources) {
  await container.item(r.id, r.category).delete();
}
```

---

## Quick mapping: HTTP endpoint → Cosmos operation

| Action | Frontend / HTTP        | Cosmos operation                          |
|--------|------------------------|-------------------------------------------|
| Read all | `GET /api/items`     | `SELECT * FROM c`                         |
| Read one | `GET /api/items/:id` | `SELECT * FROM c WHERE c.id=@id`          |
| Add      | `POST /api/items`    | `container.items.create(item)`            |
| Update   | `PUT /api/items/:id` | `.read()` → modify → `.replace(item)`     |
| Delete   | `DELETE /api/items/:id?category=` | `container.item(id, pk).delete()` |
