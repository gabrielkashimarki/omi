#!/bin/bash
# Fork: embute o motor do Atticus (~/atticus-mac) dentro do Omi Fork.app instalado, em
# Contents/Resources/atticus, e reassina o app (ad hoc, como o resto do fork).
# Uso: embutir-atticus.sh [caminho do Omi Fork.app] [caminho do atticus-mac]
set -euo pipefail
APP="${1:-$HOME/Applications/Omi Fork.app}"
SRC="${2:-$HOME/atticus-mac}"
DEST="$APP/Contents/Resources/atticus"
[ -f "$SRC/Atticus.swift" ] || { echo "Não achei $SRC/Atticus.swift"; exit 1; }
[ -d "$APP/Contents" ] || { echo "Não achei $APP"; exit 1; }
STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
# erro de compilação não pode deixar o app pela metade
swiftc -O -target "$(uname -m)-apple-macos26.0" "$SRC/Atticus.swift" -o "$STAGE/Atticus"
rm -rf "$DEST"; mkdir -p "$DEST/ui"
cp "$SRC/atticus.py" "$SRC/VERSION" "$DEST/"
cp "$SRC"/ui/*.html "$SRC"/ui/*.js "$DEST/ui/"
# MIT: o aviso de copyright do Atticus vai junto do motor
cp "$SRC/LICENSE" "$DEST/LICENSE"
# Mapa pt do copiloto de reunião (versionado no Omi) entra no i18n.js do Atticus sem editar o original
python3 - "$DEST/ui/i18n.js" "$(dirname "$0")/atticus-ui/i18n-pt.json" <<'PY'
import sys
js, pt = sys.argv[1], open(sys.argv[2], encoding="utf-8").read().strip()
s = open(js, encoding="utf-8").read()
assert "const maps = {" in s, "i18n.js do Atticus mudou de formato"
open(js, "w", encoding="utf-8").write(s.replace("const maps = {", 'const maps = {\n  "pt": ' + pt + ",", 1))
PY
mv "$STAGE/Atticus" "$DEST/Atticus"
codesign -s - --force "$DEST/Atticus"
codesign -s - --force --deep "$APP"
echo "Atticus $(cat "$SRC/VERSION") embutido em $DEST"
