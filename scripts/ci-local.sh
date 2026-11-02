#!/usr/bin/env bash
# Lokalna kopija CI-ja (.github/workflows/ci.yml): isti koraci, bez čekanja u redu na GitHubu.
# Pokretanje iz korijena repozitorija: scripts/ci-local.sh
# Argument "brzo" preskače buildove aplikacije (samo lint i testovi).
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n==> %s\n' "$1"; }

step "SwiftLint"
swiftlint lint --quiet

step "Testovi CatalogBuildera"
python3 -m unittest discover -s Tools/CatalogBuilder

step "Testovi paketa GymKit"
swift test --package-path Packages/GymKit

if [[ "${1:-}" == "brzo" ]]; then
    echo "Preskačem buildove aplikacije (brzo)."
    exit 0
fi

step "Generiranje projekta"
xcodegen generate

step "Build iOS (simulator)"
xcodebuild build -project GymApp.xcodeproj -scheme GymApp -configuration Debug \
    -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO | tail -n 60

step "Build watchOS (simulator)"
xcodebuild build -project GymApp.xcodeproj -scheme GymAppWatch -configuration Debug \
    -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO | tail -n 60

step "Build iOS za besplatni Personal Team (simulator)"
xcodebuild build -project GymApp.xcodeproj -scheme GymApp -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    GYMAPP_ENTITLEMENTS_SUFFIX=-PersonalTeam GYMAPP_EXTRA_CONDITIONS=PERSONAL_TEAM \
    CODE_SIGNING_ALLOWED=NO | tail -n 60

echo
echo "Sve provjere su prošle."
