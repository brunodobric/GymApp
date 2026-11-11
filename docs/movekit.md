# MoveKit katalog vježbi

Katalog vježbi je MoveKit paket "Complete Exercise Library" (movekit.com): 582 vježbe, svaka s animiranim klipom, posterom i metapodacima. Do studenog 2026 izvor je bio free-exercise-db.

## Licenca i što smije u repozitorij

MoveKit je komercijalna licenca (MoveKit License Agreement v1.0), kupljena na Bruna Dobrića. MoveKit je e-mailom (studeni 2026) potvrdio:

* sadržaj smijemo ugraditi u aplikaciju i isporučiti preko App Storea,
* klipove smijemo pretvoriti u drugi format, izrezati, napraviti postere i ukloniti metapodatke,
* navođenje izvora u aplikaciji nije obavezno,
* licenca se jednom može prenijeti na tvrtku.

Uvjeti koji određuju kako radimo:

* **Sirove datoteke ne smiju biti javno dostupne ni preuzimljive.** Repozitorij je javan, pa u njega ne idu klipovi, posteri, `metadata.json` ni MoveKit tekstovi (upute, česte greške, opisi), ni naši hrvatski prijevodi tih tekstova. Nema javnih poveznica na datoteke, a aplikacija nema izvoz klipova.
* **Licenca i certifikat čuvaju se uz pakete** (`~/Documents/MoveKit/LICENSE.txt` i e-mail s potvrdom). License ID se ne piše u repozitorij.

U repozitoriju su samo naši podaci: pravila mapiranja (`Tools/CatalogBuilder/mapping.json`), ispravke po vježbi (`overrides.json`), hrvatski nazivi (`names-hr.json`) i iz njih izgrađen `Resources/Catalog/catalog.json` (id, nazivi, kategorija, vrsta vježbe, mišići, oprema, vrsta unosa, regije mape mišića).

## Gdje je što

| Mjesto | Sadržaj | U gitu |
|---|---|---|
| `~/Documents/MoveKit/` | raspakirani paket: klipovi, posteri, `metadata.json`, `LICENSE.txt` | ne |
| `~/Documents/MoveKit/GymApp/` | privatni izlaz CatalogBuildera: `texts.json`, `Media/` (HEVC klipovi i JPEG posteri), kasnije `translations-hr.json` | ne |
| `Resources/MoveKit/` | kopija privatnog izlaza koja ulazi u build (`MoveKit/...` u bundleu) | ne (`.gitignore`, samo `.gitkeep`) |
| `Resources/Catalog/catalog.json` | javni katalog bez MoveKit tekstova i medija | da |

## Postupak na Macu

Jednom: `brew install ffmpeg`.

```sh
scripts/movekit.sh      # pretvori klipove i postere, napravi texts.json i kopira sve u Resources/MoveKit/
xcodegen generate
scripts/movekit-android.sh --apk   # Android: posteri u assets/movekit/ i debug APK (treba Android SDK)
```

APK s posterima smije se dati samo poimence odabranim testerima, nikad preko javne poveznice ni GitHub Actionsa.

Prvo pokretanje pretvara 582 klipa (HEVC, 1280 px, CRF 28, bez zvuka, oko 150 KB po klipu) i traje desetak minuta. Kasnije se preskaču klipovi koji su već pretvoreni. `scripts/testflight.sh` sam pokreće `scripts/movekit.sh`, pa izdanje uvijek ima medije.

Kad se promijeni mapiranje, ispravke ili hrvatski nazivi, javni katalog se ponovno gradi i commita:

```sh
python3 Tools/CatalogBuilder/build_catalog.py --movekit ~/Documents/MoveKit
```

## Build bez paketa

CI i klon repozitorija nemaju MoveKit dodatak. Aplikacija se normalno gradi i radi: katalog ima sve vježbe, nazive, mišiće i filtere, ali detalj vježbe nema klip ni upute (piše da upute nisu dostupne), a mreža kataloga nema sličice. `CatalogStore` gleda postoji li datoteka prije nego što je prikaže.

## Id-jevi vježbi

Spremljeni treninzi, predlošci i izmjene ciklusa pamte vježbu po id-ju kataloga (MoveKit slug). Id postojeće vježbe se ne mijenja. Prijelaz sa starog kataloga (free-exercise-db) imao je migraciju id-jeva samo za razvojne buildove, a uklonjena je prije prvog izdanja. Usporedba vježbi je u projektnim datotekama (`movekit/usporedba-vjezbi.md`).

## Hrvatski prijevod uputa

Upute i česte greške su zasad samo na engleskom (aplikacija to napominje). Prijevod je MoveKit tekst, pa ide u privatni `~/Documents/MoveKit/GymApp/translations-hr.json` u obliku `{"slug": {"instructions": [...], "commonMistakes": [...]}}`. CatalogBuilder ga spaja u `texts.json`.
