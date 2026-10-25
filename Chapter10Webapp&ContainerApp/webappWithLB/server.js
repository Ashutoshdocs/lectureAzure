const express = require("express");
const os = require("os");

const app = express();
const PORT = process.env.PORT || process.env.WEBSITES_PORT || 8080;

// ---- Identity of this instance -------------------------------------------
const instance = process.env.WEBSITE_INSTANCE_ID || os.hostname();
const shortId = instance.slice(0, 8).toUpperCase();
const siteName = process.env.WEBSITE_SITE_NAME || "local";
const region = process.env.REGION_NAME || "local";
const sku = process.env.WEBSITE_SKU || "docker";
const version = process.env.APP_VERSION || "v1";
const startedAt = new Date();
let hits = 0;

// Two-colour gradient per instance (same function runs in the browser)
const palettes = [
  ["#6a11cb", "#2575fc"], ["#ff0844", "#ffb199"], ["#00c6fb", "#005bea"],
  ["#f857a6", "#ff5858"], ["#43e97b", "#38f9d7"], ["#fa709a", "#fee140"],
  ["#30cfd0", "#330867"], ["#ff9a9e", "#fad0c4"], ["#4facfe", "#00f2fe"],
  ["#f093fb", "#f5576c"]
];
const paletteFor = (id) => {
  let sum = 0;
  for (let i = 0; i < id.length; i++) sum += id.charCodeAt(i);
  return palettes[sum % palettes.length];
};
const [c1, c2] = paletteFor(instance);

// ---- Middleware ----------------------------------------------------------
app.disable("x-powered-by");
app.use((req, res, next) => {
  // Never cache: every request must reach the load balancer
  res.set("Cache-Control", "no-store, no-cache, must-revalidate");
  res.set("X-Instance-Id", shortId);
  if (req.path !== "/health") hits++;
  next();
});

const info = () => ({
  instanceId: instance,
  shortId,
  hostname: os.hostname(),
  site: siteName,
  region,
  sku,
  version,
  hitsOnThisInstance: hits,
  uptimeSeconds: Math.round((Date.now() - startedAt) / 1000),
  node: process.version,
  time: new Date().toISOString()
});

// ---- API -----------------------------------------------------------------
app.get("/health", (req, res) => res.status(200).send("OK"));
app.get("/hostname", (req, res) => res.type("text").send(os.hostname()));
app.get("/instance", (req, res) => res.type("text").send(shortId));
app.get(["/info", "/api/info"], (req, res) => res.json(info()));

