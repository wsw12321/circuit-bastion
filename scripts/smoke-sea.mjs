import { spawn } from 'node:child_process';
import { resolve } from 'node:path';

const executable = resolve(process.argv[2] ?? 'dist/sea/circuit-bastion');
const port = Number(process.env.PORT ?? 4174);
const child = spawn(executable, [], {
  env: { ...process.env, PORT: String(port) },
  stdio: ['ignore', 'pipe', 'pipe'],
});
let output = '';
child.stdout.on('data', (chunk) => { output += chunk; });
child.stderr.on('data', (chunk) => { output += chunk; });

function stop() {
  if (!child.killed) child.kill();
}

try {
  let response;
  for (let attempt = 0; attempt < 30; attempt += 1) {
    try {
      response = await fetch(`http://127.0.0.1:${port}/`);
      if (response.ok) break;
    } catch {
      await new Promise((resolvePromise) => setTimeout(resolvePromise, 200));
    }
  }
  if (!response?.ok) throw new Error(`SEA server did not respond. Output: ${output}`);
  const html = await response.text();
  if (!html.includes('CIRCUIT BASTION')) throw new Error('SEA server returned unexpected HTML');
  console.log(`SEA smoke OK: ${executable}`);
} finally {
  stop();
}
