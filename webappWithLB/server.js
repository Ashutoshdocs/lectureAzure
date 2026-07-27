const express = require("express");
const os = require("os");

const app = express();

const instance = process.env.WEBSITE_INSTANCE_ID || os.hostname();

// Two-color palette per instance so we can build a gradient
const palettes = [
  ["#6a11cb", "#2575fc"],  // purple → blue
  ["#ff0844", "#ffb199"],  // red → peach
  ["#00c6fb", "#005bea"],  // sky → deep blue
  ["#f857a6", "#ff5858"],  // pink → coral
  ["#43e97b", "#38f9d7"],  // green → teal
  ["#fa709a", "#fee140"],  // rose → gold
  ["#30cfd0", "#330867"],  // aqua → indigo
  ["#ff9a9e", "#fad0c4"],  // blush → cream
  ["#4facfe", "#00f2fe"],  // blue → cyan
  ["#f093fb", "#f5576c"]   // orchid → red
];

let sum = 0;
for (let i = 0; i < instance.length; i++) {
  sum += instance.charCodeAt(i);
}

const [c1, c2] = palettes[sum % palettes.length];

// Short, friendly label from the instance id
const shortId = instance.slice(0, 8).toUpperCase();

app.get("/", (req, res) => {
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Azure Scale-Out Demo</title>
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@500;600&display=swap" rel="stylesheet" />
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }

    :root {
      --c1: ${c1};
      --c2: ${c2};
    }

    body {
      min-height: 100vh;
      font-family: "Inter", -apple-system, BlinkMacSystemFont, sans-serif;
      color: #fff;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
      background: linear-gradient(135deg, var(--c1) 0%, var(--c2) 100%);
      background-size: 200% 200%;
      animation: drift 18s ease infinite;
      overflow: hidden;
      position: relative;
    }

    @keyframes drift {
      0%   { background-position: 0% 50%; }
      50%  { background-position: 100% 50%; }
      100% { background-position: 0% 50%; }
    }

    /* Soft floating blobs for depth */
    .blob {
      position: absolute;
      border-radius: 50%;
      filter: blur(80px);
      opacity: 0.35;
      z-index: 0;
    }
    .blob.one { width: 360px; height: 360px; background: #fff; top: -120px; left: -100px; }
    .blob.two { width: 420px; height: 420px; background: var(--c2); bottom: -160px; right: -120px; }

    .card {
      position: relative;
      z-index: 1;
      width: 100%;
      max-width: 560px;
      padding: 48px 40px;
      border-radius: 28px;
      background: rgba(255, 255, 255, 0.12);
      backdrop-filter: blur(22px) saturate(160%);
      -webkit-backdrop-filter: blur(22px) saturate(160%);
      border: 1px solid rgba(255, 255, 255, 0.25);
      box-shadow: 0 24px 60px rgba(0, 0, 0, 0.28);
      text-align: center;
      animation: rise 0.8s cubic-bezier(0.2, 0.8, 0.2, 1) both;
    }

    @keyframes rise {
      from { opacity: 0; transform: translateY(28px) scale(0.98); }
      to   { opacity: 1; transform: translateY(0) scale(1); }
    }

    .badge {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      font-size: 13px;
      font-weight: 600;
      letter-spacing: 0.06em;
      text-transform: uppercase;
      padding: 8px 16px;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.18);
      border: 1px solid rgba(255, 255, 255, 0.25);
      margin-bottom: 26px;
    }

    .dot {
      width: 9px; height: 9px;
      border-radius: 50%;
      background: #2ecc71;
      box-shadow: 0 0 0 0 rgba(46, 204, 113, 0.7);
      animation: pulse 1.8s infinite;
    }
    @keyframes pulse {
      0%   { box-shadow: 0 0 0 0 rgba(46, 204, 113, 0.6); }
      70%  { box-shadow: 0 0 0 12px rgba(46, 204, 113, 0); }
      100% { box-shadow: 0 0 0 0 rgba(46, 204, 113, 0); }
    }

    h1.title {
      font-size: 34px;
      font-weight: 800;
      letter-spacing: -0.02em;
      margin-bottom: 6px;
    }
    p.subtitle {
      font-size: 15px;
      font-weight: 500;
      opacity: 0.85;
      margin-bottom: 34px;
    }

    .instance-chip {
      display: inline-block;
      font-family: "JetBrains Mono", monospace;
      font-size: 42px;
      font-weight: 600;
      letter-spacing: 0.04em;
      padding: 18px 34px;
      border-radius: 18px;
      background: rgba(0, 0, 0, 0.22);
      border: 1px solid rgba(255, 255, 255, 0.2);
      margin-bottom: 32px;
      word-break: break-all;
    }

    .grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 14px;
      margin-bottom: 30px;
    }
    .stat {
      background: rgba(255, 255, 255, 0.1);
      border: 1px solid rgba(255, 255, 255, 0.16);
      border-radius: 16px;
      padding: 18px 16px;
      text-align: left;
    }
    .stat .label {
      font-size: 11px;
      font-weight: 600;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      opacity: 0.7;
      margin-bottom: 6px;
    }
    .stat .value {
      font-family: "JetBrains Mono", monospace;
      font-size: 15px;
      font-weight: 600;
      word-break: break-all;
    }
    .stat.full { grid-column: 1 / -1; }

    .hint {
      font-size: 13px;
      opacity: 0.8;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
    }
    .hint svg { width: 15px; height: 15px; opacity: 0.9; }

    @media (max-width: 480px) {
      .card { padding: 36px 22px; }
      .instance-chip { font-size: 30px; padding: 14px 20px; }
      .grid { grid-template-columns: 1fr; }
      h1.title { font-size: 27px; }
    }
  </style>
</head>
<body>
  <div class="blob one"></div>
  <div class="blob two"></div>

  <div class="card">
    <span class="badge"><span class="dot"></span> Live · Running</span>

    <h1 class="title">Azure App Service</h1>
    <p class="subtitle">Scale-Out Demonstration</p>

    <div class="instance-chip">${shortId}</div>

    <div class="grid">
      <div class="stat full">
        <div class="label">Instance ID</div>
        <div class="value">${instance}</div>
      </div>
      <div class="stat full">
        <div class="label">Hostname</div>
        <div class="value">${os.hostname()}</div>
      </div>
      <div class="stat full">
        <div class="label">Server Time</div>
        <div class="value" id="clock">${new Date().toString()}</div>
      </div>
    </div>

    <div class="hint">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M23 4v6h-6M1 20v-6h6"/>
        <path d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/>
      </svg>
      Refresh after scaling to see a different instance
    </div>
  </div>

  <script>
    // Live-updating clock (client-side, so it ticks without a reload)
    const clock = document.getElementById("clock");
    setInterval(() => { clock.textContent = new Date().toString(); }, 1000);
  </script>
</body>
</html>`);
});

// --- API endpoints ---

const info = () => ({
  instanceId: process.env.WEBSITE_INSTANCE_ID || "N/A",
  hostname: os.hostname(),
  shortId: shortId,
  time: new Date().toString()
});

app.get("/hostname", (req, res) => {
  res.send(os.hostname());
});

app.get("/instance", (req, res) => {
  res.send(instance);
});

app.get("/info", (req, res) => {
  res.json(info());
});

app.listen(process.env.PORT || 8080);
