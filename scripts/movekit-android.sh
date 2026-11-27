#!/usr/bin/env bash
# Priprema MoveKit klipove, postere i upute za Android build: kartice vrsta u katalogu čitaju postere, a detalj
# vježbe klip i upute.
# Pokretanje na Macu iz korijena repozitorija, nakon scripts/movekit.sh:
#
#   scripts/movekit-android.sh          # samo priprema MoveKit sadržaj
#   scripts/movekit-android.sh --apk    # priprema sadržaj i gradi debug APK (treba Android SDK, npr. iz Android Studija)
#
# Izvor je Resources/MoveKit/ (izlaz scripts/movekit.sh), a cilj paket klipova android/movekit/src/main/assets/movekit/
# (install-time asset pack za Google Play, docs/android-izdanje.md). Debug APK uzima istu mapu kao obične assete.
# Obje mape su u .gitignore: licencirani sadržaj nikad ne ide u repozitorij. APK s MoveKit sadržajem smije se dati samo
# poimence odabranim testerima, nikad preko javne poveznice (docs/movekit.md, docs/android.md odjeljak 9).
#
# Klipovi su na iOS-u HEVC, a za Android se pretvaraju u H.264 (High profil, yuv420p, bez zvuka), jer hardverski HEVC
# dekoder nije zajamčen na svim Android mobitelima. Pretvara se samo klip koji je noviji od već pretvorenog.
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="Resources/MoveKit"
TARGET="android/movekit/src/main/assets/movekit"
OLD_TARGET="android/app/src/main/assets/movekit"

if ! compgen -G "$SOURCE/Media/*.jpg" > /dev/null; then
    echo "Nema postera u $SOURCE/Media. Prvo pokreni scripts/movekit.sh (vidi docs/movekit.md)." >&2
    exit 1
fi
if ! command -v ffmpeg > /dev/null; then
    echo "Za pretvorbu klipova u H.264 treba ffmpeg: brew install ffmpeg" >&2
    exit 1
fi

# Stara lokacija (prije paketa klipova) bi sadržaj stavila i u osnovni modul.
if [[ -d "$OLD_TARGET" ]]; then
    echo "Uklanjam staru mapu $OLD_TARGET (sadržaj je sada u paketu klipova)."
    rm -rf "$OLD_TARGET"
fi

mkdir -p "$TARGET/Media"
if [[ -f "$SOURCE/texts.json" ]]; then cp "$SOURCE/texts.json" "$TARGET/texts.json"; fi
# --delete: poster vježbe koja je izbačena iz kataloga ne ostaje u buildu. Klipovi se pretvaraju ispod.
rsync -a --delete --include='*.jpg' --exclude='*' "$SOURCE/Media/" "$TARGET/Media/"

converted=0
for source in "$SOURCE"/Media/*.mp4; do
    [[ -e "$source" ]] || continue
    target="$TARGET/Media/$(basename "$source")"
    if [[ -f "$target" && "$target" -nt "$source" ]]; then continue; fi
    tmp="$TARGET/Media/.tmp-$(basename "$source")"
    ffmpeg -nostdin -loglevel error -y -i "$source" -map 0:v:0 -an \
        -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -preset slow -crf 24 -profile:v high -pix_fmt yuv420p -movflags +faststart -f mp4 "$tmp"
    mv "$tmp" "$target"
    converted=$((converted + 1))
done
# Klip kojem je izvor obrisan iz kataloga.
for target in "$TARGET"/Media/*.mp4; do
    [[ -e "$target" ]] || continue
    [[ -f "$SOURCE/Media/$(basename "$target")" ]] || rm -f "$target"
done

videos=$(find "$TARGET/Media" -name '*.mp4' | wc -l | tr -d ' ')
posters=$(find "$TARGET/Media" -name '*.jpg' | wc -l | tr -d ' ')
size=$(du -sh "$TARGET" | cut -f1)
printf 'MoveKit za Android: %s klipova (%s pretvoreno sada), %s postera, %s u %s\n' "$videos" "$converted" "$posters" "$size" "$TARGET"

if [[ "${1:-}" == "--apk" ]]; then
    if [[ -z "${ANDROID_HOME:-}" && ! -f android/local.properties ]]; then
        echo "Za build treba Android SDK: instaliraj Android Studio i postavi ANDROID_HOME." >&2
        exit 1
    fi
    (cd android && ./gradlew :app:assembleDebug --console=plain)
    echo "APK: android/app/build/outputs/apk/debug/$(ls android/app/build/outputs/apk/debug | grep '\.apk$' | head -1)"
fi
