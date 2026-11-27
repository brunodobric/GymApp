# Android: izdanje na Google Playu

Kako se Android aplikacija (mobitel i Wear OS sat) gradi, potpisuje i objavljuje na Google Playu, i što se upisuje u Play Console. iOS izdanje je u `docs/izdanje.md`, plan Android verzije u `docs/android.md`.

## 1. Što je u repozitoriju

* **Release build** (`android/app` i `android/wear`): R8 uklanja nekorišteni kod i resurse, ali ne preimenuje klase (`proguard-rules.pro`), jer se nazivi enuma spremaju u bazu, kopiju i poruke sata, a stack trace u dijagnostici ostaje čitljiv.
* **Broj verzije** je u `android/gradle.properties` (`apolon.versionCode`, `apolon.versionName`). Mobitel i sat dijele `applicationId`, pa imaju različit versionCode: mobitel `versionCode × 10`, sat `versionCode × 10 + 1`. Za svako novo izdanje na Playu `apolon.versionCode` raste za 1.
* **Paket klipova** (`android/movekit`): MoveKit klipovi, posteri i upute idu u install-time asset pack, jer osnovni modul smije imati najviše oko 200 MB. Play ga instalira zajedno s aplikacijom, a kod ga čita kao obične assete. Modul postoji samo kad je sadržaj pripremljen (`scripts/movekit-android.sh`). Debug APK uzima isti sadržaj kao obične assete.
* **Klipovi u H.264:** `scripts/movekit-android.sh` pretvara HEVC klipove s iOS-a u H.264 (High, yuv420p, bez zvuka), jer hardverski HEVC nije zajamčen na svim Android mobitelima.
* **CI** (`.github/workflows/android.yml`) gradi release AAB mobitela i sata s probnim paketom klipova i provjerava da paket ulazi u AAB. Taj AAB se ne sprema: nije potpisan i nema klipove.
* **Tekstovi i grafike za Play:** `PlayStore/` (provjera duljina: `Tools/PlayStore/check_metadata.py`, na CI-ju).

## 2. Upload ključ (jednom)

Google Play App Signing: Google čuva ključ kojim potpisuje aplikaciju za korisnike, a mi potpisujemo upload ključem. Izgubljeni upload ključ Google može zamijeniti, ali ključ i lozinke ipak treba čuvati na sigurnom (npr. u upravitelju lozinki) i nikad u repozitoriju (`*.jks` je u `.gitignore`).

```sh
mkdir -p ~/Keys
keytool -genkeypair -v -keystore ~/Keys/apolon-upload.jks -alias upload \
  -keyalg RSA -keysize 4096 -validity 10000
```

Zatim u `~/.gradle/gradle.properties` (apsolutna putanja, bez `~`):

```properties
apolon.keystore=/Users/<korisnik>/Keys/apolon-upload.jks
apolon.keystorePassword=...
apolon.keyAlias=upload
apolon.keyPassword=...
```

Isti ključ potpisuje i sat: Data Layer povezuje samo aplikacije istog paketa i potpisa, a Play ih potpisuje istim ključem aplikacije.

## 3. Build za upload

Na Macu, iz korijena repozitorija, nakon `scripts/movekit.sh`:

```sh
scripts/android-izdanje.sh          # android/app/.../app-release.aab i android/wear/.../wear-release.aab
scripts/android-izdanje.sh --apk    # uz to univerzalni APK za izravno testiranje (brew install bundletool)
```

AAB i APK s MoveKit sadržajem dijele se samo kroz Play Console i poimence odabranim testerima, nikad javno (`docs/movekit.md`).

## 4. Play Console: postavljanje aplikacije

**Račun:** organizacija (D-U-N-S broj i provjera tvrtke). Naziv programera na Playu je naziv tvrtke, a adresa i kontakt tvrtke su javni na stranici aplikacije.

**Nova aplikacija:** naziv Apolon, zadani jezik hrvatski (hr), aplikacija (ne igra), besplatna.

**Glavni unos u trgovini** (Grow > Store presence > Main store listing): tekstovi iz `PlayStore/metadata/<jezik>/` (`title.txt`, `short_description.txt`, `full_description.txt`), ikona `PlayStore/graphics/icon-512.png`, grafika `PlayStore/graphics/feature-graphic-<jezik>.png` (1024 × 500), snimke zaslona mobitela (barem 2, preporuka 4 do 8, uspravno 9:16) i sata (barem 1, kvadrat, npr. 384 × 384, bez okvira sata). Engleski se dodaje kao prijevod (en-US).

**Kategorija i kontakt:** aplikacija, kategorija Health & Fitness, e-mail za kontakt, web `https://brunodobric.github.io/GymApp/podrska/`.

**Wear OS:** Test and release > Advanced settings > Form factors > dodaj Wear OS. AAB sata ide u Wear OS stazu (track) uz AAB mobitela, a Google aplikaciju sata posebno pregledava prema pravilima kvalitete za Wear OS.

### App content (Policy > App content)

| Obrazac | Odgovor |
|---|---|
| Privacy policy | `https://brunodobric.github.io/GymApp/privacy/` |
| Ads | Ne, aplikacija nema oglase. |
| App access | Sve funkcije dostupne bez prijave i posebnog pristupa. |
| Content ratings (IARC) | Kategorija upitnika: All Other App Types. Nasilje, strah, seksualnost, jezik, droge, kockanje: ne. Korisnici međusobno komuniciraju ili dijele sadržaj: ne. Dijeli lokaciju: ne. Digitalne kupnje: ne. Očekivana oznaka: PEGI 3 / Everyone. |
| Target audience | 13 i više (13–15, 16–17, 18+). Aplikacija nije namijenjena djeci, pa ne ulazi u program Families. |
| News app | Ne. |
| Government app | Ne. |
| Financial features | Ne. |
| Health apps | Da: praćenje fizičke aktivnosti i treninga (Fitness / Activity tracking). Ne medicinski uređaj, nema medicinskih savjeta. |
| Data safety | Vidi ispod. |
| Health Connect | Vidi ispod. |
| Foreground service | Vidi ispod (sat). |

