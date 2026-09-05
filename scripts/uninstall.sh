#!/bin/bash
set -euo pipefail
LABEL="com.p1rate.ns2controller"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN="$HOME/.local/bin/ns2ctl"

if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
    echo "==> Stopping agent"
    launchctl bootout "gui/$(id -u)/$LABEL" || true
fi
rm -f "$PLIST" "$BIN"
echo "Removed agent and binary. Log kept at ~/Library/Logs/ns2controller.log"
