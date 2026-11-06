#!/usr/bin/env bash
# Priprema MoveKit dodatak i kopira ga u Resources/MoveKit/, odakle ulazi u build aplikacije.
# Pokretanje na Macu iz korijena repozitorija: scripts/movekit.sh
#
# 1. Tools/CatalogBuilder iz paketa (zadano ~/Documents/MoveKit, može MOVEKIT_DIR=...) radi privatnu mapu
#    <paket>/GymApp: texts.json (upute i česte greške) i Media/ (klipovi HEVC i posteri JPEG). Već pretvoreni
#    klipovi se preskaču, pa je samo prvo pokretanje sporo. Javni catalog.json se ovdje ne mijenja.
# 2. Privatna mapa se kopira u Resources/MoveKit/ (u .gitignore: licencirani sadržaj nikad ne ide u repozitorij).
#
# Detalji i licenca: docs/movekit.md.
set -euo pipefail
cd "$(dirname "$0")/.."

PACKAGE="${MOVEKIT_DIR:-$HOME/Documents/MoveKit}"
SOURCE="$PACKAGE/GymApp"
TARGET="Resources/MoveKit"

if ! compgen -G "$PACKAGE/*/metadata.json" > /dev/null; then
    echo "Nema MoveKit paketa u $PACKAGE (treba raspakirani paket s metadata.json). Vidi docs/movekit.md." >&2
    exit 1
fi
if ! command -v ffmpeg > /dev/null; then
    echo "Za pretvorbu klipova treba ffmpeg: brew install ffmpeg" >&2
    exit 1
fi

python3 Tools/CatalogBuilder/build_catalog.py --movekit "$PACKAGE" --no-public --media

mkdir -p "$TARGET/Media"
cp "$SOURCE/texts.json" "$TARGET/texts.json"
# --delete: klip koji je izbačen iz kataloga ne ostaje u buildu.
rsync -a --delete --exclude='.tmp-*' --include='*.mp4' --include='*.jpg' --exclude='*' "$SOURCE/Media/" "$TARGET/Media/"

videos=$(find "$TARGET/Media" -name '*.mp4' | wc -l | tr -d ' ')
posters=$(find "$TARGET/Media" -name '*.jpg' | wc -l | tr -d ' ')
size=$(du -sh "$TARGET" | cut -f1)
printf 'MoveKit: %s klipova, %s postera, %s u %s\n' "$videos" "$posters" "$size" "$TARGET"