### Data safety

Prijedlog: **"Aplikacija ne prikuplja ni ne dijeli korisničke podatke"** (No data collected). Razlog, prema definiciji u Play pravilima ("prikupljanje" je prijenos podataka s uređaja aplikacije):

* Nema servera, računa, analitike ni SDK-ova trećih strana. Dijagnostika (`ApplicationExitInfo`) ostaje na uređaju i izvozi se samo kad korisnik to sam odabere.
* Podaci iz Health Connecta (čitanje) ostaju u lokalnoj bazi i ne idu u sigurnosnu kopiju.
* Sinkronizacija: aplikacija piše u datoteku koju korisnik sam odabere sustavskim izbornikom (Storage Access Framework). U oblak je prenosi pohrana koju je korisnik odabrao, ne aplikacija. Ovo je tumačenje: ako Google pri pregledu traži drukčije, odgovor je "Fitness info, Health info: collected, not shared, encrypted in transit, user can request deletion (brisanjem datoteke), purpose App functionality".
* Sat i mobitel razmjenjuju podatke preko Wearable Data Layera (Google Play usluge) između korisnikovih uređaja.
* Sustavska sigurnosna kopija Androida (Auto Backup) ne prijavljuje se.

Pitanja: "Does your app collect or share any of the required user data types?" Ne. Pravila privatnosti moraju odgovarati obrascu (`site/privacy/`).

### Health Connect (deklaracija dozvola)

Policy > App content > Health Connect. Za svaku dozvolu kratko obrazloženje (engleski):

| Dozvola | Obrazloženje |
|---|---|
| `WRITE_EXERCISE` | Saves workouts the user finishes in the app (time, duration, strength and cardio segments). |
| `WRITE_WEIGHT` | Saves body weight the user enters in body tracking. |
| `READ_EXERCISE` | Shows cardio workouts from other apps in the workout history and weekly overview. |
| `READ_DISTANCE` | Shows the distance of those cardio workouts. |
| `READ_ACTIVE_CALORIES_BURNED` | Shows active calories of those cardio workouts. |
| `READ_HEART_RATE` | Shows average heart rate of those cardio workouts and, in the Wear OS app, heart rate from the watch sensors during a workout. |
| `READ_WEIGHT` | Shows body weight from other apps in body tracking and relative strength statistics. |
| `READ_HEIGHT` | Shows height from other apps in body tracking. |

Aplikacija ne čita u pozadini (`READ_HEALTH_DATA_IN_BACKGROUND` se ne traži) ni povijest stariju od 30 dana (`READ_HEALTH_DATA_HISTORY` se ne traži). Ekran s objašnjenjem dozvola je `HealthPermissionsActivity`, a pravila privatnosti opisuju što se čita i upisuje.

### Foreground service (sat)

Aplikacija na satu za vrijeme treninga drži foreground service vrste `health` (`FOREGROUND_SERVICE_HEALTH`) da Health Services mjere puls i kalorije dok je zaslon ugašen. U obrascu: vrsta Health, opis "Tracks heart rate and calories with Health Services during a strength workout the user starts on the watch or phone; stops when the workout ends." i poveznica na kratki video (npr. YouTube, neizlistano) koji pokazuje: početak treninga na satu, obavijest ili ikonu treninga u tijeku, upis serije i kraj treninga. Mobitel nema foreground service (obavijest treninga je obična stalna obavijest).

### Ostale dozvole

* `SCHEDULE_EXACT_ALARM` (kraj odmora): ne traži deklaraciju; korisnik ga dopušta u postavkama, a bez njega alarm ima prozor od nekoliko sekundi. `USE_EXACT_ALARM` se ne koristi.
* `POST_PROMOTED_NOTIFICATIONS` (Live Update na Androidu 16) i `POST_NOTIFICATIONS`: bez deklaracije.
* `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` se namjerno ne koristi (ograničeno pravilima). Postavke > Obavijesti > Potrošnja baterije otvara podatke o aplikaciji.

## 5. Testiranje i produkcija

1. **Interno testiranje** (do 100 testera po e-mailu, bez pregleda): prvi upload, provjera da se aplikacija i sat instaliraju iz Playa, da klipovi stižu (paket klipova) i da se mobitel i sat vide.
2. **Zatvoreno testiranje (preporuka):** račun programera je račun organizacije (Bruno, 27. 11.), pa pravilo za nove osobne račune (barem 12 testera neprekidno 14 dana prije produkcije) ne vrijedi. Zatvoreni test s nekoliko testera ipak se preporučuje prije produkcije, posebno za sat i obavijesti na Samsungu.
3. **Zahtjev za produkciju** ne treba za račun organizacije: izdanje se šalje izravno na pregled u produkcijsku stazu.
4. **Produkcija:** postupno izdanje (npr. 20 %, pa 100 %), zemlje: sve.

Tijekom testiranja svako novo izdanje dobiva veći `apolon.versionCode`.

## 6. Prije svakog izdanja

* `apolon.versionCode` + 1, `apolon.versionName` prema izdanju, `PlayStore/metadata/<jezik>/release_notes.txt` (najviše 500 znakova).
* `scripts/android-izdanje.sh`, upload oba AAB-a u istu stazu.
* Kratka provjera univerzalnog APK-a na mobitelu (`android/test-na-uredaju.md` u projektnim datotekama).
