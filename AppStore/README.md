# App Store materijali

Sve što se upisuje u App Store Connect za Apolon, na hrvatskom (`hr`, primarni jezik) i engleskom (`en-US`). Tekst se mijenja ovdje, a u App Store Connect se kopira. CI (`Tools/AppStore/check_metadata.py`) provjerava Appleova ograničenja duljine i da oba jezika imaju sve datoteke.

## Datoteke

| Datoteka | Polje u App Store Connectu | Ograničenje |
|---|---|---|
| `metadata/<jezik>/name.txt` | Name | 30 znakova, mora biti jedinstven u App Storeu |
| `metadata/<jezik>/subtitle.txt` | Subtitle | 30 znakova |
| `metadata/<jezik>/promotional_text.txt` | Promotional Text (mijenja se bez nove verzije) | 170 znakova |
| `metadata/<jezik>/description.txt` | Description | 4000 znakova |
| `metadata/<jezik>/keywords.txt` | Keywords | 100 bajtova, odvojeno zarezima bez razmaka |
| `metadata/<jezik>/release_notes.txt` | What's New (od druge verzije) | 4000 znakova |
| `metadata/<jezik>/support_url.txt` | Support URL | ispravan https URL |
| `metadata/<jezik>/privacy_url.txt` | Privacy Policy URL | ispravan https URL |
| `review_notes.txt` | App Review Information > Notes | 4000 znakova, na engleskom |
| `screenshots/<jezik>/<uređaj>/` | snimke zaslona | 6,9" iPhone i 13" iPad, vidi niže |

Ključne riječi ne ponavljaju riječi iz naziva i podnaslova, jer ih App Store već pretražuje.

## Ostala polja

* **Bundle ID:** `com.brunodobric.gymapp` (sat: `com.brunodobric.gymapp.watchkitapp`).
* **SKU:** `apolon-ios`.
* **Primarna kategorija:** Health & Fitness. Sekundarna: Sports.
* **Cijena:** besplatno. **Dostupnost:** sve zemlje.
* **Copyright:** `2026 Bruno Dobrić`.
* **Sign-in required:** ne (nema računa).
* **Privatnost (App Privacy):** "Data Not Collected", odgovori su u `docs/PRAVNO_I_PRIVATNOST.md`.
* **Export Compliance:** već riješeno u Info.plist (`ITSAppUsesNonExemptEncryption = NO`).
* **Content Rights:** aplikacija prikazuje sadržaj trećih strana samo iz MoveKit kataloga vježbi (komercijalna licenca, s pisanom potvrdom za isporuku u aplikaciji) i crteža MuscleMap (MIT), za koje ima pravo. Odgovor na pitanje o pravima: Yes, has rights.

## Dobna oznaka (Age Rating)

Upitnik u App Store Connectu, odgovori za Apolon:

| Pitanje | Odgovor |
|---|---|
| Nasilje (crtano, realistično, grafičko) | None |
| Seksualni sadržaj, golotinja | None |
| Psovke i grub humor | None |
| Alkohol, duhan, droge | None |
| Simulirano kockanje, kockanje za pravi novac, natjecanja | None / No |
| Horor i strašne teme | None |
| Medicinske ili terapijske informacije | None (bilježenje treninga nije medicinski savjet) |
| Neograničen pristup webu | No |
| Sadržaj koji stvaraju korisnici i dijeljenje među korisnicima | No |
| Poruke i chat | No |
| Oglasi | No |
| Kontrole za roditelje, provjera dobi | No |

Očekivana oznaka: **4+**.

## Naziv

Ime "Apolon" samo po sebi moglo bi biti zauzeto u App Storeu, zato je naziv "Apolon: dnevnik treninga" i "Apolon: Workout Log". Ako ni to nije slobodno pri stvaranju aplikacije u App Store Connectu, rezerva je "Apolon Gym: dnevnik treninga" / "Apolon Gym: Workout Log". Ime ispod ikone na uređaju (`CFBundleDisplayName`) ostaje "Apolon".

## Snimke zaslona

**iPhone i iPad** se snimaju automatski, na Macu:

```sh
scripts/snimke-zaslona.sh
```

Skripta za iPhone 16 Pro Max (6,9") i iPad Pro 13" (M4), na hrvatskom i engleskom, pokrene UI test `UITests/ScreenshotTests.swift`. Test pokreće aplikaciju s `-ScreenshotMode`: baza je samo u memoriji i puni se demo podacima (`DemoDataGenerator` u GymKitu: program Upper/Lower, deset tjedana treninga s napretkom, mjere tijela), pa podaci na simulatoru ostaju netaknuti. Status bar je postavljen na 9:41 s punom baterijom. Snimke idu u `AppStore/screenshots/<jezik>/<uređaj>/`:

1. `01-pocetna`: Početna sa sljedećim treningom
2. `02-trening`: trening u tijeku s prošlim rezultatima
3. `03-povijest`: povijest treninga
4. `04-statistika`: grafovi, heatmap i rekordi
5. `05-rasporedi`: rasporedi
6. `06-vjezbe` i `07-vjezba`: katalog i detalj vježbe

U App Store Connect se učitavaju redom 02, 01, 04, 07, 03, 05 (prva snimka je ono što se vidi u pretrazi). Ako Xcode nema neki od simulatora, uređaj se zadaje varijablom: `IPHONE="iPhone 17 Pro Max" IPAD="iPad Pro 13-inch (M5)" scripts/snimke-zaslona.sh`. Za demo podatke ne treba nikakva postavka: način rada postoji samo u Debug buildu.

**Apple Watch** se snima ručno, jer sat prikazuje trening koji vodi iPhone:

1. U Xcodeu pokrenuti shemu GymApp na paru simulatora iPhone 16 Pro Max + Apple Watch Series 10 (46 mm), s argumentom `-ScreenshotMode` (Edit Scheme > Run > Arguments) i jezikom sheme (Options > App Language).
2. Na iPhoneu dodirnuti Započni, pa na satu otvoriti Apolon.
3. Snimiti zaslon sata: `xcrun simctl io booted screenshot AppStore/screenshots/<jezik>/watch/01-trening.png` (s `--device` ako je pokrenuto više simulatora) ili ⌘S u Simulatoru.
4. Ponoviti za odmor (označiti seriju) i za komplikaciju na brojčaniku.
