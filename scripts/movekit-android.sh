#!/usr/bin/env bash
# Kopira MoveKit postere u Android build, odakle ih čitaju kartice vrsta u katalogu.
# Pokretanje na Macu iz korijena repozitorija, nakon scripts/movekit.sh:
#
#   scripts/movekit-android.sh          # samo kopira postere
#   scripts/movekit-android.sh --apk    # kopira postere i gradi debug APK (treba Android SDK, npr. iz Android Studija)
#
# Izvor je Resources/MoveKit/Media/ (izlaz scripts/movekit.sh), a cilj android/app/src/main/assets/movekit/Media/.
# Obje mape su u .gitignore: licencirani sadržaj nikad ne ide u repozitorij. APK s posterima smije se dati samo
# poimence odabranim testerima, nikad preko javne poveznice (docs/movekit.md, docs/android.md odjeljak 9).
# Klipovi se zasad ne kopiraju: Android još nema klip na detalju vježbe, a HEVC ne podržava svaki uređaj.
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="Resources/MoveKit/Media"
TARGET="android/app/src/main/assets/movekit/Media"

if ! compgen -G "$SOURCE/*.jpg" > /dev/null; then
    echo "Nema postera u $SOURCE. Prvo pokreni scripts/movekit.sh (vidi docs/movekit.md)." >&2
    exit 1
fi

mkdir -p "$TARGET"
# --delete: poster vježbe koja je izbačena iz kataloga ne ostaje u buildu.
rsync -a --delete --include='*.jpg' --exclude='*' "$SOURCE/" "$TARGET/"

posters=$(find "$TARGET" -name '*.jpg' | wc -l | tr -d ' ')
size=$(du -sh "$TARGET" | cut -f1)
printf 'MoveKit za Android: %s postera, %s u %s\n' "$posters" "$size" "$TARGET"

if [[ "${1:-}" == "--apk" ]]; then
    if [[ -z "${ANDROID_HOME:-}" && ! -f android/local.properties ]]; then
        echo "Za build treba Android SDK: instaliraj Android Studio i postavi ANDROID_HOME." >&2
        exit 1
    fi
    (cd android && ./gradlew :app:assembleDebug --console=plain)
    echo "APK: android/app/build/outputs/apk/debug/$(ls android/app/build/outputs/apk/debug | grep '\.apk$' | head -1)"
fi
