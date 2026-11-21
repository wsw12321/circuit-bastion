import { chmodSync, copyFileSync, existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const platform = process.platform;
const architecture = process.arch;
const outputDirectory = resolve(process.env.SEA_OUTPUT_DIR ?? join(root, 'dist', 'sea'));
const name = process.env.SEA_NAME ?? `circuit-bastion-${platform}-${architecture}`;
const executableName = platform === 'win32' ? `${name}.exe` : name;
const executablePath = join(outputDirectory, executableName);
const workDirectory = join(outputDirectory, '.work');
const configPath = join(workDirectory, 'sea-config.json');
const blobPath = join(workDirectory, 'sea-prep.blob');

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: root,
    stdio: 'inherit',
    shell: platform === 'win32',
    ...options,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} exited with code ${result.status}`);
}

rmSync(workDirectory, { recursive: true, force: true });
mkdirSync(workDirectory, { recursive: true });
mkdirSync(outputDirectory, { recursive: true });

const config = {
  main: join(root, 'sea-entry.cjs'),
  mainFormat: 'commonjs',
  output: blobPath,
  disableExperimentalSEAWarning: true,
  useCodeCache: false,
  useSnapshot: false,
  assets: {
    'index.html': join(root, 'index.html'),
    'styles.css': join(root, 'styles.css'),
    'app.js': join(root, 'app.js'),
  },
};
writeFileSync(configPath, JSON.stringify(config, null, 2));

run(process.execPath, ['--experimental-sea-config', configPath]);
copyFileSync(process.execPath, executablePath);

if (platform === 'darwin') {
  const signature = spawnSync('codesign', ['--remove-signature', executablePath], { stdio: 'inherit' });
  if (signature.error) throw signature.error;
}

const postject = join(root, 'node_modules', '.bin', platform === 'win32' ? 'postject.cmd' : 'postject');
if (!existsSync(postject)) throw new Error(`postject was not found at ${postject}. Run npm ci first.`);
const postjectArgs = [
  executablePath,
  'NODE_SEA_BLOB',
  blobPath,
  '--sentinel-fuse',
  'NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2',
];
if (platform === 'darwin') postjectArgs.push('--macho-segment-name', 'NODE_SEA');
run(postject, postjectArgs);

if (platform === 'darwin') {
  run('codesign', ['--sign', '-', executablePath]);
}
if (platform !== 'win32') chmodSync(executablePath, 0o755);
rmSync(workDirectory, { recursive: true, force: true });

console.log(`Created ${executablePath}`);
