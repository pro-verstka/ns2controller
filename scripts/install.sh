#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

LABEL="com.p1rate.ns2controller"
BIN_DIR="$HOME/.local/bin"
BIN="$BIN_DIR/ns2ctl"
LOG="$HOME/Library/Logs/ns2controller.log"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

echo "==> Building release binary"
swift build -c release 2>&1 | tail -n 3

mkdir -p "$BIN_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
    echo "==> Stopping running agent"
    launchctl bootout "gui/$(id -u)/$LABEL" || true
fi

echo "==> Installing $BIN"
install -m 755 ".build/release/ns2ctl" "$BIN"

echo "==> Installing $PLIST"
sed -e "s|__NS2CTL__|$BIN|g" -e "s|__LOG__|$LOG|g" "LaunchAgents/$LABEL.plist" > "$PLIST"

echo "==> Loading agent"
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL"
echo "Done. Log: $LOG"
