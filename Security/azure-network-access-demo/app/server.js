// Tiny "caller" app for demo 5 (no dependencies).
// Opening this app's URL makes it try to fetch TARGET_URL (a PRIVATE IP
// inside the VNet) and report whether it could reach it.
const http = require('http');

const target = process.env.TARGET_URL || 'http://10.1.3.4';
const port = process.env.PORT || 8080;

http.createServer((req, res) => {
  let done = false;
  const finish = (code, body) => {
    if (done) return;
    done = true;
    res.writeHead(code, { 'Content-Type': 'text/plain' });
    res.end(body);
  };

  const upstream = http.get(target, { timeout: 5000 }, (up) => {
    let data = '';
    up.on('data', (c) => { data += c; });
    up.on('end', () => finish(200,
      `SUCCESS: this web app reached ${target} through VNet integration.\n\n` +
      `First part of the private page:\n${data.slice(0, 300)}\n`));
  });
  upstream.on('timeout', () => upstream.destroy(new Error('timed out after 5s')));
  upstream.on('error', (e) => finish(502,
    `FAILED: this web app could NOT reach ${target} (${e.message}).\n` +
    `It lives outside the VNet and has no route to private addresses.\n`));
}).listen(port, () => console.log(`caller app listening on ${port}, target=${target}`));
