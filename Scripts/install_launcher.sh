#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_PATH="$HOME/Library/LaunchAgents/com.local.DeskPetLauncher.plist"
LAUNCHER_APP="$ROOT_DIR/dist/DeskPetLauncher.app"
LAUNCHER_BINARY="$LAUNCHER_APP/Contents/MacOS/DeskPetLauncher"

cd "$ROOT_DIR"
"$ROOT_DIR/Scripts/build_and_run.sh" --stage

mkdir -p "$(dirname "$PLIST_PATH")"

cat >"$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.local.DeskPetLauncher</string>
  <key>ProgramArguments</key>
  <array>
    <string>$LAUNCHER_BINARY</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/DeskPetLauncher.out.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/DeskPetLauncher.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl kickstart -k "gui/$(id -u)/com.local.DeskPetLauncher"

echo "Installed DeskPet launcher: $PLIST_PATH"
echo "Press Control + Option + D to start or toggle DeskPet."
