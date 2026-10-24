// Event Grid Lab - custom event viewer
// Zero dependencies: uses only Node.js built-in modules.
//
// Endpoints
//   POST    /api/updates   Event Grid webhook (validation handshake + events)
//   OPTIONS /api/updates   CloudEvents v1.0 webhook validation handshake
//   GET     /api/events    JSON list of events received so far
//   GET     /api/stream    Server-Sent Events stream (live updates to the UI)
//   DELETE  /api/events    Clear stored events
//   GET     /health        Health check
//   GET     /              Web UI (public/index.html)

const http = require("http");
const fs = require("fs");
const path = require("path");

const PORT = process.env.PORT || 8080;
const MAX_EVENTS = parseInt(process.env.MAX_EVENTS || "200", 10);
// Optional shared secret. If set, Event Grid must call
//   https://<app>.azurewebsites.net/api/updates?key=<value>
const WEBHOOK_KEY = process.env.WEBHOOK_KEY || "";

const events = [];        // newest first, in memory only
const clients = new Set(); // open SSE connections

function log(...args) {
  console.log(new Date().toISOString(), ...args);
}

function send(res, status, body, headers = {}) {
  const isObj = typeof body === "object" && body !== null;
  res.writeHead(status, {
    "Content-Type": isObj ? "application/json" : "text/plain; charset=utf-8",
    ...headers,
  });
  res.end(isObj ? JSON.stringify(body) : body ?? "");
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (chunk) => {
      data += chunk;
      if (data.length > 1024 * 1024) {
        reject(new Error("Body too large"));
        req.destroy();
      }
    });
    req.on("end", () => resolve(data));
    req.on("error", reject);
  });
}

function broadcast(evt) {
  const payload = `data: ${JSON.stringify(evt)}\n\n`;
  for (const res of clients) res.write(payload);
}

function store(evt, source) {
  const record = {
    receivedAt: new Date().toISOString(),
    source, // "webhook" | "validation"
    id: evt.id,
    type: evt.eventType || evt.type,          // Event Grid schema | CloudEvents
    subject: evt.subject,
    time: evt.eventTime || evt.time,
    topic: evt.topic || evt.source,
    data: evt.data,
    raw: evt,
  };
  events.unshift(record);
  if (events.length > MAX_EVENTS) events.length = MAX_EVENTS;
  broadcast(record);
  log(`[${source}] ${record.type} | ${record.subject || ""}`);
}

async function handleWebhook(req, res, url) {
  if (WEBHOOK_KEY && url.searchParams.get("key") !== WEBHOOK_KEY) {
    log("Rejected call with missing/invalid key");
    return send(res, 401, { error: "Unauthorized" });
  }

  // CloudEvents v1.0 schema validation handshake (HTTP OPTIONS)
  if (req.method === "OPTIONS") {
    const origin = req.headers["webhook-request-origin"];
    log("CloudEvents validation handshake from", origin);
    return send(res, 200, "", {
      "WebHook-Allowed-Origin": origin || "*",
      "WebHook-Allowed-Rate": "*",
    });
  }

  let body;
  try {
    body = JSON.parse((await readBody(req)) || "null");
  } catch {
    return send(res, 400, { error: "Invalid JSON" });
  }

  // Event Grid schema delivers an array; CloudEvents may deliver a single object
  const list = Array.isArray(body) ? body : body ? [body] : [];

  for (const evt of list) {
    // Event Grid schema validation handshake
    if (evt.eventType === "Microsoft.EventGrid.SubscriptionValidationEvent") {
      const code = evt.data && evt.data.validationCode;
      store(evt, "validation");
      log("Validation handshake, replying with validationCode", code);
      return send(res, 200, { validationResponse: code });
    }
  }

  for (const evt of list) store(evt, "webhook");
  return send(res, 200, { received: list.length });
}

function handleStream(req, res) {
  res.writeHead(200, {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
    "X-Accel-Buffering": "no",
  });
  res.write(": connected\n\n");
  clients.add(res);
  // keep-alive ping so App Service / proxies don't close the connection
  const ping = setInterval(() => res.write(": ping\n\n"), 25000);
  req.on("close", () => {
    clearInterval(ping);
    clients.delete(res);
  });
}

function serveStatic(res, pathname) {
  const publicDir = path.join(__dirname, "public");
  const file = path.normalize(
    path.join(publicDir, pathname === "/" ? "index.html" : pathname)
  );
  if (!file.startsWith(publicDir)) return send(res, 403, "Forbidden");
  fs.readFile(file, (err, content) => {
    if (err) return send(res, 404, "Not found");
    const types = {
      ".html": "text/html; charset=utf-8",
      ".js": "application/javascript",
      ".css": "text/css",
      ".svg": "image/svg+xml",
    };
    res.writeHead(200, {
      "Content-Type": types[path.extname(file)] || "application/octet-stream",
    });
    res.end(content);
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  const p = url.pathname.replace(/\/+$/, "") || "/";

  try {
    if (p === "/api/updates" && (req.method === "POST" || req.method === "OPTIONS"))
      return await handleWebhook(req, res, url);

    if (p === "/api/events" && req.method === "GET") return send(res, 200, events);

    if (p === "/api/events" && req.method === "DELETE") {
      events.length = 0;
      broadcast({ cleared: true });
      return send(res, 200, { cleared: true });
    }

    if (p === "/api/stream" && req.method === "GET") return handleStream(req, res);

    if (p === "/health") return send(res, 200, { status: "ok", events: events.length });

    if (req.method === "GET") return serveStatic(res, p);

    return send(res, 405, "Method not allowed");
  } catch (err) {
    log("Error:", err.message);
    return send(res, 500, { error: "Internal error" });
  }
});

server.listen(PORT, () => log(`Event viewer listening on port ${PORT}`));

// Exported for local tests
module.exports = { server };
