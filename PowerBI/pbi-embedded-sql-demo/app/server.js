// =====================================================================
// server.js — Power BI Embedded "app owns data" (embed for your customers)
//
//  Browser ──(app login, session cookie)──▶ this server
//  this server ──(client credentials)──▶ Microsoft Entra ID  → AAD token for app-pbi-embed
//  this server ──(AAD token)──▶ Power BI REST GenerateToken  → EMBED token
//                                 with effective identity { username, roles }
//  Browser ──(embed token)──▶ Power BI (iframe via powerbi-client JS)
//
// End users never sign in to Power BI and need no Power BI licence:
// the Embedded capacity pays for rendering, the service principal owns the content.
// =====================================================================
require("dotenv").config();
const express = require("express");
const session = require("express-session");
const crypto = require("crypto");
const path = require("path");
const msal = require("@azure/msal-node");

const {
  TENANT_ID, CLIENT_ID, WORKSPACE_ID, REPORT_ID, DATASET_ID,
  RLS_ROLE_REGION = "RegionManager", RLS_ROLE_ALL = "AllRegions",
  KEY_VAULT_NAME, PORT = 3000,
} = process.env;

const PBI_API = "https://api.powerbi.com/v1.0/myorg";
const PBI_SCOPE = ["https://analysis.windows.net/powerbi/api/.default"];

// ---------------------------------------------------------------------
// Demo users of YOUR application. In production these come from your own
// identity system (e.g. Microsoft Entra External ID / B2C, Auth0, your DB).
// "username" must match sales.DimRegion.ManagerUPN for the RegionManager role.
// ---------------------------------------------------------------------
const APP_USERS = {
  north: { display: "North Region Manager", username: "north.manager@contoso.onmicrosoft.com", role: RLS_ROLE_REGION },
  south: { display: "South Region Manager", username: "south.manager@contoso.onmicrosoft.com", role: RLS_ROLE_REGION },
  west:  { display: "West Region Manager",  username: "west.manager@contoso.onmicrosoft.com",  role: RLS_ROLE_REGION },
  east:  { display: "East Region Manager",  username: "east.manager@contoso.onmicrosoft.com",  role: RLS_ROLE_REGION },
  admin: { display: "Head Office (all regions)", username: "headoffice@contoso.onmicrosoft.com", role: RLS_ROLE_ALL },
};

// ---------------------------------------------------------------------
// Secret: local .env for development, Key Vault + managed identity on App Service
// ---------------------------------------------------------------------
async function getClientSecret() {
  if (!KEY_VAULT_NAME) return process.env.CLIENT_SECRET;
  const { DefaultAzureCredential } = require("@azure/identity");
  const { SecretClient } = require("@azure/keyvault-secrets");
  const kv = new SecretClient(`https://${KEY_VAULT_NAME}.vault.azure.net`, new DefaultAzureCredential());
  return (await kv.getSecret("pbi-embed-secret")).value;
}

let cca;
async function aadToken() {
  if (!cca) {
    cca = new msal.ConfidentialClientApplication({
      auth: {
        clientId: CLIENT_ID,
        authority: `https://login.microsoftonline.com/${TENANT_ID}`,
        clientSecret: await getClientSecret(),
      },
    });
  }
  const res = await cca.acquireTokenByClientCredential({ scopes: PBI_SCOPE }); // MSAL caches it
  return res.accessToken;
}

async function pbi(method, url, token, body) {
  const r = await fetch(`${PBI_API}${url}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`${method} ${url} -> ${r.status}: ${text}`);
  return text ? JSON.parse(text) : {};
}

// ---------------------------------------------------------------------
const app = express();
app.use(express.json());
app.use(session({
  secret: process.env.SESSION_SECRET || crypto.randomBytes(32).toString("hex"),
  resave: false, saveUninitialized: false,
  cookie: { httpOnly: true, sameSite: "lax", secure: process.env.NODE_ENV === "production" },
}));
app.set("trust proxy", 1);
app.use(express.static(path.join(__dirname, "public")));

app.get("/api/users", (_req, res) =>
  res.json(Object.entries(APP_USERS).map(([id, u]) => ({ id, display: u.display }))));

app.post("/api/login", (req, res) => {
  const u = APP_USERS[req.body.userId];
  if (!u) return res.status(400).json({ error: "unknown user" });
  req.session.userId = req.body.userId;
  res.json({ ok: true, display: u.display });
});

app.post("/api/logout", (req, res) => req.session.destroy(() => res.json({ ok: true })));

// The browser NEVER chooses its identity or roles: they come from the server-side session.
app.get("/api/embed-config", async (req, res) => {
  const user = APP_USERS[req.session.userId];
  if (!user) return res.status(401).json({ error: "not signed in" });
  try {
    const token = await aadToken();
    const report = await pbi("GET", `/groups/${WORKSPACE_ID}/reports/${REPORT_ID}`, token);

    const embed = await pbi("POST", "/GenerateToken", token, {
      datasets: [{ id: DATASET_ID }],
      reports: [{ id: REPORT_ID }],
      targetWorkspaces: [{ id: WORKSPACE_ID }],
      identities: [{
        username: user.username,           // → USERPRINCIPALNAME() / USERNAME() in DAX
        roles: [user.role],                // → Power BI RLS role defined in the .pbix
        datasets: [DATASET_ID],
      }],
      lifetimeInMinutes: 60,
    });

    res.json({
      reportId: REPORT_ID,
      embedUrl: report.embedUrl,
      accessToken: embed.token,
      expiration: embed.expiration,
      user: { display: user.display, username: user.username, role: user.role },
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});

app.get("/healthz", (_req, res) => res.send("ok"));

app.listen(PORT, () => console.log(`Power BI Embedded demo on http://localhost:${PORT}`));
