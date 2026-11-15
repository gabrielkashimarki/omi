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
mv "$STAGE/Atticus" "$DEST/Atticus"
codesign -s - --force "$DEST/Atticus"
codesign -s - --force --deep "$APP"
echo "Atticus $(cat "$SRC/VERSION") embutido em $DEST"
