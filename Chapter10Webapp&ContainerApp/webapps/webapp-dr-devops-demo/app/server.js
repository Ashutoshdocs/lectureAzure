// Demo web app: shows whether you are on the PRIMARY or the DR site.
// SITE_ROLE / SITE_REGION / BUILD_NUMBER are app settings written by the pipelines.
const http = require('http');
const os = require('os');

const PORT = process.env.PORT || 8080;
const ROLE = (process.env.SITE_ROLE || 'local').toUpperCase();
const REGION = process.env.SITE_REGION || 'local';
const BUILD = process.env.BUILD_NUMBER || 'dev';
const COMMIT = (process.env.SOURCE_COMMIT || 'unknown').slice(0, 8);
const APP = process.env.WEBSITE_SITE_NAME || os.hostname();
const IS_DR = ROLE === 'DR';

const page = () => `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${ROLE} site</title>
<style>
  body { margin:0; font-family: system-ui, sans-serif; color:#fff; min-height:100vh;
         background: ${IS_DR ? 'linear-gradient(135deg,#7a1f1f,#2b0a0a)' : 'linear-gradient(135deg,#0f5132,#062016)'}; }
  main { max-width: 760px; margin: 0 auto; padding: 40px 16px; }
  .badge { display:inline-block; padding:6px 12px; border-radius:999px; background:rgba(255,255,255,.18);
           font-size:13px; letter-spacing:2px; text-transform:uppercase; }
  h1 { font-size: clamp(40px, 8vw, 76px); margin: 12px 0; }
  table { width:100%; border-collapse:collapse; margin-top:24px; background:rgba(0,0,0,.25); border-radius:12px; overflow:hidden; }
  td { padding:10px 14px; border-bottom:1px solid rgba(255,255,255,.1); }
  td:first-child { opacity:.7; width:38%; }
  code { font-family: ui-monospace, monospace; }
</style></head>
<body><main>
  <span class="badge">${IS_DR ? 'Disaster recovery site' : 'Primary site'}</span>
  <h1>${IS_DR ? 'DR is live 🚨' : 'Primary is live ✅'}</h1>
  <p>Deployed from the Azure DevOps repo by an Azure Pipelines run.</p>
  <table>
    <tr><td>Web app</td><td><code>${APP}</code></td></tr>
    <tr><td>Role</td><td><code>${ROLE}</code></td></tr>
    <tr><td>Region</td><td><code>${REGION}</code></td></tr>
    <tr><td>Pipeline build</td><td><code>${BUILD}</code></td></tr>
    <tr><td>Commit</td><td><code>${COMMIT}</code></td></tr>
    <tr><td>Instance</td><td><code>${(process.env.WEBSITE_INSTANCE_ID || os.hostname()).slice(0, 12)}</code></td></tr>
  </table>
</main></body></html>`;

http.createServer((req, res) => {
  if (req.url === '/healthz') { res.writeHead(200, { 'Content-Type': 'text/plain' }); return res.end('ok'); }
  if (req.url === '/api/info') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ app: APP, role: ROLE, region: REGION, build: BUILD, commit: COMMIT }));
  }
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(page());
}).listen(PORT, () => console.log(`${ROLE} site (${REGION}) listening on ${PORT}`));
