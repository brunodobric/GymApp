# GymApp

iOS, iPadOS i watchOS aplikacija za bilježenje treninga. Swift + SwiftUI, SwiftData, CloudKit, HealthKit, WatchConnectivity.

## Dokumenti

* `docs/SPECIFIKACIJA.md`: što aplikacija radi (izvor istine za funkcionalnost)
* `docs/PLAN_IZRADE.md`: faze, redoslijed i kriteriji "gotovo kad"
* `docs/DIZAJN.md`: pravila Apple HIG-a za ovu aplikaciju
* `docs/PRAVNO_I_PRIVATNOST.md`: privatnost, licence, App Store pravila
* `docs/prototipi.md`: prototipi faze 0 i nalazi
* `docs/sinkronizacija.md`: iCloud sinkronizacija, objava CloudKit sheme i provjera na uređajima
* `docs/performanse.md`: signposti, ciljevi i mjerenje performansi u Instrumentsu
* `docs/izdanje.md`: TestFlight beta, greške iz bete i slanje na App Store review
* `docs/lokalizacija.md`: String Catalog (hr i en), pisanje teksta u kodu i provjera prijevoda na CI-ju
* `docs/movekit.md`: MoveKit katalog vježbi, licenca i što smije u javni repozitorij
* `docs/widgeti.md`: widgeti, kontrola "Započni trening" i komplikacije: snimka u App Groupu i osvježavanje

Dokumentacija, komentari u kodu i commit poruke pišu se na hrvatskom. Nazivi tipova, funkcija i varijabli su na engleskom.

## Struktura

* `project.yml`: XcodeGen specifikacija. `GymApp.xcodeproj` se ne commita, generira se s `xcodegen generate`.
* `Config/`: xcconfig datoteke za potpisivanje. Tim je u `Config/Local.xcconfig` (ne commita se). Entitlements su datoteke u `App/` i `WatchApp/`, a `GymApp-PersonalTeam.entitlements` je verzija bez iCloud i push za besplatni tim (uvjet kompajliranja `PERSONAL_TEAM`).
* `App/`: iPhone i iPad aplikacija
* `WatchApp/`: watchOS aplikacija
* `Widgets/`: Live Activity, widgeti na početnom i zaključanom zaslonu i kontrola "Započni trening"
* `WatchWidgets/`: komplikacije na satu
* `UITests/`: UI test koji radi snimke zaslona za App Store (`scripts/snimke-zaslona.sh`)
* `Shared/Common/`: kod koji dijele iPhone i Watch
* `Shared/LiveActivity/`: kod koji dijele aplikacija i widget extension
* `Shared/Design/`: stilovi fontova (`AppFont`) koje dijele aplikacija, widgeti i sat
* `Packages/GymKit/`: logika bez sučelja, s unit testovima (Swift Testing)
* `Resources/Catalog/`: javni katalog vježbi (`catalog.json`, gradi ga `Tools/CatalogBuilder`)
* `Resources/MoveKit/`: licencirani MoveKit klipovi i upute, ne commita se (`scripts/movekit.sh`)
* `AppStore/`: tekstovi za App Store Connect (hr i en), napomena za review i snimke zaslona. Duljine provjerava CI.
* `site/`: pravila privatnosti i podrška (GitHub Pages)

## Pravila

* **Logika ide u `GymKit`**, ne u viewove. Svaka nova logika dobiva testove.
* **Tekst za korisnika ide kroz String Catalog** (`docs/lokalizacija.md`): svaki novi tekst dobiva engleski prijevod u `Resources/Localization/Localizable.xcstrings`, inače CI pada.
* **Težina se uvijek sprema u kg** (`Units`). Pretvorba u lbs samo za prikaz i unos.
* **SwiftData modeli koji se sinkroniziraju poštuju pravila CloudKita:** svako svojstvo opcionalno ili sa zadanom vrijednošću, bez `@Attribute(.unique)`, opcionalne relacije, redoslijed u `orderIndex`. Shema se nakon izdanja samo proširuje.
* **Bez SDK-ova trećih strana** i bez vanjskih resursa (fontovi, CDN, analitika). Svaka nova ovisnost ide u `docs/PRAVNO_I_PRIVATNOST.md` s licencom.
* **Dizajn prema `docs/DIZAJN.md`:** sistemske komponente, tab bar samo za navigaciju, Dynamic Type, iPad preko size classa.
* **MoveKit sadržaj nikad ne ide u repozitorij** (klipovi, posteri, upute, česte greške i njihovi prijevodi): `docs/movekit.md`.
* Debug-only kod (prototipi, alati) ide unutar `#if DEBUG`.

## Naredbe

```sh
brew install xcodegen swiftlint
xcodegen generate                              # generira GymApp.xcodeproj
scripts/movekit.sh                             # MoveKit klipovi i upute u build (na Macu, treba ffmpeg)
scripts/testflight.sh                          # arhiva i upload za TestFlight (na Macu)
swift test --package-path Packages/GymKit      # testovi logike
swiftlint lint
```

CI (`.github/workflows/ci.yml`) na svaki push i PR pokreće SwiftLint, testove paketa te build za iOS i watchOS simulator.
