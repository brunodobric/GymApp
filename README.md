# GymApp

iOS, iPadOS i watchOS aplikacija za bilježenje treninga (Swift + SwiftUI).

* [Specifikacija (v3)](docs/SPECIFIKACIJA.md)
* [Plan izrade](docs/PLAN_IZRADE.md)
* [Pravila dizajna (Apple HIG)](docs/DIZAJN.md)
* [Pravo i privatnost](docs/PRAVNO_I_PRIVATNOST.md)
* [Prototipi faze 0](docs/prototipi.md)

## Pokretanje

Potreban je Mac s aktualnim Xcodeom.

```sh
brew install xcodegen
xcodegen generate
open GymApp.xcodeproj
```

Prije pokretanja na uređaju odabrati svoj tim (Signing & Capabilities) za targete `GymApp`, `GymAppWatch` i `GymAppWidgets`, ili ga upisati kao `DEVELOPMENT_TEAM` u `project.yml`.

Testovi logike rade i bez Xcode projekta:

```sh
swift test --package-path Packages/GymKit
```
