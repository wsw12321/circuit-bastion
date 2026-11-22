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

## Godot 4 desktop vertical slice

Install Godot 4.3 or newer, then launch the project root. The desktop build uses
`scenes/main.tscn`, `scripts/game_root.gd`, `godot/battle_view.gd`, and the
deterministic core in `scripts/simulation.gd`.

```bash
godot4 --path .
```

Headless validation is available for CI or servers without a display:

```bash
godot4 --headless --path . --scene res://scenes/main.tscn --quit-after 2 \
  --display-driver headless --audio-driver Dummy --rendering-method gl_compatibility
godot4 --headless --path . --script scripts/godot_smoke.gd \
  --display-driver headless --audio-driver Dummy --rendering-method gl_compatibility
godot4 --headless --path . --script scripts/simulation_probe.gd
```

Version tags also publish `circuit-bastion-godot-linux-x64.zip` and
`circuit-bastion-godot-windows-x64.zip`. Each archive contains the exported
Godot executable, project documentation, and `VERSION.txt`. macOS remains an
optional release target and never blocks the required Linux/Windows release.

### Godot Release packages

Version tags publish two desktop archives alongside the Node fallback packages:

- `circuit-bastion-godot-linux-x64.zip` runs the Linux x64 executable directly.
- `circuit-bastion-godot-windows-x64.zip` runs the Windows x64 `.exe` directly.

Each archive includes `README.md`, this file, and `VERSION.txt`. The macOS SEA
packages remain optional because hosted macOS runners can be queued independently.

### Android arm64 APK

Version tags also run an independent Android export job. When the hosted Android
toolchain is available, the Release contains `circuit-bastion-android-arm64.apk`.
Download it on an arm64 Android phone, allow installation from the browser or file
manager when Android asks, and install the APK. The build is debug-signed for local
验收 and does not request network access. Touch controls include tap-to-select,
drag-to-move, long-press-friendly detail cards, and the same build, rotate, sell,
shop, upgrade, pause, and retry actions as desktop. The Android job is optional, so
desktop and portable release assets still publish if a mobile runner is queued or
unavailable.
