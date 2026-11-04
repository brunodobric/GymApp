#!/usr/bin/env bash
# Snimke zaslona za App Store: za svaki uređaj i jezik pokreće UI test ScreenshotTests s demo podacima
# i sprema slike u AppStore/screenshots/<jezik>/<uređaj>/.
# Pokretanje na Macu iz korijena repozitorija: scripts/snimke-zaslona.sh
# Uređaji se mogu zadati varijablama, npr. IPHONE="iPhone 17 Pro Max" scripts/snimke-zaslona.sh
# (popis simulatora: xcrun simctl list devices available).
set -euo pipefail
cd "$(dirname "$0")/.."

# App Store traži snimke za 6,9" iPhone i 13" iPad; ostale veličine App Store Connect izvodi iz njih.
IPHONE="${IPHONE:-iPhone 16 Pro Max}"
IPAD="${IPAD:-iPad Pro 13-inch (M4)}"
LANGUAGES="${LANGUAGES:-hr en}"
OUT="AppStore/screenshots"
RESULTS="build/screenshots"

xcodegen generate
rm -rf "$RESULTS"
mkdir -p "$RESULTS"

for device in "$IPHONE" "$IPAD"; do
    xcrun simctl boot "$device" 2>/dev/null || true
    xcrun simctl bootstatus "$device" -b >/dev/null
    # Uredan status bar kao na Appleovim snimkama.
    xcrun simctl status_bar "$device" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
        --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
    slug=$(echo "$device" | tr ' ' '-' | tr -cd '[:alnum:]-')
    for language in $LANGUAGES; do
        printf '\n==> %s, %s\n' "$device" "$language"
        result="$RESULTS/$slug-$language.xcresult"
        TEST_RUNNER_SCREENSHOT_LANGUAGE="$language" xcodebuild test \
            -project GymApp.xcodeproj -scheme GymApp \
            -destination "platform=iOS Simulator,name=$device" \
            -only-testing:GymAppUITests/ScreenshotTests \
            -resultBundlePath "$result" | tail -n 20
        target="$OUT/$language/$slug"
        rm -rf "$target"
        mkdir -p "$target"
        xcrun xcresulttool export attachments --path "$result" --output-path "$RESULTS/$slug-$language"
        python3 scripts/snimke_iz_rezultata.py "$RESULTS/$slug-$language" "$target"
    done
    xcrun simctl status_bar "$device" clear
done

printf '\nSnimke su u %s. Snimke sata: vidi AppStore/README.md.\n' "$OUT"
