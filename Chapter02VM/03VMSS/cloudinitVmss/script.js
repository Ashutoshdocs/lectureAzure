/*=========================================================
  AZURE VMSS DASHBOARD — script.js
  Live clock · particles · animated gauges · public IP · uptime
=========================================================*/

// config.js (written at boot by cloud-init) may define window.AZURE_CONFIG.
// Sensible fallbacks keep the page working when opened directly.
const CFG = window.AZURE_CONFIG || {};
const HOSTNAME = CFG.hostname || "azure-vmss-node";
const REGION = CFG.region || "Central India";
const BOOT_EPOCH = CFG.bootEpoch || Math.floor(Date.now() / 1000);

/*---------------------------------------------------------
  1. Static values from config
---------------------------------------------------------*/
document.getElementById("hostname").textContent = HOSTNAME;
document.getElementById("region").textContent = REGION;

/*---------------------------------------------------------
  2. Live clock + date
---------------------------------------------------------*/
function pad(n) { return String(n).padStart(2, "0"); }

function tickClock() {
  const now = new Date();
  document.getElementById("clock").textContent =
    `${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
  document.getElementById("date").textContent = now.toLocaleDateString(undefined, {
    weekday: "long", year: "numeric", month: "long", day: "numeric"
  });
}
tickClock();
setInterval(tickClock, 1000);

/*---------------------------------------------------------
  3. Uptime (real, from boot epoch supplied by cloud-init)
---------------------------------------------------------*/
function tickUptime() {
  let secs = Math.max(0, Math.floor(Date.now() / 1000) - BOOT_EPOCH);
  const d = Math.floor(secs / 86400); secs -= d * 86400;
  const h = Math.floor(secs / 3600);  secs -= h * 3600;
  const m = Math.floor(secs / 60);    secs -= m * 60;
  const parts = [];
  if (d) parts.push(`${d}d`);
  parts.push(`${pad(h)}h`, `${pad(m)}m`, `${pad(secs)}s`);
  document.getElementById("uptime").textContent = parts.join(" ");
}
tickUptime();
setInterval(tickUptime, 1000);

/*---------------------------------------------------------
  4. Floating particles
---------------------------------------------------------*/
(function spawnParticles() {
  const layer = document.getElementById("particles");
  const COUNT = 45;
  for (let i = 0; i < COUNT; i++) {
    const p = document.createElement("div");
    p.className = "particle";
    const size = Math.random() * 5 + 2;
    p.style.width = p.style.height = `${size}px`;
    p.style.left = `${Math.random() * 100}%`;
    p.style.animationDuration = `${Math.random() * 12 + 8}s`;
    p.style.animationDelay = `${Math.random() * -20}s`;
    p.style.opacity = (Math.random() * 0.5 + 0.3).toFixed(2);
    layer.appendChild(p);
  }
})();

/*---------------------------------------------------------
  5. Animated gauges
  NOTE: A static page served by NGINX cannot read the host's
  real CPU/RAM/disk without a backend agent. These values are
  simulated so the demo dashboard looks alive. Swap updateSim()
  for a fetch() against a metrics endpoint to show real data.
---------------------------------------------------------*/
const state = { cpu: 24, mem: 41, disk: 37, net: 120 };

function drift(value, min, max, step) {
  const next = value + (Math.random() - 0.5) * step;
  return Math.min(max, Math.max(min, next));
}

function ringColor(v) {
  if (v >= 85) return "var(--red)";
  if (v >= 60) return "var(--orange)";
  return "var(--cyan)";
}

function setGauge(gaugeId, textId, value) {
  const g = document.getElementById(gaugeId);
  const rounded = Math.round(value);
  g.style.setProperty("--val", rounded);
  g.style.setProperty("--ring", ringColor(rounded));
  document.getElementById(textId).textContent = `${rounded}%`;
}

function updateSim() {
  state.cpu = drift(state.cpu, 8, 92, 14);
  state.mem = drift(state.mem, 30, 88, 6);
  state.disk = drift(state.disk, 35, 70, 1.2);
  state.net = drift(state.net, 20, 940, 220);

  setGauge("cpuGauge", "cpuPercent", state.cpu);
  setGauge("memoryGauge", "memoryPercent", state.mem);
  setGauge("diskGauge", "diskPercent", state.disk);
  document.getElementById("netThroughput").textContent = Math.round(state.net);
}
updateSim();
setInterval(updateSim, 2000);

/*---------------------------------------------------------
  6. Public IP detection (client-side lookup)
---------------------------------------------------------*/
(async function detectIP() {
  const el = document.getElementById("publicIP");
  try {
    const res = await fetch("https://api.ipify.org?format=json", { cache: "no-store" });
    const data = await res.json();
    el.textContent = data.ip || "Unavailable";
  } catch (_) {
    el.textContent = "Unavailable";
  }
})();
