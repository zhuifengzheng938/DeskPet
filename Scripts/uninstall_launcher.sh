#!/usr/bin/env bash
set -euo pipefail

PLIST_PATH="$HOME/Library/LaunchAgents/com.local.DeskPetLauncher.plist"

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH"
pkill -x DeskPetLauncher >/dev/null 2>&1 || true

echo "Uninstalled DeskPet launcher."
