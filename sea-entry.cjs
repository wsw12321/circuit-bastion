const { createServer } = require('node:http');
const { readFileSync } = require('node:fs');
const { join, dirname } = require('node:path');
const { isSea, getAsset } = require('node:sea');

const root = dirname(process.execPath);
const mime = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
};

function readAsset(name) {
  if (isSea()) return getAsset(name, 'utf8');
  return readFileSync(join(root, name), 'utf8');
}

const assets = new Map([
  ['/', ['index.html', 'text/html; charset=utf-8']],
  ['/index.html', ['index.html', 'text/html; charset=utf-8']],
  ['/styles.css', ['styles.css', mime['.css']]],
  ['/app.js', ['app.js', mime['.js']]],
]);

const server = createServer((req, res) => {
  let pathname;
  try {
    pathname = new URL(req.url, 'http://127.0.0.1').pathname;
  } catch {
    res.writeHead(400);
    res.end('Bad request');
    return;
  }

  const asset = assets.get(pathname);
  if (!asset) {
    res.writeHead(404);
    res.end('Not found');
    return;
  }

  try {
    res.writeHead(200, { 'Content-Type': asset[1], 'Cache-Control': 'no-cache' });
    res.end(readAsset(asset[0]));
  } catch (error) {
    res.writeHead(500);
    res.end(`Asset error: ${error.message}`);
  }
});

const port = Number(process.env.PORT ?? 4173);
server.listen(port, '127.0.0.1', () => {
  console.log(`Circuit Bastion running at http://127.0.0.1:${port}`);
});
