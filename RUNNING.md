# Running Circuit Bastion

## Standalone release builds

Release downloads include a platform-specific executable that bundles Node.js, the HTTP server, HTML, CSS, and game JavaScript. Node.js is not required for these builds.

1. Download the ZIP matching your platform and architecture.
2. Extract it.
3. Run the executable in the extracted folder.
4. Open `http://127.0.0.1:4173/` in a browser.

The macOS artifacts are ad-hoc signed for local execution. macOS may still ask for confirmation the first time an unsigned developer build is opened.

## Portable Node.js fallback

The `circuit-bastion-portable` ZIP works on any system with Node.js 18 or newer.

- macOS and Linux: run `./launch.sh`
- Windows: run `launch.cmd`

Then open `http://127.0.0.1:4173/`.

## Development

```bash
npm ci
npm run check
npm start
```

To build a local SEA executable on the current platform:

```bash
npm ci
npm run build:sea
node scripts/smoke-sea.mjs dist/sea/circuit-bastion-<platform>-<arch>
```
