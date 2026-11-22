#!/usr/bin/env bash
set -euo pipefail
DIST_DIR="${1:?usage: $0 <release-dist>}"
APK="${DIST_DIR}/circuit-bastion-android-arm64.apk"
LINUX_ZIP="${DIST_DIR}/circuit-bastion-godot-linux-x64.zip"
WINDOWS_ZIP="${DIST_DIR}/circuit-bastion-godot-windows-x64.zip"
PORTABLE_ZIP="$(find "${DIST_DIR}" -maxdepth 1 -type f -name 'circuit-bastion-v*.zip' -print -quit)"
SEA_LINUX_ZIP="${DIST_DIR}/circuit-bastion-linux-x64.zip"
SEA_WINDOWS_ZIP="${DIST_DIR}/circuit-bastion-windows-x64.zip"

for artifact in "$APK" "$LINUX_ZIP" "$WINDOWS_ZIP" "$SEA_LINUX_ZIP" "$SEA_WINDOWS_ZIP" "$PORTABLE_ZIP"; do
  test -n "$artifact"
  test -s "$artifact"
done
test "$(stat -c %s "$APK")" -le 104857600
unzip -tq "$APK" >/dev/null

zip_has() {
  local archive="$1"
  local entry="$2"
  unzip -Z1 "$archive" | grep -Fx "$entry" >/dev/null
}

zip_has "$LINUX_ZIP" "circuit-bastion-godot-linux-x64/circuit-bastion-linux-x86_64"
zip_has "$LINUX_ZIP" "circuit-bastion-godot-linux-x64/VERSION.txt"
zip_has "$WINDOWS_ZIP" "circuit-bastion-godot-windows-x64/circuit-bastion-windows-x86_64.exe"
zip_has "$WINDOWS_ZIP" "circuit-bastion-godot-windows-x64/VERSION.txt"

portable_root="$(basename "$PORTABLE_ZIP" .zip)"
zip_has "$PORTABLE_ZIP" "${portable_root}/index.html"
zip_has "$PORTABLE_ZIP" "${portable_root}/server.mjs"
zip_has "$PORTABLE_ZIP" "${portable_root}/launch.sh"
zip_has "$PORTABLE_ZIP" "${portable_root}/launch.cmd"
zip_has "$PORTABLE_ZIP" "${portable_root}/README.md"
zip_has "$PORTABLE_ZIP" "${portable_root}/RUNNING.md"

zip_has "$SEA_LINUX_ZIP" "circuit-bastion-linux-x64/circuit-bastion-linux-x64"
zip_has "$SEA_LINUX_ZIP" "circuit-bastion-linux-x64/README.md"
zip_has "$SEA_LINUX_ZIP" "circuit-bastion-linux-x64/RUNNING.md"
zip_has "$SEA_WINDOWS_ZIP" "circuit-bastion-windows-x64/circuit-bastion-windows-x64.exe"
zip_has "$SEA_WINDOWS_ZIP" "circuit-bastion-windows-x64/README.md"
zip_has "$SEA_WINDOWS_ZIP" "circuit-bastion-windows-x64/RUNNING.md"

echo "RELEASE_ASSETS_OK apk=$(stat -c %s "$APK") linux=$(stat -c %s "$LINUX_ZIP") windows=$(stat -c %s "$WINDOWS_ZIP") portable=$(stat -c %s "$PORTABLE_ZIP") sea_linux=$(stat -c %s "$SEA_LINUX_ZIP") sea_windows=$(stat -c %s "$SEA_WINDOWS_ZIP")"
