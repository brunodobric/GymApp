# App Store materijali

Sve što se upisuje u App Store Connect za Apollo, na hrvatskom (`hr`, primarni jezik) i engleskom (`en-US`). Tekst se mijenja ovdje, a u App Store Connect se kopira. CI (`Tools/AppStore/check_metadata.py`) provjerava Appleova ograničenja duljine i da oba jezika imaju sve datoteke.

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
| `screenshots/` | snimke zaslona (faza 14, dio 3) | |

Ključne riječi ne ponavljaju riječi iz naziva i podnaslova, jer ih App Store već pretražuje.

## Ostala polja

* **Bundle ID:** `com.brunodobric.gymapp` (sat: `com.brunodobric.gymapp.watchkitapp`).
* **SKU:** `apollo-ios`.
* **Primarna kategorija:** Health & Fitness. Sekundarna: Sports.
* **Cijena:** besplatno. **Dostupnost:** sve zemlje.
* **Copyright:** `2026 Bruno Dobrić`.
* **Sign-in required:** ne (nema računa).
* **Privatnost (App Privacy):** "Data Not Collected", odgovori su u `docs/PRAVNO_I_PRIVATNOST.md`.
* **Export Compliance:** već riješeno u Info.plist (`ITSAppUsesNonExemptEncryption = NO`).
* **Content Rights:** aplikacija ne prikazuje sadržaj trećih strana osim kataloga free-exercise-db (Unlicense) i crteža MuscleMap (MIT), za koje ima pravo.

## Dobna oznaka (Age Rating)

Upitnik u App Store Connectu, odgovori za Apollo:

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

Ime "Apollo" samo po sebi vjerojatno je zauzeto u App Storeu, zato je naziv "Apollo: dnevnik treninga" i "Apollo: Workout Log". Ako ni to nije slobodno pri stvaranju aplikacije u App Store Connectu, rezerva je "Apollo Gym: dnevnik treninga" / "Apollo Gym: Workout Log". Ime ispod ikone na uređaju (`CFBundleDisplayName`) ostaje "Apollo".
