#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP_NAME="NS2 Controller"
LABEL="com.p1rate.ns2controller"

./scripts/build-app.sh

if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
    echo "==> Stopping LaunchAgent $LABEL (the app takes over auto-wake)"
    launchctl bootout "gui/$(id -u)/$LABEL" || true
fi
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"

if pgrep -x NS2App >/dev/null; then
    echo "==> Quitting running app"
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || pkill -x NS2App || true
    for i in $(seq 1 20); do pgrep -x NS2App >/dev/null || break; perl -e 'select(undef,undef,undef,0.25)'; done
fi

echo "==> Installing /Applications/$APP_NAME.app"
rm -rf "/Applications/$APP_NAME.app"
cp -R "dist/$APP_NAME.app" "/Applications/"
open "/Applications/$APP_NAME.app"
echo "Done."
