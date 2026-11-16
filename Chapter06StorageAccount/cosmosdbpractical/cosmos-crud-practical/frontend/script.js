// script.js — talks to the Express API on the same origin (/api/...)
const API = "/api/items";

function showMsg(text, ok = true) {
  const el = document.getElementById("msg");
  el.textContent = text;
  el.className = "msg " + (ok ? "ok" : "err");
  if (text) setTimeout(() => { el.textContent = ""; el.className = "msg"; }, 3000);
}

function esc(s) {
  return String(s ?? "").replace(/[&<>"']/g, c =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

// READ ALL
async function loadItems() {
  const tbody = document.getElementById("tbody");
  tbody.innerHTML = `<tr><td colspan="4" class="empty">Loading…</td></tr>`;
  try {
    const res = await fetch(API);
    const items = await res.json();
    if (!items.length) {
      tbody.innerHTML = `<tr><td colspan="4" class="empty">No items yet. Add one above.</td></tr>`;
      return;
    }
    tbody.innerHTML = items.map(it => `
      <tr>
        <td>${esc(it.name)}</td>
        <td>${esc(it.category)}</td>
        <td>${esc(it.price)}</td>
        <td>
          <div class="rowactions">
            <button class="edit" onclick='startEdit(${JSON.stringify(it)})'>Edit</button>
            <button class="del" onclick="deleteItem('${esc(it.id)}','${esc(it.category)}')">Delete</button>
          </div>
        </td>
      </tr>`).join("");
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="4" class="empty">Error loading items</td></tr>`;
    showMsg("Failed to load: " + e.message, false);
  }
}

// CREATE or UPDATE (form is shared)
async function saveItem() {
  const id = document.getElementById("itemId").value;
  const oldCategory = document.getElementById("oldCategory").value;
  const name = document.getElementById("name").value.trim();
  const category = document.getElementById("category").value.trim();
  const price = document.getElementById("price").value;

  if (!name || !category) return showMsg("Name and Category are required", false);

  try {
    let res;
    if (id) {
      // UPDATE
      res = await fetch(`${API}/${id}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, category, price, oldCategory }),
      });
    } else {
      // CREATE
      res = await fetch(API, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, category, price }),
      });
    }
    if (!res.ok) throw new Error((await res.json()).error || "Request failed");
    showMsg(id ? "Updated!" : "Added!", true);
    resetForm();
    loadItems();
  } catch (e) {
    showMsg(e.message, false);
  }
}

// DELETE
async function deleteItem(id, category) {
  if (!confirm("Delete this item?")) return;
  try {
    const res = await fetch(`${API}/${id}?category=${encodeURIComponent(category)}`, {
      method: "DELETE",
    });
    if (!res.ok) throw new Error((await res.json()).error || "Delete failed");
    showMsg("Deleted!", true);
    loadItems();
  } catch (e) {
    showMsg(e.message, false);
  }
}

// Put a row into the form for editing
function startEdit(it) {
  document.getElementById("itemId").value = it.id;
  document.getElementById("oldCategory").value = it.category;
  document.getElementById("name").value = it.name;
  document.getElementById("category").value = it.category;
  document.getElementById("price").value = it.price;
  document.getElementById("formTitle").textContent = "Edit Item";
  document.getElementById("saveBtn").textContent = "Update";
  document.getElementById("cancelBtn").style.display = "inline-block";
  window.scrollTo({ top: 0, behavior: "smooth" });
}

function resetForm() {
  document.getElementById("itemId").value = "";
  document.getElementById("oldCategory").value = "";
  document.getElementById("name").value = "";
  document.getElementById("category").value = "";
  document.getElementById("price").value = "";
  document.getElementById("formTitle").textContent = "Add Item";
  document.getElementById("saveBtn").textContent = "Add";
  document.getElementById("cancelBtn").style.display = "none";
}

// initial load
loadItems();
