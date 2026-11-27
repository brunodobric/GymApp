#!/usr/bin/env bash
# Gradi potpisane AAB-ove mobitela i sata za Google Play, s MoveKit klipovima u paketu klipova (docs/android-izdanje.md).
# Pokretanje na Macu iz korijena repozitorija:
#
#   scripts/android-izdanje.sh          # AAB-ovi za upload u Play Console
#   scripts/android-izdanje.sh --apk    # uz to i univerzalni APK mobitela za izravno testiranje (treba bundletool)
#
# Treba: Android SDK (ANDROID_HOME ili android/local.properties), ffmpeg, MoveKit izlaz (scripts/movekit.sh) i upload
# ključ. Putanja i lozinke ključa su u ~/.gradle/gradle.properties (apolon.keystore, apolon.keystorePassword,
# apolon.keyAlias, apolon.keyPassword) ili u okolini (APOLON_KEYSTORE, ...). Ključ nikad ne ide u repozitorij.
# AAB i APK s MoveKit sadržajem ne smiju se dijeliti javno (docs/movekit.md).
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${ANDROID_HOME:-}" && ! -f android/local.properties ]]; then
    echo "Za build treba Android SDK: instaliraj Android Studio i postavi ANDROID_HOME." >&2
    exit 1
fi
if [[ -z "${APOLON_KEYSTORE:-}" ]] && ! grep -qs '^apolon.keystore=' "$HOME/.gradle/gradle.properties"; then
    echo "Nema upload ključa: dodaj apolon.keystore i lozinke u ~/.gradle/gradle.properties (docs/android-izdanje.md)." >&2
    exit 1
fi

if compgen -G "Resources/MoveKit/Media/*.jpg" > /dev/null; then
    scripts/movekit-android.sh
else
    echo "Upozorenje: nema MoveKit sadržaja (scripts/movekit.sh), AAB ide bez klipova i uputa." >&2
fi

(cd android && ./gradlew :app:bundleRelease :wear:bundleRelease --console=plain)

PHONE="android/app/build/outputs/bundle/release/app-release.aab"
WATCH="android/wear/build/outputs/bundle/release/wear-release.aab"
version=$(grep '^apolon.versionName=' android/gradle.properties | cut -d= -f2)
code=$(grep '^apolon.versionCode=' android/gradle.properties | cut -d= -f2)
printf 'Verzija %s (versionCode mobitel %s, sat %s)\n' "$version" "$((code * 10))" "$((code * 10 + 1))"
printf 'Mobitel: %s (%s)\nSat:     %s (%s)\n' "$PHONE" "$(du -h "$PHONE" | cut -f1)" "$WATCH" "$(du -h "$WATCH" | cut -f1)"

if [[ "${1:-}" == "--apk" ]]; then
    if ! command -v bundletool > /dev/null; then
        echo "Za univerzalni APK treba bundletool: brew install bundletool" >&2
        exit 1
    fi
    props="$HOME/.gradle/gradle.properties"
    prop() { grep "^$1=" "$props" 2>/dev/null | cut -d= -f2- || true; }
    keystore="${APOLON_KEYSTORE:-$(prop apolon.keystore)}"
    keystore="${keystore/#\~/$HOME}"
    alias="${APOLON_KEY_ALIAS:-$(prop apolon.keyAlias)}"
    out="android/app/build/outputs/apolon-universal.apks"
    bundletool build-apks --overwrite --mode=universal --bundle="$PHONE" --output="$out" \
        --ks="$keystore" --ks-pass="pass:${APOLON_KEYSTORE_PASSWORD:-$(prop apolon.keystorePassword)}" \
        --ks-key-alias="${alias:-upload}" --key-pass="pass:${APOLON_KEY_PASSWORD:-$(prop apolon.keyPassword)}"
    unzip -o -q "$out" universal.apk -d android/app/build/outputs/
    mv android/app/build/outputs/universal.apk android/app/build/outputs/apolon-universal.apk
    echo "Univerzalni APK: android/app/build/outputs/apolon-universal.apk (samo poimence odabranim testerima)"
fi
