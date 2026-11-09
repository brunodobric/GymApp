# Lokalizacija (hrvatski i engleski)

Aplikacija je na hrvatskom i engleskom. Izvorni jezik je hrvatski: tekst u kodu je hrvatski i ujedno je ključ u String Catalogu, a engleski je prijevod.

## Datoteke

* `Resources/Localization/Localizable.xcstrings`: svi tekstovi sučelja. Jedan katalog dijele sva četiri targeta (iPhone i iPad, Watch, Live Activity, complications), pa se tekst koji se ponavlja prevodi jednom.
* `App/InfoPlist.xcstrings` i `WatchApp/InfoPlist.xcstrings`: opisi dozvola za Zdravlje. Odvojeni su jer iPhone i sat traže različite dozvole.
* `App/AppShortcuts.xcstrings`: fraze za Prečace i Siri (`GymAppShortcuts`). Ključ je prva fraza akcije, a svaki jezik ima popis fraza (`stringSet`). Svaka fraza mora sadržavati `${applicationName}`, a parametar se piše kao `${workout}`.
* Katalog vježbi (`Resources/Catalog/catalog.json`) ima nazive i upute po jeziku. Prijevodi su u `Tools/CatalogBuilder/translations/hr.json`, a katalog ih bira prema jeziku sučelja aplikacije (`CatalogStore.language`), ne prema regiji uređaja.

## Pisanje teksta u kodu

* `Text("…")`, `Button("…")`, `Label`, `Section`, `navigationTitle` i ostali SwiftUI inicijalizatori s literalom već su lokalizirani.
* Tekst koji se gradi u kodu ide kroz `String(localized: "…")` ili `LocalizedStringResource`. Obični `String` literal koji završi u `Text(string)` se ne prevodi.
* Brojeve, datume, trajanja i popise formatiraj kroz `formatted()`, ne lijepljenjem stringova, kako bi poštovali jezik i regiju.
* Tekst s brojem koji mijenja oblik ("1 serija", "3 serije", "5 serija") dobiva u katalogu varijante za množinu (`plural`) na oba jezika. Hrvatski ima oblike `one`, `few` i `other`, engleski `one` i `other`.
* Tekst u kodu unutar `#if DEBUG` (Prototipi, alat za CloudKit shemu) ne ide u katalog: piše se doslovno, `Text(verbatim:)` ili `String("…")` (npr. `Button(String("Prototipi"), systemImage: "hammer")`). Izvoz lokalizacije prevodi aplikaciju bez `DEBUG`-a, pa bi takav tekst u katalogu ispao zastarjeo i srušio provjeru.
* Simboli koji se ne prevode (`·`, `×`, `+10`) u katalogu imaju `shouldTranslate: false`.

## Provjera na CI-ju

Posao `localization` u `.github/workflows/ci.yml`:

1. `xcodebuild -exportLocalizations` prevede kod i u katalog upiše sve tekstove koje je kompajler izvukao.
2. `Tools/Localization/check_catalog.py` javi grešku ako neki tekst nema engleski prijevod, ako prijevod ima druge formatne argumente od ključa (`%lld`, `%@`) ili ako je u katalogu ostao tekst koji se više ne koristi.

Novi tekst u kodu bez prijevoda zato ruši CI. Popravak: u Xcodeu otvori `Localizable.xcstrings`, upiši engleski prijevod (a zastarjele ključeve obriši) i commitaj katalog. Lokalno isto radi `scripts/ci-local.sh`.

## Ručna provjera

* **Duljina teksta na malim ekranima:** u Xcodeu shema → Run → Options → App Language: English, pa provjeriti iPhone SE (3. gen.), najmanji Apple Watch (41 mm) i Live Activity na zaključanom zaslonu. Isto s najvećom veličinom teksta (Accessibility Large).
* **Pseudojezik:** App Language "Double-Length Pseudolanguage" otkriva mjesta gdje dulji tekst lomi raspored.
* Engleski je strojno preveden pa ručno pregledan; prijedloge boljih izraza upisati izravno u katalog.
