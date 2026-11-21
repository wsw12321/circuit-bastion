#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=${1:-snapshot}
safe_version=${version//\//-}
package_name="circuit-bastion-${safe_version}"
dist_dir="$root_dir/dist"
scratch_dir="$root_dir/.release-tmp"
mkdir -p "$scratch_dir"
stage_dir=$(mktemp -d "$scratch_dir/circuit-bastion.XXXXXX")
package_dir="$stage_dir/$package_name"

cleanup() {
  rm -rf "$stage_dir"
  rmdir "$scratch_dir" 2>/dev/null || true
}
trap cleanup EXIT

if ! command -v zip >/dev/null 2>&1; then
  echo "zip is required to build a release archive" >&2
  exit 1
fi

mkdir -p "$package_dir" "$dist_dir"
for file in index.html styles.css app.js server.mjs package.json README.md; do
  cp "$root_dir/$file" "$package_dir/$file"
done
if [[ -f "$root_dir/package-lock.json" ]]; then
  cp "$root_dir/package-lock.json" "$package_dir/package-lock.json"
fi

cat > "$package_dir/RUNNING.md" <<'EOF'
# Running the portable build

The release package needs Node.js 18 or newer and does not include `node_modules`.

## macOS and Linux

```bash
./launch.sh
```

## Windows

Double-click `launch.cmd`, or run it from Command Prompt.

Open `http://127.0.0.1:4173/` after the server starts. Stop the server with `Ctrl+C`.
EOF

cat > "$package_dir/launch.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$script_dir"
exec node server.mjs
EOF

cat > "$package_dir/launch.cmd" <<'EOF'
@echo off
cd /d "%~dp0"
node server.mjs
EOF

chmod +x "$package_dir/launch.sh"
rm -f "$dist_dir/$package_name.zip"
(
  cd "$stage_dir"
  zip -qr "$dist_dir/$package_name.zip" "$package_name"
)

echo "Created $dist_dir/$package_name.zip"
