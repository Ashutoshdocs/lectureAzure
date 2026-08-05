/* Azure Service Bus Order System — front-end logic
   Works on both pages; each block only runs if its elements exist. */

// ---------- helpers ----------
const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

async function api(url, opts = {}) {
  const res = await fetch(url, opts);
  return res.json();
}

// animated count-up for any [data-stat] element
function animateTo(el, target) {
  const suffix = el.dataset.suffix || "";
  const from = parseFloat(el.dataset.cur || "0");
  const to = Number(target) || 0;
  if (from === to) { el.textContent = to + suffix; return; }
  const start = performance.now();
  const dur = 500;
  function step(now) {
    const p = Math.min((now - start) / dur, 1);
    const val = from + (to - from) * (0.5 - Math.cos(Math.PI * p) / 2);
    el.textContent = (Number.isInteger(to) ? Math.round(val) : val.toFixed(1)) + suffix;
    if (p < 1) requestAnimationFrame(step);
    else el.dataset.cur = to;
  }
  requestAnimationFrame(step);
}

function paintStats(s) {
  $$("[data-stat]").forEach((el) => {
    const key = el.dataset.stat;
    if (s[key] !== undefined) animateTo(el, s[key]);
  });
}

// ======================================================
//  HOME PAGE — order form
// ======================================================
const sendBtn = $("#sendBtn");
if (sendBtn) {
  sendBtn.addEventListener("click", async () => {
    const payload = {
      customer: $("#customer").value,
      product: $("#product").value,
      quantity: $("#quantity").value,
      price: $("#price").value,
      priority: $("#priority").value,
    };
    sendBtn.classList.add("loading");
    try {
      const r = await api("/api/send", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const toast = $("#toast");
      if (r.ok) {
        toast.innerHTML = `<i class="fa-solid fa-circle-check"></i> Order #${r.order_id} sent to queue`;
        toast.style.color = "#8ff0a6";
      } else {
        toast.innerHTML = `<i class="fa-solid fa-circle-xmark"></i> ${r.error}`;
        toast.style.color = "#ff9a9a";
      }
      toast.classList.add("show");
      setTimeout(() => toast.classList.remove("show"), 3000);
      refreshStats();
    } finally {
      sendBtn.classList.remove("loading");
    }
  });
}

async function refreshStats() {
  try { paintStats(await api("/api/stats")); } catch (e) { /* ignore */ }
}
if ($("[data-stat]") && !$("#orderRows")) {
  refreshStats();
  setInterval(refreshStats, 2500);
}

// ======================================================
//  DASHBOARD
// ======================================================
if ($("#orderRows")) {
  let pieChart, lineChart;
  const queueHistory = [];
  const timeLabels = [];

  function initCharts() {
    const pieCtx = $("#pieChart").getContext("2d");
    pieChart = new Chart(pieCtx, {
      type: "doughnut",
      data: {
        labels: ["Pending", "Processing", "Completed", "Failed"],
        datasets: [{
          data: [0, 0, 0, 0],
          backgroundColor: ["#5b8dff", "#f7b733", "#22c55e", "#ef4444"],
          borderColor: "#171a35", borderWidth: 3,
        }],
      },
      options: {
        plugins: { legend: { labels: { color: "#a3a8cf" } } },
        cutout: "62%",
      },
    });

    const lineCtx = $("#lineChart").getContext("2d");
    const grad = lineCtx.createLinearGradient(0, 0, 0, 220);
    grad.addColorStop(0, "rgba(123,47,247,.5)");
    grad.addColorStop(1, "rgba(123,47,247,0)");
    lineChart = new Chart(lineCtx, {
      type: "line",
      data: {
        labels: timeLabels,
        datasets: [{
          label: "Active messages",
          data: queueHistory,
          borderColor: "#8a5cff", backgroundColor: grad,
          fill: true, tension: 0.35, pointRadius: 0, borderWidth: 2,
        }],
      },
      options: {
        plugins: { legend: { labels: { color: "#a3a8cf" } } },
        scales: {
          x: { ticks: { color: "#7c81a8" }, grid: { color: "rgba(255,255,255,.05)" } },
          y: { beginAtZero: true, ticks: { color: "#7c81a8" }, grid: { color: "rgba(255,255,255,.05)" } },
        },
      },
    });
  }

  const statusBadge = (s) => `<span class="badge-status s-${s}">${s}</span>`;

  const prevStatus = {};
  function renderTable(orders) {
    const body = $("#orderRows");
    if (!orders.length) {
      body.innerHTML = `<tr><td colspan="7" class="text-center empty-row">No orders yet — send one from the home page.</td></tr>`;
      return;
    }
    body.innerHTML = orders.map((o) => {
      const changed = prevStatus[o.id] && prevStatus[o.id] !== o.status;
      prevStatus[o.id] = o.status;
      return `<tr class="${changed ? "flash" : ""}">
        <td>#${o.id}</td><td>${o.customer}</td><td>${o.product}</td>
        <td>${o.quantity}</td><td>${o.priority}</td>
        <td>${statusBadge(o.status)}</td>
        <td class="text-muted">${(o.created_on || "").replace("T", " ")}</td>
      </tr>`;
    }).join("");
  }

  async function tick() {
    // stats + charts
    try {
      const s = await api("/api/stats");
      paintStats(s);
      if (pieChart) {
        pieChart.data.datasets[0].data = [s.pending, s.processing, s.completed, s.failed];
        pieChart.update("none");
      }
    } catch (e) {}

    // orders table
    try { renderTable((await api("/api/orders")).orders); } catch (e) {}

    // live queue metrics + line chart
    try {
      const q = await api("/api/queue");
      if (q.ok) {
        $("#q-ns").textContent = q.namespace;
        $("#q-name").textContent = q.queue;
        $("#q-active").textContent = q.active;
        $("#q-dlq").textContent = q.dead_letter;
        $("#q-sched").textContent = q.scheduled;
        const t = new Date().toLocaleTimeString();
        queueHistory.push(q.active); timeLabels.push(t);
        if (queueHistory.length > 30) { queueHistory.shift(); timeLabels.shift(); }
        if (lineChart) lineChart.update("none");
      } else {
        $("#q-active").textContent = "n/a";
      }
    } catch (e) {}
  }

  // admin actions
  $$(".btn-admin").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const action = btn.dataset.action;
      const original = btn.innerHTML;
      btn.disabled = true;
      try {
        if (action === "generate") {
          btn.innerHTML = `<i class="fa-solid fa-circle-notch fa-spin"></i> Generating…`;
          await api("/api/generate", {
            method: "POST", headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ count: 20 }),
          });
        } else if (action === "retry") {
          await api("/api/retry", { method: "POST" });
        } else if (action === "clear") {
          if (confirm("Delete all orders from the database?"))
            await api("/api/clear", { method: "POST" });
        } else if (action === "peek") {
          const r = await api("/api/peek");
          const out = $("#peekOut");
          out.classList.remove("d-none");
          out.textContent = r.ok
            ? (r.messages.length ? JSON.stringify(r.messages, null, 2) : "Queue is empty — nothing to peek.")
            : "Error: " + r.error;
        }
      } finally {
        btn.innerHTML = original;
        btn.disabled = false;
        tick();
      }
    });
  });

  initCharts();
  tick();
  setInterval(tick, 2000);
}
