// Azure Container Apps demo server — zero dependencies (Node 18+).
// Serves a UI at "/" and a few APIs that make Container Apps features visible.
const http = require("http");
const fs = require("fs");
const path = require("path");
const os = require("os");

const PORT = process.env.PORT || 8080;
const startedAt = new Date().toISOString();
let inFlight = 0;
let served = 0;

// Container Apps injects these env vars into every replica automatically.
function info() {
  return {
    app: process.env.CONTAINER_APP_NAME || "local",
    revision: process.env.CONTAINER_APP_REVISION || "local-revision",
    replica: process.env.CONTAINER_APP_REPLICA_NAME || os.hostname(),
    envDnsSuffix: process.env.CONTAINER_APP_ENV_DNS_SUFFIX || null,
    runningInAca: Boolean(process.env.CONTAINER_APP_NAME),
    version: process.env.APP_VERSION || "v1",
    image: process.env.APP_IMAGE || "not set (add APP_IMAGE env var)",
    color: process.env.APP_COLOR || "#2563eb",
    message: process.env.APP_MESSAGE || "Hello from Azure Container Apps",
    role: process.env.APP_ROLE || "frontend",
    backendUrl: process.env.BACKEND_URL || null,
    startedAt,
    uptimeSec: Math.round(process.uptime()),
    inFlight,
    served,
    node: process.version,
  };
}

function sendJson(res, status, body) {
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
  });
  res.end(JSON.stringify(body));
}

const indexHtml = path.join(__dirname, "public", "index.html");

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  served++;

  try {
    // UI
    if (url.pathname === "/" || url.pathname === "/index.html") {
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      return fs.createReadStream(indexHtml).pipe(res);
    }

    // Health probe (used by liveness/readiness probes)
    if (url.pathname === "/healthz") return sendJson(res, 200, { status: "ok" });

    // Who answered? (replica + revision) — used for load-balancing & traffic-split demos
    if (url.pathname === "/api/info") return sendJson(res, 200, info());

    // Holds a request open for N ms. Concurrent held requests drive the
    // HTTP-concurrency scale rule (KEDA) so you can watch replicas scale out.
    if (url.pathname === "/api/work") {
      const ms = Math.min(parseInt(url.searchParams.get("ms") || "2000", 10), 30000);
      inFlight++;
      await new Promise((r) => setTimeout(r, ms));
      inFlight--;
      return sendJson(res, 200, { heldMs: ms, ...info() });
    }

    // Calls another container app in the same environment by name
    // (internal ingress + built-in service discovery).
    if (url.pathname === "/api/downstream") {
      const target = process.env.BACKEND_URL;
      if (!target) return sendJson(res, 400, { error: "BACKEND_URL not set on this app" });
      const t0 = Date.now();
      const r = await fetch(`${target.replace(/\/$/, "")}/api/info`);
      const body = await r.json();
      return sendJson(res, 200, { calledUrl: target, latencyMs: Date.now() - t0, backend: body, caller: info() });
    }

    sendJson(res, 404, { error: "not found" });
  } catch (err) {
    sendJson(res, 500, { error: String(err.message || err) });
  }
});

server.listen(PORT, () => console.log(`[${info().revision}/${info().replica}] listening on :${PORT}`));

// Graceful shutdown — Container Apps sends SIGTERM when scaling in.
process.on("SIGTERM", () => {
  console.log("SIGTERM received (scale-in or new revision) — shutting down gracefully");
  server.close(() => process.exit(0));
});
