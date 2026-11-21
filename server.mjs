import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('.', import.meta.url));
const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8' };

const server = createServer(async (req, res) => {
  const requested = req.url === '/' ? '/index.html' : req.url.split('?')[0];
  const path = normalize(join(root, requested));
  if (!path.startsWith(root)) { res.writeHead(403); res.end('Forbidden'); return; }
  try {
    const body = await readFile(path);
    res.writeHead(200, { 'Content-Type': mime[extname(path)] ?? 'application/octet-stream', 'Cache-Control': 'no-cache' });
    res.end(body);
  } catch {
    res.writeHead(404); res.end('Not found');
  }
});

const port = Number(process.env.PORT ?? 4173);
server.listen(port, '127.0.0.1', () => console.log(`Circuit Bastion running at http://127.0.0.1:${port}`));
