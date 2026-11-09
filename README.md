# GymApp

iOS, iPadOS i watchOS aplikacija za bilježenje treninga (Swift + SwiftUI).

Korisnici aplikaciju vide pod imenom **Apolon** (`CFBundleDisplayName` u `project.yml`). Interno ime projekta, targeta i sheme ostaje GymApp. Ikona je u `App/Assets.xcassets` i `WatchApp/Assets.xcassets` (jedna slika 1024×1024 bez prozirnosti). Ruka zauzima oko 63 % širine i 71 % visine i stane u krug promjera 81 % platna, pa se ne reže ni u zaobljenom kvadratu na iPhoneu ni u krugu na satu.

* [Specifikacija (v3)](docs/SPECIFIKACIJA.md)
* [Plan izrade](docs/PLAN_IZRADE.md)
* [Pravila dizajna (Apple HIG)](docs/DIZAJN.md)
* [Pravo i privatnost](docs/PRAVNO_I_PRIVATNOST.md)

## Pokretanje

Potreban je Mac s aktualnim Xcodeom.

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig   # upisati svoj Team ID
brew install xcodegen
xcodegen generate
open GymApp.xcodeproj
```

Tim se upisuje u `Config/Local.xcconfig`, a ne u Xcodeu, kako se ne bi izgubio pri ponovnom generiranju. Za besplatni Personal Team u toj datoteci ostaviti retke koji isključuju iCloud i push (vidi komentare u primjeru).

Testovi logike rade i bez Xcode projekta:

```sh
swift test --package-path Packages/GymKit
```
