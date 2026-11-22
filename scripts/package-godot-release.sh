#!/usr/bin/env bash
set -euo pipefail

# Build a Godot desktop release from the committed export presets. The caller
# supplies the target preset and output stem, which lets Actions run Linux and
# Windows jobs independently without coupling optional macOS work.

PRESET="${1:?usage: $0 <preset> <output-stem> [version]}"
OUTPUT_STEM="${2:?usage: $0 <preset> <output-stem> [version]}"
VERSION="${3:-dev}"
GODOT_BIN="${GODOT_BIN:-godot4}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist/godot"
PACKAGE_DIR="${DIST_DIR}/${OUTPUT_STEM}"

mkdir -p "${PACKAGE_DIR}"

case "${PRESET}" in
  "Linux/X11")
    executable="${PACKAGE_DIR}/circuit-bastion-linux-x86_64"
    ;;
  "Windows Desktop")
    executable="${PACKAGE_DIR}/circuit-bastion-windows-x86_64.exe"
    ;;
  "macOS")
    executable="${PACKAGE_DIR}/circuit-bastion-macos-universal.app"
    ;;
  *)
    echo "unknown Godot export preset: ${PRESET}" >&2
    exit 2
    ;;
esac

"${GODOT_BIN}" --headless --path "${ROOT_DIR}" --export-release "${PRESET}" "${executable}"
if [[ ! -f "${executable}" && ! -d "${executable}" ]]; then
  echo "Godot export did not produce the expected output: ${executable}" >&2
  exit 1
fi
cp "${ROOT_DIR}/README.md" "${ROOT_DIR}/RUNNING.md" "${PACKAGE_DIR}/"
cat > "${PACKAGE_DIR}/VERSION.txt" <<EOF
Circuit Bastion Godot desktop build
Version: ${VERSION}
Preset: ${PRESET}
EOF

if [[ "${PRESET}" == "Linux/X11" ]]; then
  chmod +x "${executable}"
fi

(cd "${DIST_DIR}" && zip -qr "${OUTPUT_STEM}.zip" "${OUTPUT_STEM}")
echo "GODOT_PACKAGE_OK ${DIST_DIR}/${OUTPUT_STEM}.zip"
