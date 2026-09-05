#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAPPING_FILE="$ROOT/steam/ns2pro.mapping"
CFG="$HOME/Library/Application Support/Steam/config/config.vdf"

if pgrep -x steam_osx >/dev/null; then
    echo "Steam запущен — закрой его полностью (Steam → Quit Steam) и запусти скрипт снова." >&2
    exit 1
fi
[ -f "$CFG" ] || { echo "Не найден $CFG" >&2; exit 1; }

BACKUP="$CFG.bak-ns2-$(date +%Y%m%d-%H%M%S)"
cp "$CFG" "$BACKUP"
echo "==> Бэкап: $BACKUP"

MAPPING_FILE="$MAPPING_FILE" CFG="$CFG" python3 - <<'PYEOF'
import os
cfg = os.environ["CFG"]
mapping = open(os.environ["MAPPING_FILE"], encoding="utf-8").read().strip().split("\n")
value = "\\n".join(line.replace('"', "'") for line in mapping)
text = open(cfg, encoding="utf-8").read()
key = '"SDL_GamepadBind"'
spans = []
pos = 0
while True:
    i = text.find(key, pos)
    if i < 0:
        break
    line_start = text.rfind("\n", 0, i) + 1
    q1 = text.find('"', i + len(key))
    j = q1 + 1
    while j < len(text):
        if text[j] == "\\":
            j += 2
            continue
        if text[j] == '"':
            break
        j += 1
    line_end = text.find("\n", j)
    line_end = len(text) if line_end < 0 else line_end + 1
    spans.append((line_start, line_end))
    pos = line_end
for line_start, line_end in reversed(spans):
    text = text[:line_start] + text[line_end:]
head = '"InstallConfigStore"\n{\n'
if not text.startswith(head):
    raise SystemExit("Неожиданный формат config.vdf, ничего не менял")
text = head + f'\t"SDL_GamepadBind"\t\t"{value}"\n' + text[len(head):]
print(f"==> Удалил старых записей SDL_GamepadBind: {len(spans)}, записал одну новую")
open(cfg, "w", encoding="utf-8").write(text)
PYEOF
echo "==> Готово. Запусти Steam."
