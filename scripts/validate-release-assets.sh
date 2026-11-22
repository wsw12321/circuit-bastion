#!/usr/bin/env bash
set -euo pipefail
DIST_DIR="${1:?usage: $0 <release-dist>}"
APK="${DIST_DIR}/circuit-bastion-android-arm64.apk"
LINUX_ZIP="${DIST_DIR}/circuit-bastion-godot-linux-x64.zip"
WINDOWS_ZIP="${DIST_DIR}/circuit-bastion-godot-windows-x64.zip"
for artifact in "$APK" "$LINUX_ZIP" "$WINDOWS_ZIP"; do test -s "$artifact"; done
test "$(stat -c %s "$APK")" -le 104857600
unzip -tq "$APK" >/dev/null
unzip -Z1 "$LINUX_ZIP" | grep -Fx "circuit-bastion-godot-linux-x64/circuit-bastion-linux-x86_64" >/dev/null
unzip -Z1 "$LINUX_ZIP" | grep -Fx "circuit-bastion-godot-linux-x64/VERSION.txt" >/dev/null
unzip -Z1 "$WINDOWS_ZIP" | grep -Fx "circuit-bastion-godot-windows-x64/circuit-bastion-windows-x86_64.exe" >/dev/null
unzip -Z1 "$WINDOWS_ZIP" | grep -Fx "circuit-bastion-godot-windows-x64/VERSION.txt" >/dev/null
echo "RELEASE_ASSETS_OK apk=$(stat -c %s "$APK") linux=$(stat -c %s "$LINUX_ZIP") windows=$(stat -c %s "$WINDOWS_ZIP")"
