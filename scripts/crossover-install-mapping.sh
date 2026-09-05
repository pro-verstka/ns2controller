#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOTTLE="${1:-}"
[ -n "$BOTTLE" ] || { echo "usage: $0 <bottle-name>  (см. ~/Library/Application Support/CrossOver/Bottles)" >&2; exit 1; }
BOTTLE_DIR="$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE"
CONF="$BOTTLE_DIR/cxbottle.conf"
[ -f "$CONF" ] || { echo "Бутылка не найдена: $BOTTLE_DIR" >&2; exit 1; }
WINE=""
for app in "/Applications/CrossOver.app" "/Applications/CrossOver Preview.app"; do
    [ -x "$app/Contents/SharedSupport/CrossOver/bin/wine" ] && WINE="$app/Contents/SharedSupport/CrossOver/bin/wine"
done
[ -n "$WINE" ] || { echo "CrossOver не найден" >&2; exit 1; }

MAPPING="$(sed -n 1p "$ROOT/steam/ns2pro.mapping")"
cp "$CONF" "$CONF.bak-ns2-$(date +%Y%m%d-%H%M%S)"
MAPPING="$MAPPING" CONF="$CONF" python3 - <<'PYEOF'
import os, re
path = os.environ["CONF"]
mapping = os.environ["MAPPING"]
text = open(path, encoding="utf-8").read()
text = re.sub(r'^"SDL_GAMECONTROLLERCONFIG" = .*\n', "", text, flags=re.M)
marker = "[EnvironmentVariables]\n"
if marker not in text:
    text = text.rstrip("\n") + "\n\n" + marker
i = text.index(marker) + len(marker)
text = text[:i] + f'"SDL_GAMECONTROLLERCONFIG" = "{mapping}"\n' + text[i:]
open(path, "w", encoding="utf-8").write(text)
PYEOF
echo "==> SDL_GAMECONTROLLERCONFIG записан в $CONF"

echo "==> Удаляю ключ winebus\\map, если есть (в Wine он роняет winebus)"
"$WINE" --bottle "$BOTTLE" reg delete 'HKLM\System\CurrentControlSet\Services\winebus\map' /f >/dev/null 2>&1 || true
echo "==> Готово. Перезапусти бутылку (закрой все её Windows-программы) и запусти игру."
