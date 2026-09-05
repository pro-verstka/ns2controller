#!/bin/bash
set -euo pipefail
MAPPING_FILE="$(cd "$(dirname "$0")/.." && pwd)/steam/ns2pro.mapping"
if pgrep -x steam_osx >/dev/null; then
    echo "Steam уже запущен — закрой его полностью (Steam → Quit Steam), иначе маппинг не применится." >&2
    exit 1
fi
export SDL_GAMECONTROLLERCONFIG="$(cat "$MAPPING_FILE")"
exec /Applications/Steam.app/Contents/MacOS/steam_osx "$@"
