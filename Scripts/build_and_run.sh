#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PET_NAME="DeskPet"
LAUNCHER_NAME="DeskPetLauncher"
PET_BUNDLE_ID="com.local.DeskPet"
LAUNCHER_BUNDLE_ID="com.local.DeskPetLauncher"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"

cd "$ROOT_DIR"

stage_app() {
  local app_name="$1"
  local bundle_id="$2"
  local build_binary="$3"
  local app_bundle="$DIST_DIR/$app_name.app"
  local app_contents="$app_bundle/Contents"
  local app_macos="$app_contents/MacOS"
  local app_binary="$app_macos/$app_name"
  local info_plist="$app_contents/Info.plist"

  rm -rf "$app_bundle"
  mkdir -p "$app_macos"
  cp "$build_binary" "$app_binary"
  chmod +x "$app_binary"

  cat >"$info_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$app_name</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundleName</key>
  <string>$app_name</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

build_apps() {
  swift build
  local bin_path
  bin_path="$(swift build --show-bin-path)"
  mkdir -p "$DIST_DIR"
  stage_app "$PET_NAME" "$PET_BUNDLE_ID" "$bin_path/$PET_NAME"
  stage_app "$LAUNCHER_NAME" "$LAUNCHER_BUNDLE_ID" "$bin_path/$LAUNCHER_NAME"
}

open_pet() {
  /usr/bin/open -n "$DIST_DIR/$PET_NAME.app"
}

open_launcher() {
  /usr/bin/open -n "$DIST_DIR/$LAUNCHER_NAME.app"
}

pkill -x "$PET_NAME" >/dev/null 2>&1 || true
pkill -x "$LAUNCHER_NAME" >/dev/null 2>&1 || true

build_apps

case "$MODE" in
  --stage|stage)
    ;;
  run)
    open_launcher
    ;;
  --pet|pet)
    open_pet
    ;;
  --debug|debug)
    lldb -- "$DIST_DIR/$PET_NAME.app/Contents/MacOS/$PET_NAME"
    ;;
  --launcher-debug|launcher-debug)
    lldb -- "$DIST_DIR/$LAUNCHER_NAME.app/Contents/MacOS/$LAUNCHER_NAME"
    ;;
  --logs|logs)
    open_launcher
    /usr/bin/log stream --info --style compact --predicate "process == \"$PET_NAME\" OR process == \"$LAUNCHER_NAME\""
    ;;
  --telemetry|telemetry)
    open_launcher
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$PET_BUNDLE_ID\" OR subsystem == \"$LAUNCHER_BUNDLE_ID\""
    ;;
  --verify|verify)
    open_launcher
    sleep 1
    pgrep -x "$LAUNCHER_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--stage|--pet|--debug|--launcher-debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
