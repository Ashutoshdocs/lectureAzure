// Azure App Service autoscale demo
// - Every instance renders a page with its own color/name derived from its instance ID
// - /burn?seconds=N makes THIS instance busy for N seconds (capped) so autoscale can kick in
// - /stop ends the burn immediately on whichever instance receives it
const http = require('http');
const os = require('os');
const crypto = require('crypto');
const { Worker } = require('worker_threads');

const PORT = process.env.PORT || 8080;
const INSTANCE_ID = process.env.WEBSITE_INSTANCE_ID || os.hostname();
const SHORT_ID = INSTANCE_ID.slice(0, 10);
const STARTED = new Date();
const MAX_BURN_SECONDS = 120; // safety cap per request

const NAMES = ['Aurora', 'Ember', 'Lagoon', 'Meadow', 'Nebula', 'Saffron', 'Glacier', 'Orchid'];
const h = crypto.createHash('sha256').update(INSTANCE_ID).digest();
const VARIANT = {
  name: NAMES[h[0] % NAMES.length],
  hue: h.readUInt16BE(1) % 360,
};

// ---------- CPU burner (safe, time-boxed) ----------
let burnUntil = 0;
let workers = [];
const SPIN = 'while (true) { Math.sqrt(Math.random() * 1e9); }';

function startBurn(seconds) {
  const sec = Math.min(Math.max(parseInt(seconds, 10) || 60, 1), MAX_BURN_SECONDS);
  burnUntil = Math.max(burnUntil, Date.now() + sec * 1000);
  if (workers.length === 0) {
    const n = os.cpus().length;
    for (let i = 0; i < n; i++) workers.push(new Worker(SPIN, { eval: true }));
  }
  return sec;
}
function stopBurn() {
  burnUntil = 0;
  workers.forEach((w) => w.terminate());
  workers = [];
}
// Watchdog: always stop spinning once the deadline passes
setInterval(() => { if (workers.length && Date.now() > burnUntil) stopBurn(); }, 1000);

function info() {
  return {
    instanceId: INSTANCE_ID,
    shortId: SHORT_ID,
    variant: VARIANT.name,
    hue: VARIANT.hue,
    hostname: os.hostname(),
    cpus: os.cpus().length,
    startedAt: STARTED.toISOString(),
    uptimeSec: Math.round(process.uptime()),
    burning: workers.length > 0,
    burnSecondsLeft: workers.length ? Math.max(0, Math.round((burnUntil - Date.now()) / 1000)) : 0,
    loadAvg1m: os.loadavg()[0].toFixed(2),
  };
}

function page() {
  const i = info();
  return `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Instance ${i.variant}</title>
<style>
  :root { --h: ${i.hue}; }
  body { margin:0; font-family: system-ui, sans-serif; color:#fff;
         background: linear-gradient(135deg, hsl(var(--h) 70% 30%), hsl(calc(var(--h) + 40) 70% 18%)); min-height:100vh; }
  main { max-width: 860px; margin: 0 auto; padding: 32px 16px; }
  h1 { font-size: clamp(42px, 9vw, 88px); margin: 0; letter-spacing: -2px; }
  .tag { opacity:.8; font-size: 14px; text-transform: uppercase; letter-spacing: 2px; }
  .card { background: rgba(0,0,0,.25); border-radius: 14px; padding: 18px; margin-top: 20px; }
  code { background: rgba(255,255,255,.15); padding: 2px 6px; border-radius: 6px; }
  table { width:100%; border-collapse: collapse; }
  td { padding: 6px 4px; border-bottom: 1px solid rgba(255,255,255,.12); font-size: 14px; }
  .dot { display:inline-block; width:12px; height:12px; border-radius:50%; margin-right:8px; vertical-align:middle; }
  button { background:#fff; color:#111; border:0; border-radius:8px; padding:8px 14px; font-weight:600; cursor:pointer; margin-right:8px; }
  .new { animation: flash 1.5s ease 3; }
  @keyframes flash { 50% { background: rgba(255,255,0,.35); } }
</style></head>
<body><main>
  <div class="tag">This page was served by instance</div>
  <h1>${i.variant}</h1>
  <p>Instance ID <code>${i.shortId}…</code> · host <code>${i.hostname}</code> · started ${i.startedAt}</p>
  <p>CPU burning: <b>${i.burning ? 'YES (' + i.burnSecondsLeft + 's left)' : 'no'}</b> · load ${i.loadAvg1m} · ${i.cpus} vCPU</p>
  <p><button onclick="location.reload()">Reload page</button>
     <button id="auto">Auto-reload: off</button></p>

  <div class="card">
    <b>Live view — instances answering right now</b>
    <p style="font-size:13px;opacity:.8">Polls <code>/api/whoami</code> every 1.5s. New instances flash when they appear.</p>
    <table id="tbl"></table>
  </div>
</main>
<script>
  const seen = {};
  async function poll() {
    try {
      const r = await fetch('/api/whoami?t=' + Date.now(), { cache: 'no-store' });
      const d = await r.json();
      const isNew = !seen[d.instanceId];
      seen[d.instanceId] = Object.assign(seen[d.instanceId] || { hits: 0 }, d, { last: new Date() });
      seen[d.instanceId].hits++;
      render(isNew ? d.instanceId : null);
    } catch (e) {}
  }
  function render(newId) {
    const rows = Object.values(seen).map(s =>
      '<tr class="' + (s.instanceId === newId ? 'new' : '') + '"><td><span class="dot" style="background:hsl(' + s.hue + ' 70% 55%)"></span><b>' + s.variant + '</b></td>' +
      '<td><code>' + s.shortId + '</code></td><td>' + s.hits + ' hits</td>' +
      '<td>' + (s.burning ? 'burning' : 'idle') + '</td><td>' + s.last.toLocaleTimeString() + '</td></tr>').join('');
    document.getElementById('tbl').innerHTML = '<tr><td><b>' + Object.keys(seen).length + ' instance(s) seen</b></td><td></td><td></td><td></td><td></td></tr>' + rows;
  }
  setInterval(poll, 1500); poll();

  let timer = null;
  const btn = document.getElementById('auto');
  btn.onclick = () => {
    if (timer) { clearInterval(timer); timer = null; btn.textContent = 'Auto-reload: off'; }
    else { timer = setInterval(() => location.reload(), 3000); btn.textContent = 'Auto-reload: every 3s'; }
  };
</script></body></html>`;
}

http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  const send = (code, type, body) => {
    res.writeHead(code, { 'Content-Type': type, 'Cache-Control': 'no-store', 'X-Instance': SHORT_ID });
    res.end(body);
  };
  switch (url.pathname) {
    case '/':
      return send(200, 'text/html; charset=utf-8', page());
    case '/api/whoami':
      return send(200, 'application/json', JSON.stringify(info()));
    case '/burn': {
      const sec = startBurn(url.searchParams.get('seconds'));
      return send(200, 'application/json', JSON.stringify({ instance: VARIANT.name, shortId: SHORT_ID, burningFor: sec }));
    }
    case '/stop':
      stopBurn();
      return send(200, 'application/json', JSON.stringify({ instance: VARIANT.name, stopped: true }));
    case '/healthz':
      return send(200, 'text/plain', 'ok');
    default:
      return send(404, 'text/plain', 'not found');
  }
}).listen(PORT, () => console.log(`Instance ${VARIANT.name} (${SHORT_ID}) listening on ${PORT}`));
