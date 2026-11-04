#!/usr/bin/env bash
# Arhivira aplikaciju (iPhone, iPad i sat) i šalje build u App Store Connect za TestFlight.
# Pokretanje na Macu iz korijena repozitorija: scripts/testflight.sh
# Preduvjeti (docs/izdanje.md): plaćeni Apple Developer Program, tim u Config/Local.xcconfig bez
# Personal Team redaka, Apple račun prijavljen u Xcode > Settings > Accounts, aplikacija stvorena u App Store Connectu.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Ima necommitanih promjena. Build mora odgovarati commitu, pa prvo commitaj ili pospremi promjene." >&2
    exit 1
fi
if grep -q "^GYMAPP_ENTITLEMENTS_SUFFIX" Config/Local.xcconfig 2>/dev/null; then
    echo "Config/Local.xcconfig je postavljen za Personal Team, koji ne može na TestFlight. Obriši retke GYMAPP_*." >&2
    exit 1
fi
TEAM=$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' Config/Local.xcconfig 2>/dev/null | tr -d '[:space:]')
if [[ -z "$TEAM" ]]; then
    echo "Nema DEVELOPMENT_TEAM u Config/Local.xcconfig (vidi Config/Local.xcconfig.example)." >&2
    exit 1
fi

# Broj builda raste sa svakim commitom, pa je svaki upload jedinstven i vidi se iz kojeg je commita.
BUILD=$(git rev-list --count HEAD)
VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
ARCHIVE="build/Apolon-$VERSION-$BUILD.xcarchive"
OPTIONS="build/ExportOptions.plist"

printf '==> Apolon %s (%s), commit %s\n' "$VERSION" "$BUILD" "$(git rev-parse --short HEAD)"
xcodegen generate
mkdir -p build
cp Config/ExportOptions.plist "$OPTIONS"
/usr/libexec/PlistBuddy -c "Add :teamID string $TEAM" "$OPTIONS"

xcodebuild archive \
    -project GymApp.xcodeproj -scheme GymApp -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    CURRENT_PROJECT_VERSION="$BUILD" | tail -n 20

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" -exportPath "build/export" \
    -allowProvisioningUpdates | tail -n 20

printf '\nBuild %s (%s) je poslan. Za 10 do 30 minuta pojavi se u App Store Connect > TestFlight.\n' "$VERSION" "$BUILD"