// ---- Page ----------------------------------------------------------------
app.get("/", (req, res) => {
  const i = info();
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>Web App + Load Balancer</title>
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@500;600&display=swap" rel="stylesheet" />
<style>
*{margin:0;padding:0;box-sizing:border-box}
:root{--c1:${c1};--c2:${c2};--glass:rgba(255,255,255,.12);--line:rgba(255,255,255,.22)}
body{min-height:100vh;font-family:Inter,system-ui,sans-serif;color:#fff;padding:32px 16px;
  background:linear-gradient(135deg,var(--c1),var(--c2));background-size:200% 200%;
  animation:drift 18s ease infinite;display:flex;justify-content:center;align-items:flex-start}
@keyframes drift{0%,100%{background-position:0% 50%}50%{background-position:100% 50%}}
.wrap{width:100%;max-width:1040px;display:grid;grid-template-columns:1fr 1fr;gap:20px}
.panel{background:var(--glass);backdrop-filter:blur(22px) saturate(160%);-webkit-backdrop-filter:blur(22px) saturate(160%);
  border:1px solid var(--line);border-radius:24px;padding:32px;box-shadow:0 24px 60px rgba(0,0,0,.25);
  animation:rise .7s cubic-bezier(.2,.8,.2,1) both}
.panel:nth-child(2){animation-delay:.1s}
@keyframes rise{from{opacity:0;transform:translateY(24px)}to{opacity:1;transform:none}}
.badge{display:inline-flex;align-items:center;gap:8px;font-size:12px;font-weight:600;letter-spacing:.08em;
  text-transform:uppercase;padding:7px 14px;border-radius:999px;background:rgba(255,255,255,.18);border:1px solid var(--line)}
.dot{width:9px;height:9px;border-radius:50%;background:#2ecc71;animation:pulse 1.8s infinite}
@keyframes pulse{0%{box-shadow:0 0 0 0 rgba(46,204,113,.6)}70%{box-shadow:0 0 0 12px rgba(46,204,113,0)}100%{box-shadow:0 0 0 0 rgba(46,204,113,0)}}
h1{font-size:30px;font-weight:800;letter-spacing:-.02em;margin:20px 0 4px}
.sub{opacity:.85;font-size:15px;margin-bottom:24px}
.label{font-size:11px;font-weight:600;letter-spacing:.1em;text-transform:uppercase;opacity:.7;margin-bottom:6px}
.chip{font-family:"JetBrains Mono",monospace;font-size:44px;font-weight:600;letter-spacing:.04em;
  padding:16px 24px;border-radius:18px;background:rgba(0,0,0,.22);border:1px solid var(--line);text-align:center;margin-bottom:22px}
.stats{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.stat{background:rgba(255,255,255,.1);border:1px solid rgba(255,255,255,.16);border-radius:14px;padding:12px 14px}
.stat.full{grid-column:1/-1}
.val{font-family:"JetBrains Mono",monospace;font-size:14px;font-weight:600;word-break:break-all}
h2{font-size:20px;font-weight:700;margin-bottom:4px}
.muted{opacity:.8;font-size:14px;margin-bottom:18px;line-height:1.5}
.controls{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:18px}
button,select{font:inherit;font-weight:600;font-size:14px;color:#fff;border-radius:12px;padding:10px 16px;
  border:1px solid var(--line);background:rgba(0,0,0,.25);cursor:pointer}
button.primary{background:#fff;color:#111}
button:disabled{opacity:.5;cursor:wait}
.bars{display:flex;flex-direction:column;gap:10px;min-height:120px}
.bar{display:grid;grid-template-columns:96px 1fr 44px;align-items:center;gap:10px;font-family:"JetBrains Mono",monospace;font-size:13px}
.track{height:22px;border-radius:8px;background:rgba(0,0,0,.2);overflow:hidden}
.fill{height:100%;border-radius:8px;transition:width .3s ease}
.me{outline:2px solid #fff;outline-offset:2px}
.summary{margin-top:16px;font-size:14px;opacity:.9}
.empty{opacity:.7;font-size:14px;padding:30px 0;text-align:center}
.log{margin-top:14px;font-family:"JetBrains Mono",monospace;font-size:12px;max-height:120px;overflow:auto;
  background:rgba(0,0,0,.2);border-radius:10px;padding:10px;display:none}
footer{grid-column:1/-1;text-align:center;font-size:13px;opacity:.8}
@media(max-width:820px){.wrap{grid-template-columns:1fr}.chip{font-size:32px}}
</style>
</head>
<body>
<div class="wrap">

  <section class="panel">
    <span class="badge"><span class="dot"></span> Live · ${i.version}</span>
    <h1>Azure App Service</h1>
    <p class="sub">Scale-out behind the built-in load balancer</p>

    <div class="label">This page was served by</div>
    <div class="chip">${shortId}</div>

    <div class="stats">
      <div class="stat full"><div class="label">Instance ID</div><div class="val">${i.instanceId}</div></div>
      <div class="stat"><div class="label">Hostname</div><div class="val">${i.hostname}</div></div>
      <div class="stat"><div class="label">Region</div><div class="val">${i.region}</div></div>
      <div class="stat"><div class="label">Site</div><div class="val">${i.site}</div></div>
      <div class="stat"><div class="label">SKU</div><div class="val">${i.sku}</div></div>
      <div class="stat"><div class="label">Hits here</div><div class="val">${i.hitsOnThisInstance}</div></div>
      <div class="stat"><div class="label">Uptime</div><div class="val">${i.uptimeSeconds}s</div></div>
      <div class="stat full"><div class="label">Server time</div><div class="val" id="clock">${new Date().toString()}</div></div>
    </div>
  </section>

  <section class="panel">
    <h2>⚖️ Load balancer test</h2>
    <p class="muted">Sends requests to <code>/api/info</code> and counts which instance answered each one.
      With ARR affinity off and several instances, traffic spreads across all of them.</p>

    <div class="controls">
      <select id="count">
        <option value="20">20 requests</option>
        <option value="50" selected>50 requests</option>
        <option value="100">100 requests</option>
      </select>
      <button class="primary" id="run">Run test</button>
      <button id="reset">Reset</button>
    </div>

    <div class="bars" id="bars"><div class="empty">Press <b>Run test</b> to hit the load balancer.</div></div>
    <div class="summary" id="summary"></div>
    <div class="log" id="log"></div>
  </section>

  <footer>Refresh the page to land on a different instance · Endpoints: /api/info · /instance · /hostname · /health</footer>
</div>

<script>
const ME = ${JSON.stringify(shortId)};
const PALETTES = ${JSON.stringify(palettes)};
const colorFor = id => { let s = 0; for (const ch of id) s += ch.charCodeAt(0); const p = PALETTES[s % PALETTES.length]; return "linear-gradient(90deg," + p[0] + "," + p[1] + ")"; };

const clock = document.getElementById("clock");
setInterval(() => clock.textContent = new Date().toString(), 1000);

let tally = {}, total = 0, errors = 0;
const bars = document.getElementById("bars"), summary = document.getElementById("summary"), log = document.getElementById("log");
const runBtn = document.getElementById("run");

// The full instance id hashes differently from the short one, so colour by the short id
// and match the first panel by giving "this" instance a white outline instead.
function render() {
  const ids = Object.keys(tally).sort((a, b) => tally[b] - tally[a]);
  if (!ids.length) { bars.innerHTML = '<div class="empty">Press <b>Run test</b> to hit the load balancer.</div>'; summary.textContent = ""; return; }
  const max = Math.max(...ids.map(k => tally[k]));
  bars.innerHTML = ids.map(id =>
    '<div class="bar"><span>' + id + (id === ME ? " ★" : "") + '</span>' +
    '<div class="track' + (id === ME ? " me" : "") + '"><div class="fill" style="width:' + (tally[id] / max * 100) + '%;background:' + colorFor(id) + '"></div></div>' +
    '<span>' + tally[id] + '</span></div>').join("");
  summary.textContent = total + " requests · " + ids.length + " instance" + (ids.length > 1 ? "s" : "") + " answered" + (errors ? " · " + errors + " errors" : "") + " · ★ = served this page";
}

async function run() {
  const n = +document.getElementById("count").value;
  runBtn.disabled = true; log.style.display = "block";
  const jobs = Array.from({ length: n }, (_, k) =>
    fetch("/api/info?r=" + Date.now() + "-" + k, { cache: "no-store" })
      .then(r => r.json())
      .then(d => { tally[d.shortId] = (tally[d.shortId] || 0) + 1; total++; log.textContent = "#" + total + " → " + d.shortId + "\\n" + log.textContent; render(); })
      .catch(() => { errors++; render(); }));
  await Promise.all(jobs);
  runBtn.disabled = false;
}

runBtn.onclick = run;
document.getElementById("reset").onclick = () => { tally = {}; total = 0; errors = 0; log.textContent = ""; log.style.display = "none"; render(); };
</script>
</body>
</html>`);
});

app.listen(PORT, () => console.log(`Instance ${shortId} listening on ${PORT}`));
