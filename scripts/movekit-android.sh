#!/usr/bin/env bash
# Kopira MoveKit klipove, postere i upute u Android build: kartice vrsta u katalogu čitaju postere, a detalj
# vježbe klip i upute.
# Pokretanje na Macu iz korijena repozitorija, nakon scripts/movekit.sh:
#
#   scripts/movekit-android.sh          # samo kopira MoveKit sadržaj
#   scripts/movekit-android.sh --apk    # kopira sadržaj i gradi debug APK (treba Android SDK, npr. iz Android Studija)
#
# Izvor je Resources/MoveKit/ (izlaz scripts/movekit.sh), a cilj android/app/src/main/assets/movekit/.
# Obje mape su u .gitignore: licencirani sadržaj nikad ne ide u repozitorij. APK s MoveKit sadržajem smije se dati samo
# poimence odabranim testerima, nikad preko javne poveznice (docs/movekit.md, docs/android.md odjeljak 9).
# Klipovi su HEVC kao na iOS-u; Android ga dekodira od verzije 5 (softverski dekoder je dio sustava).
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="Resources/MoveKit"
TARGET="android/app/src/main/assets/movekit"

if ! compgen -G "$SOURCE/Media/*.jpg" > /dev/null; then
    echo "Nema postera u $SOURCE/Media. Prvo pokreni scripts/movekit.sh (vidi docs/movekit.md)." >&2
    exit 1
fi

mkdir -p "$TARGET/Media"
if [[ -f "$SOURCE/texts.json" ]]; then cp "$SOURCE/texts.json" "$TARGET/texts.json"; fi
# --delete: klip ili poster vježbe koja je izbačena iz kataloga ne ostaje u buildu.
rsync -a --delete --include='*.mp4' --include='*.jpg' --exclude='*' "$SOURCE/Media/" "$TARGET/Media/"

videos=$(find "$TARGET/Media" -name '*.mp4' | wc -l | tr -d ' ')
posters=$(find "$TARGET/Media" -name '*.jpg' | wc -l | tr -d ' ')
size=$(du -sh "$TARGET" | cut -f1)
printf 'MoveKit za Android: %s klipova, %s postera, %s u %s\n' "$videos" "$posters" "$size" "$TARGET"

if [[ "${1:-}" == "--apk" ]]; then
    if [[ -z "${ANDROID_HOME:-}" && ! -f android/local.properties ]]; then
        echo "Za build treba Android SDK: instaliraj Android Studio i postavi ANDROID_HOME." >&2
        exit 1
    fi
    (cd android && ./gradlew :app:assembleDebug --console=plain)
    echo "APK: android/app/build/outputs/apk/debug/$(ls android/app/build/outputs/apk/debug | grep '\.apk$' | head -1)"
fi
