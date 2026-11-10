# Plan izrade Android verzije aplikacije Apolon

Studeni 2026. Plan za Android aplikaciju koja radi isto što i iOS, iPadOS i watchOS aplikacija. Izvor istine za funkcionalnost ostaje `docs/SPECIFIKACIJA.md` (v3): Android ne dobiva vlastitu specifikaciju, nego ovaj dokument kaže kako se svaka stavka specifikacije ostvaruje na Androidu i gdje ponašanje mora biti drukčije.

Plan je napisan prema stanju repozitorija na commitu `dc3b13b` (widgeti, prečaci, statistika po razdobljima). Ovo je samo plan: nema koda.

---

## 0. Odluke i stanje (9. 11. 2026.)

Ovaj odjeljak vrijedi ispred svega ispod njega.

* **Opseg: samo Android mobitel.** Wear OS sat, tableti i preklopni mobiteli se zasad ne rade (Bruno, 9. 11.). Odjeljci 7.9 i faza 9 (Wear OS) te faza 11 (tableti i preklopni) ostaju u planu samo kao zapis za kasnije. Aplikacija se zaključava na uspravni položaj kao na iPhoneu, a na tabletu i otvorenom preklopnom mobitelu radi kao telefon (bez vlastitog rasporeda). Zbog toga otpada i dio prilagodljivosti iz 7.1 (rail, drawer, više okna).
* **MoveKit licenca vrijedi i za Android**, pod istim pravilima kao za iOS (odjeljak 9).
* **Repozitorij:** isti, mapa `android/`, grana `claude/project-thread-9zyhro` za prve korake.
* **Usklađeno s iOS kodom do PR-a #134** (commit `670eff4`) i pregledom koda od 9. 11.:
  * Nema više migracija za razvojne buildove (`CatalogIdMigration`, `legacyIds`, `CardioPlanMigration`, WorkoutKit) ni polja `cardioPlanRaw` i `workoutPlanId`. Android ih ne prenosi.
  * **Jedan put za završetak i odbacivanje treninga** (`WorkoutLifecycle`): na Androidu od prvog dana jedan `WorkoutLifecycle` (raspored, podsjetnici, obavijest u tijeku, Health Connect, widgeti), s testom za svaki ulaz (zaslon, ponuda za stari trening, prečac, obavijest).
  * **Kvačica upisuje samo izmijenjena polja** i sprema jednom; izmjene polja spremaju se s odgodom od pola sekunde i odmah pri odlasku u pozadinu. Neizmijenjena težina se nikad ne pretvara iz zaokruženog teksta (funte).
  * **`DataVersion`**: statistika, Pregled i kartice preračunavaju se po brojaču koji raste nakon svakog spremanja, ne po broju treninga. Na Androidu to prirodno daje Room `InvalidationTracker` / `Flow`.
  * **Upiti s predikatom i indeksima** od prvog dana: izvođenja po ključu vježbe, treninzi po stanju i početku, mjerenja po vrsti i datumu; "prošli put" dohvaća jedan zapis.
  * **Statistika i rekordi izvan glavne niti** (korutine na `Dispatchers.Default`), a rekordi završenog treninga spremaju se u lokalnu predmemoriju umjesto računanja iz cijele povijesti (preporuka P2-3 iz pregleda).
  * **Jedan engine treninga.** Na iOS-u postoje dva (`WorkoutEngine` za bazu i `SnapshotEngine` za sat) koja ponavljaju ista pravila. Android logiku treninga piše jednom, nad domenskom snimkom treninga, a baza je samo primjenjuje. Tako je i sat kasnije jednostavan.
  * **Nova pravila iz PR-ova #131 i #133:** zadana pauza prema vrsti vježbe (složene 2:30, ostale 1:30, `RestPolicy`) i korak težine po opremi i po vježbi (`WeightSteps`, `WheelOptions`). Ulaze u port logike u fazi 1.
  * **Statistika ima osnovni i detaljni prikaz** (PR #132), a detaljni će kasnije biti plaćen. Na Androidu to znači Google Play Billing kad se uvede plaćanje; do tada je detaljni prikaz besplatna postavka kao na iOS-u.
  * **Widgeti** imaju crnu pozadinu u tamnoj temi i vidljiv trokut na gumbu ▶ (#128, #129); isto vrijedi za Glance widgete.
  * **Zadani akcent je Apolon plava** uz paletu od šest boja (#127).
* **Pohrana bez Rooma (odluka u izradi, 9. 11.).** Logika na iOS-u mijenja graf modela (trening → vježbe → serije) i zatim sprema. Da bi port bio vjeran i testovi isti, Android ima isti graf u memoriji (`core/model`, `GymStore`): logika mijenja objekte, a `save()` usporedbom sa zadnjim spremljenim stanjem zapisuje samo promijenjene i obrisane zapise. Trajno spremanje je jedna SQLite tablica `records(type, id, json)` preko Androidova `SQLiteDatabase` (bez Rooma i KSP-a, dakle bez nove ovisnosti). Upiti idu nad memorijom (podaci jednog korisnika su mali), a `revision` u `GymStore` je `DataVersion`. Zapisi koje Android ne razumije (iz novije verzije ili uvoza) i zapisi bez roditelja ostaju u bazi netaknuti. Nazivi polja u JSON-u su isti kao u SwiftData modelima, a UUID-ovi se pišu velikim slovima, pa izvoz i uvoz ostaju isti na obje platforme. Ako se ikad pokaže sporim, `RecordPersistence` se može zamijeniti tablicama po modelu bez promjene logike.
* **Sigurnosna kopija (`domain/backup`) u istom zapisu kao na iOS-u.** JSON ima ista polja, ključeve abecedno, datume kao sekunde od 1. 1. 2001. (zadano u Swiftovu `JSONEncoder`u) i UUID-ove velikim slovima, pa se kopija s iPhonea uvozi na Android i obrnuto. CSV ima iste stupce i datume (ISO 8601 s milisekundama, UTC). Slika vlastite vježbe je u kopiji kao Base64 bajtovi, a u aplikaciji zasebna datoteka (`imageFile`). Dok ne postoji Health Connect, uvoz preskače treninge iz aplikacije Workouts i težinu ili visinu iz Zdravlja (na iOS-u idu u lokalnu bazu zdravstvenih podataka, ne u korisničku). `DataResetScope` (iCloud) se ne prenosi; brisanje u Driveu dolazi sa sinkronizacijom.
* **Postavke > Podaci na Androidu:** izvoz ide kroz sustavski izbornik datoteka (`CreateDocument`), uvoz kroz `OpenDocument`, s istim imenima datoteka i granicom od 50 MB. Pregled uvoza iz druge aplikacije zasad pokazuje samo brojeve (novi treninzi, serije, nove vlastite vježbe), bez popisa vježbi i kamo idu kao na iOS-u. Slike vlastitih vježbi su u `files/exercise-images/`.
* **Uređivači treninga i rasporeda na Androidu zasad spremaju odmah**, bez tijeka "Spremi / Izađi bez spremanja" (`EditSnapshot`) s iOS-a. Uređivač treninga ima naziv, vježbe s redoslijedom na strelice, serije s ciljanom težinom i ponavljanjima te odmor po vježbi (superserije i rasponi ponavljanja dolaze kasnije). "Novi trening iz ovog" u detalju treninga otvara novi trening u tom uređivaču. Uređivač rasporeda ima naziv, aktivnost, broj ciklusa, niz s redoslijedom na strelice, "Pokreni ispočetka" i brisanje (podsjetnici i preskočeni treninzi dolaze kasnije).
* **Stanje aplikacije (10. 11., PR-ovi #143 do #157).** Svih pet kartica radi:
  * **Početna:** kartica "Započni trening" s planiranim treninzima, "Odaberi drugi trening" (#135) i praznim treningom.
  * **Trening:** serije s unosom prema vrsti vježbe, kvačica s odmorom (±15 s, preskoči), zagrijavanje, brisanje serije i izbacivanje vježbe s poništavanjem, završetak sa sažetkom (trajanje, volumen, tvrde serije, usporedba, istaknuti rekordi, bilješka).
  * **Povijest:** popis i detalj treninga s usporedbom i brisanjem.
  * **Rasporedi:** rasporedi i treninzi, novi raspored ili trening, uređivači i gotovi programi (nazivi na jeziku sučelja, kao `ProgramLabels`).
  * **Statistika:** pregled tjedna, mjeseca i godine, osobni rekordi (svi rekordi s pretragom i filtrom), mjere tijela s grafom i napredak vježbe.
  * **Postavke:** Profil (cilj, dani, iskustvo, oprema), Trening (jedinice, zadana pauza, rekordi), Health Connect, Podaci i O aplikaciji.
  * **Health Connect (upis):** završeni treninzi s mobitela i ručno unesena težina idu u Health Connect kad korisnik to uključi u Postavkama (`HealthConnectExporter`, logika u `domain/health`). Trening je jedan `ExerciseSessionRecord`; s kardijem je `OTHER_WORKOUT` s dijelovima snage i kardija, iste podjele vremena kao na iOS-u. Prvi upis nosi treninge iz zadnjih 30 dana i težine iz zadnje godine, a izmjena ili brisanje u aplikaciji mijenja i zapis u Health Connectu. Što je upisano pamti datoteka `files/health/exported.txt`, koja ne ide u sigurnosnu kopiju. Onboarding na kraju nudi povezivanje (zaslon kao Apple Zdravlje na iOS-u), ako je Health Connect na uređaju.
  * **Health Connect (čitanje):** kardio treninzi drugih aplikacija (zadnjih 30 dana, s udaljenošću, aktivnim kalorijama i prosječnim pulsom iz iste aplikacije), težina i visina (zadnja godina) idu u lokalnu bazu `files/health/local.json` (`HealthLocalFile`, kao `HealthLocal` na iOS-u), koja ne ide u sigurnosnu kopiju. Čita se pri svakom povratku u aplikaciju (Health Connect ne dopušta čitanje u pozadini bez posebne dozvole). Uvezeni treninzi su u povijesti i kalendaru (`HistoryQueries`), a mjerenja u praćenju tijela (`BodyTracking`). Brisanje u aplikaciji briše samo lokalni zapis, koji se ne vraća sljedećim čitanjem. Nisu prenesene kalorije i puls vlastitih treninga (sat) ni uvezeni treninzi na Početnoj i u statistici.
  * **Live Update (Android 16+):** obavijest treninga u tijeku traži promociju (`requestPromotedOngoing`, dozvola `POST_PROMOTED_NOTIFICATIONS`) i postaje čip u statusnoj traci s trajanjem ili odbrojavanjem odmora. Sustav promovira samo obavijest bez vlastitog izgleda, pa na Androidu 16 nema gumba − i +: vrijednosti sljedeće serije su u tekstu, a ✓ ostaje. Na starijim Androidima ostaje proširena obavijest s − i +.
  * **Kartice vrsta:** početna kataloga ima četiri kartice vrsta (dva stupca, jedan uz vrlo veliki tekst) s mozaikom 2 × 2 postera (`featured` u `core/catalog`), brojem vježbi i retcima Sve vježbe i Moje vježbe. Posteri se čitaju iz `assets/movekit/` (putanja iz kataloga, npr. `movekit/Media/<id>.jpg`, mapa je u `.gitignore`); bez MoveKit dodatka kartica pokazuje simbol vrste. Pretraga s početne odmah otvara popis.
  * **Još nije preneseno:** klip na detalju vježbe, skripta `scripts/movekit-android.sh` koja puni `assets/movekit/`, sinkronizacija. Aplikacija je dosad provjerena samo buildom na CI-ju, ne na uređaju.
* **Okruženje za izradu:** u ovom oblaku `dl.google.com` je blokiran, pa se Android SDK ne može instalirati. Čisti Kotlin moduli (logika i testovi) grade se i testiraju ovdje, a aplikacija se gradi na GitHub Actionsu (Ubuntu runner ima Android SDK). Za lokalni build aplikacije ovdje treba dopustiti `dl.google.com` u mrežnim postavkama okruženja.

**Nova procjena za mobitel:** oko 36 tjedana sa sinkronizacijom (faze 0 do 8, 10, 12, 13, 14), oko 33 bez nje.

---

## 1. Sažetak

* **Nativna Android aplikacija u Kotlinu i Jetpack Composeu**, uz Wear OS aplikaciju za sat. Isti pristup kao na iOS-u: sistemske komponente (Material 3), bez SDK-ova trećih strana, bez vlastitog servera i bez korisničkog računa.
* **Logika iz GymKita prepisuje se u Kotlin**, modul po modul, a postojeći testovi (oko 8 000 redaka) prenose se kao specifikacija ponašanja. Dijeljenje Swift koda nije isplativo, jer je GymKit vezan uz SwiftData (odjeljak 4).
* **Dijele se podaci, ne kod:** `catalog.json`, `body.json`, hrvatski nazivi, mapiranje kataloga, programi, tekstovi sučelja (pretvorba iz String Cataloga) i formati izvoza (CSV i JSON), tako da se korisnik može preseliti s iPhonea na Android i natrag preko datoteke.
* **CloudKit nema zamjenu bez računa.** Preporuka: prvo izdanje ima lokalnu bazu, Android Backup (sustavska sigurnosna kopija) i izvoz/uvoz, a sinkronizacija između Android uređaja preko skrivene mape aplikacije u korisnikovom Google Driveu dolazi kao zasebna faza. To je glavna odluka za Bruna (odjeljak 13).
* **Live Activity postaje obavijest u tijeku** (foreground service) s odbrojavanjem i gumbima −, + i ✓, a na Androidu 16 i novijima i kao Live Update u statusnoj traci.
* **Procjena:** oko 43 tjedna rada jedne osobe (raspon 36 do 46) za punu jednakost (telefon, tablet, Wear OS, widgeti, Health Connect, sinkronizacija), otprilike koliko je trebao i iOS. Prvo izdanje bez sata i sinkronizacije moguće je za oko 35 tjedana (odjeljak 11).
* **MoveKit licenca vrijedi i za Android** pod istim pravilima kao na iOS-u (Brunova odluka), pa klipovi i upute idu u Android verziju bez novog upita (odjeljak 9).

---

## 2. Što znači "potpuno ista" aplikacija

Ista aplikacija znači iste funkcije, isti model podataka, ista pravila (rekordi, tvrde serije, rasporedi, smart defaults, oporavak treninga), isti katalog i isti tekstovi. Ne znači isti izgled piksel po piksel: iOS verzija je građena po Apple HIG-u (`docs/DIZAJN.md`), a Android verzija treba slijediti Material 3, inače će Android korisnicima izgledati strano (tab bar na dnu postaje navigacijska traka, sheetovi postaju bottom sheetovi, "Poništi" traka postaje Snackbar, swipe akcije i povratak sustavskom gestom).

Nekoliko stvari na Androidu ne postoji ili radi drukčije. To nisu propusti plana nego granice platforme:

| iOS | Android | Posljedica |
|---|---|---|
| Activity prstenovi (zatvaranje preko HealthKita) | Nema sustavskog ekvivalenta. Health Connect prima trening, a prikazuju ga Google Fit, Samsung Health ili Fitbit. | Spec rečenica o prstenovima ne vrijedi; trening se samo upisuje u Health Connect. |
| Dynamic Island | Live Update čip u statusnoj traci (Android 16+), inače obavijest u tijeku | Odbrojavanje se vidi u traci, ali bez izgleda Dynamic Islanda. |
| Widgeti na zaključanom zaslonu (pravokutnik, krug, redak iznad sata) | Na većini telefona nema widgeta na zaključanom zaslonu | Ti oblici otpadaju; ostaju widgeti na početnom zaslonu i obavijest u tijeku. |
| Kontrola u Kontrolnom centru i tipka Action | Pločica u Brzim postavkama (Quick Settings tile) i prečac na ikoni | Isto djelovanje, drugo mjesto. Tipke Action nema (Samsung bočna tipka može otvoriti aplikaciju, ali to korisnik sam podešava). |
| Prečaci, Siri, Spotlight (App Intents) | App Shortcuts (dugi pritisak na ikonu), pretraga sustava, Gemini/Assistant samo ako Google to i dalje podržava | Automatizacije poput "kad stignem u teretanu" nemaju sustavsku podlogu kao Shortcuts. Glasovne naredbe treba provjeriti u fazi 0. |
| `HKHealthStore.startWatchApp` (iPhone pokreće sat) | Poruka preko Wearable Data Layera koju sat prima u servisu | Moguće, ali pokretanje sesije na satu iz pozadine treba prototip (odjeljak 7). |
| iCloud i CloudKit bez prijave | Nema ekvivalenta bez Google prijave | Odjeljak 6. |
| SF Pro Rounded | Appleova licenca ne dopušta SF fontove izvan Appleovih platformi | Treba drugi zaobljeni font ili sistemski (odjeljak 8). |
| StandBy, Stage Manager, ⌘N i izbornik aplikacije | Više prozora i tipkovnički prečaci (Ctrl+N) postoje; StandBy nema | Prečaci tipkovnice ostaju, StandBy otpada. |
| Apple Watch | Wear OS (Galaxy Watch, Pixel Watch). Wear OS sat se uparuje samo s Android telefonom. | Korisnik s iPhoneom ne može koristiti Wear OS sat i obrnuto. |
| Sinkronizacija iPhone ↔ Android | Nije planirana | Prelazak ide preko izvoza i uvoza JSON-a (isti format). |

---

## 3. Tehnički stog

| Područje | iOS danas | Android |
|---|---|---|
| Jezik | Swift 5/6 | Kotlin 2.x (K2 kompajler) |
| Sučelje | SwiftUI | Jetpack Compose, Material 3 (Expressive gdje ima smisla) |
| Navigacija | `TabView`, `NavigationStack`, `NavigationSplitView` | Navigation 3 (ili Navigation Compose), `NavigationSuiteScaffold` (traka dolje, rail ili drawer prema veličini prozora), `ListDetailPaneScaffold` i `SupportingPaneScaffold` za tablete |
| Stanje | `@Observable`, `@Query` | ViewModel + `StateFlow`, Room upiti kao `Flow` |
| Baza | SwiftData (dvije konfiguracije: korisnička i `HealthLocal`) | Room (SQLite), dvije baze: korisnička i lokalna za podatke iz Health Connecta |
| Postavke uređaja | `UserDefaults` | DataStore (Preferences) |
| Grafovi | Swift Charts | Vlastiti grafovi u Compose `Canvas` ili Vico (Apache 2.0). Preporuka: Vico za linijske i stupčaste grafove, vlastiti Canvas za mapu tijela i godišnju mrežu aktivnosti. |
| Video | AVFoundation | Media3 ExoPlayer (Apache 2.0, Google) |
| Zdravlje | HealthKit | Health Connect (telefon), Health Services (sat) |
| Sat | watchOS, WatchConnectivity, `HKWorkoutSession` | Wear OS 4+, Wearable Data Layer API, Health Services `ExerciseClient`, Ongoing Activity, Tiles, komplikacije |
| Live Activity | ActivityKit | Foreground service + obavijest u tijeku (Live Update na Androidu 16+) |
| Widgeti | WidgetKit, App Group snimka | Jetpack Glance, snimka u datoteci aplikacije |
| Prečaci | App Intents | App Shortcuts (`shortcuts.xml` i dinamički prečaci), Quick Settings tile, deep linkovi `apolon://` |
| Obavijesti | UserNotifications | `NotificationManager`, kanali, `AlarmManager` za podsjetnike, WorkManager za periodične poslove |
| Sinkronizacija | CloudKit | Faza 12: Google Drive `appDataFolder` (odjeljak 6) |
| Rušenja i performanse | MetricKit, Xcode Organizer | Android vitals u Play Consoleu, `ApplicationExitInfo` u lokalni dnevnik, Macrobenchmark i Baseline Profiles |
| DI | Ručno (`AppServices`) | Ručno (AppContainer) ili Hilt. Preporuka: ručno, kao na iOS-u, dok ne postane nezgrapno. |
| Testovi | Swift Testing | JUnit 5 / kotlin.test za čistu logiku, Robolectric gdje treba Android, Compose UI testovi, Room testovi migracija |
| Lint | SwiftLint | Android Lint i ktlint (ili detekt) |
| Build | XcodeGen, Xcode | Gradle (Kotlin DSL), version catalog |
| CI | GitHub Actions (macOS) | GitHub Actions (Ubuntu): lint, testovi, build telefona i sata, provjera prijevoda |

**Minimalne verzije:** telefon i tablet `minSdk 31` (Android 12: dinamičke boje, nova pravila za alarme i foreground servise, dovoljan udio uređaja krajem 2026), `targetSdk` najnoviji koji Play traži (36). Sat `minSdk 33` (Wear OS 4). Kao i na iOS-u, pred izlazak provjeriti udio uređaja i po potrebi podići minimum.

**Pravilo "bez SDK-ova trećih strana" na Androidu:** Jetpack biblioteke (Compose, Room, Glance, Media3, Health Connect, Wear) su Googleove biblioteke otvorenog koda pod Apache 2.0 i igraju ulogu Appleovih okvira. Smiju se koristiti, ali svaka ide u evidenciju ovisnosti u `docs/PRAVNO_I_PRIVATNOST.md`. Firebase, Crashlytics, Google Analytics i oglasni SDK-ovi se ne koriste. Vico i eventualna biblioteka za povlačenje redaka (npr. Reorderable, Apache 2.0) su ovisnosti trećih strana: dopuštene su samo uz upis licence, a ako Bruno želi strogo pravilo, i to se može napisati samostalno (oko tjedan dana više).

---

## 4. Što se dijeli s iOS verzijom

### Zašto se Swift kod ne dijeli

Postoje tri puta: prepisati logiku u Kotlin, prebaciti zajedničku logiku u Kotlin Multiplatform pa je koristiti i na iOS-u, ili koristiti Swift SDK za Android i GymKit pozivati iz Kotlina.

GymKit ima oko 13 000 redaka logike i 8 000 redaka testova, ali gotovo svi moduli (`Models`, `Training`, `Planning`, `Stats`, `Backup`, `Connectivity`, `HealthSync`, `WidgetSync`) uvoze SwiftData i rade izravno nad `@Model` klasama. Bez SwiftData ovisnosti su samo `Units`, `Catalog`, `Diagnostics` i `WidgetData` (oko 1 300 redaka). Swift na Androidu zato bi prvo tražio odvajanje cijelog GymKita od SwiftData, a zatim JNI most i Swift runtime u aplikaciji, uz alat koji je još mlad. Kotlin Multiplatform bi tražio prepisivanje logike i za iOS, što ne donosi ništa postojećoj aplikaciji.

**Preporuka: Kotlin port GymKita**, sa Swift testovima kao specifikacijom ponašanja. Logika je dobro odvojena od sučelja i pokrivena testovima, pa je prijevod mehanički posao kojem Claude Code dobro odgovara.

### Kako dvije implementacije ostaju iste

* **Zajednički testni slučajevi u JSON-u.** Za pravila koja se lako razlikuju (1RM i rekordi, tvrde serije, status vježbe s Theil–Senovim nagibom, napredovanje rasporeda i ciklusa, smart defaults, pregled zadnja 4 tjedna, preporuka programa, uvoz CSV-a drugih aplikacija) Swift strana generira ulaze i očekivane izlaze u `Fixtures/` (novi direktorij u repozitoriju), a oba testna skupa ih provjeravaju. Promjena pravila na jednoj strani tada ruši testove druge strane dok se ne uskladi.
* **Formati izvoza su ugovor.** CSV i JSON koje izvozi iOS mora uvesti Android i obrnuto, bez gubitka. To je ujedno put za prelazak korisnika s jedne platforme na drugu.
* **Pravilo u CLAUDE.md:** svaka promjena logike u GymKitu dobiva i promjenu u Kotlin modulu (ili zapis u popis neusklađenih stavki), kao što svaki tekst danas dobiva engleski prijevod.

### Što se dijeli izravno kao datoteke

| Datoteka | Upotreba na Androidu |
|---|---|
| `Resources/Catalog/catalog.json` | Isti katalog u `assets/` i isti `catalogId` (MoveKit slug) |
| `Resources/BodyMap/body.json` (MuscleMap, MIT) | SVG putanje se crtaju u Compose `Canvas` (`PathParser`) |
| `Tools/CatalogBuilder` (mapping, overrides, names-hr) | Bez promjena. Dobiva novi izlaz: medije za Android (odjeljak 9). |
| `Resources/Localization/Localizable.xcstrings` | Skripta pretvara String Catalog u `values/strings.xml` i `values-en/strings.xml`, s množinama (hrvatski ima oblike one, few, other) |
| `AppStore/` tekstovi | Osnova za opis na Google Playu (druge duljine: kratki opis 80 znakova, puni 4 000) |
| `site/` | Pravila privatnosti dobivaju odjeljak za Android (Health Connect, Google Drive) |

---

## 5. Arhitektura Android projekta

**Repozitorij:** preporuka je isti repozitorij, nova mapa `android/`, jer dijeli katalog, prijevode, dokumentaciju, CatalogBuilder i testne slučajeve. CI dobiva zaseban workflow koji se pokreće samo kad se promijeni `android/`, `Resources/`, `Fixtures/` ili `Tools/`.

```
android/
  settings.gradle.kts, gradle/libs.versions.toml
  core/units          (čisti Kotlin: Weight, InputParsing, WheelOptions)
  core/catalog        (čisti Kotlin: ExerciseCatalog, Taxonomy, ExerciseSearch)
  core/model          (čisti Kotlin: modeli, GymStore, deduplikacija, kartice, onboarding, koraci težine)
  core/training       (WorkoutEngine, SessionEditor, PersonalRecords, PRRanking, PlateCalculator, RestAndFlow)
  core/planning       (TemplateEngine, ScheduleEngine, TemplateStarter, EditSnapshot, Reminders, Programs)
  core/stats          (Statistics, EffectiveSets, Trends, PeriodOverview, WeeklyReview, BodyTracking...)
  domain/backup       (CSV, JSON, ForeignWorkoutImport, DataReset)
  domain/health       (HealthImporter, pravila zapisa treninga)
  shared/wearprotocol (SessionSnapshot, WorkoutCommand, WorkoutEvent, WatchContext: dijele telefon i sat)
  shared/widgetdata   (WidgetSnapshot, WidgetLink, WidgetWeek)
  shared/design       (tema, tipografija, boje akcenta: dijele telefon, widgeti i sat)
  app                 (telefon i tablet: Compose ekrani, servisi, Glance widgeti, tile)
  wear                (Wear OS aplikacija, Tiles, komplikacije)
  benchmark           (Macrobenchmark, Baseline Profile)
```

* **Logika u čistim Kotlin modulima** bez Android ovisnosti, kao GymKit bez SwiftUI-ja. Testovi se izvode na JVM-u za nekoliko sekundi.
* **Domenski tipovi su odvojeni od Room entiteta.** Na iOS-u logika radi izravno nad SwiftData modelima. Na Androidu je bolje da logika radi nad običnim `data class` tipovima, a `core/data` pretvara entitete. Tako su testovi jednostavniji, a ista logika radi i na satu, koji nema bazu telefona.
* **Model podataka je isti kao u odjeljku 8 specifikacije:** iste tablice (Session, SessionExercise, SetLog, WorkoutTemplate, TemplateExercise, TemplateSet, Schedule, ScheduleItem, CycleOverride, CustomExercise, BodyMeasurement, DashboardCard, UserSettings), isti nazivi polja, UUID kao `id`, `orderIndex` za redoslijed, težina u kg. Room dopušta jedinstvena ograničenja, ali zbog sinkronizacije (odjeljak 6) vrijede ista pravila kao za CloudKit: uz to svaki zapis dobiva `updatedAt` i `deletedAt` (tombstone), jer ih sinkronizacija bez CloudKita mora sama voditi.
* **Podaci iz Health Connecta u zasebnoj lokalnoj bazi**, kao `HealthLocal`: Google Play pravila za zdravstvene podatke su stroga, a isti raspored kao na iOS-u znači da sinkronizacija i sigurnosna kopija nikad ne nose zdravstvene vrijednosti.
* **Aktivni trening se sprema nakon svake promjene** (Room transakcija), a stanje odmora kao trenutak završetka. Oporavak prekinutog treninga radi isto kao na iOS-u. Na Androidu je to još važnije, jer proizvođači (Samsung, Xiaomi, Huawei) agresivno gase aplikacije u pozadini.

---

## 6. Sinkronizacija bez CloudKita

Specifikacija kaže: bez vlastitog servera, bez korisničkog računa, bez analitike, privatni podaci samo kod korisnika. Na Androidu ne postoji sustavski servis koji to radi kao CloudKit.

| Mogućnost | Za | Protiv |
|---|---|---|
| **Android Backup** (Auto Backup u Google Drive korisnika, uključen sustavski) | Bez prijave i bez koda osim pravila što se kopira. Vraća podatke na novom telefonu. | Samo vraćanje pri postavljanju uređaja, nije sinkronizacija između uređaja. Ograničenje 25 MB. |
| **Google Drive `appDataFolder`** (skrivena mapa aplikacije u korisnikovom Driveu) | Podaci ostaju kod korisnika, nema našeg servera, korisnik može obrisati podatke aplikacije iz Drivea. Radi između telefona i tableta. | Treba Google prijava (Credential Manager i OAuth za scope `drive.appdata`) i postavljanje projekta u Google Cloud konzoli. Logiku sinkronizacije pišemo sami: dnevnik promjena, last write wins po zapisu, tombstoneovi, rješavanje duplikata. Provjeriti vrstu scopea i treba li Googleova verifikacija. |
| **Vlastiti server** (Firebase, Supabase) | Najlakša sinkronizacija | Krši osnovno načelo aplikacije: račun, server, podaci kod nas, "Data Not Collected" više ne vrijedi, GDPR obveze rastu. Ne preporučuje se. |
| **Sinkronizacija s iCloudom** (CloudKit Web Services) | Isti podaci na iPhoneu i Androidu | Traži Apple ID prijavu na Androidu, krhko i neuobičajeno. Ne preporučuje se. |

**Preporuka:**

1. **Prvo izdanje:** lokalna baza, Android Backup za korisničku bazu (bez `health-local` baze) i izvoz/uvoz. Ekran Postavke > iCloud postaje Postavke > Sigurnosna kopija, sa stanjem sustavske kopije i uputom.
2. **Faza 12:** sinkronizacija preko Drive `appDataFolder`, isključena dok je korisnik ne uključi. Dizajn: svaki uređaj piše svoje promjene kao datoteke dnevnika (zapis = cijeli red s `updatedAt`), povremeno se slaže sažeta snimka, last write wins po zapisu kao u specifikaciji, `deletedAt` za brisanja, deduplikacija po UUID-u kao `Deduplication.removeAllDuplicates`. "Obriši sve podatke" briše i datoteke u `appDataFolder`.
3. Korisnik koji prelazi s iPhonea na Android to radi izvozom JSON-a na iPhoneu i uvozom na Androidu (odjeljak 4). Na to se nadovezuje uputa na stranici podrške.

---

## 7. Mapiranje funkcija i platformskih API-ja

### 7.1 Navigacija i prilagodljivost (telefon, tablet, preklopni)

* Pet tabova (Početna, Odrađeni treninzi, Rasporedi, Katalog, Statistika) u `NavigationSuiteScaffold`: na telefonu navigacijska traka dolje, na tabletu i otvorenom preklopnom navigacijski rail ili drawer. Postavke ostaju gumb gore desno na Početnoj.
* Svaki tab ima vlastiti stog navigacije koji se čuva pri prelasku na drugi tab, a ponovni dodir na otvoreni tab vraća na korijen (isto pravilo kao na iOS-u, Material ga također preporučuje). Rasporedi usred uređivanja pitaju Spremi ili Izađi bez spremanja.
* iPad layouti (`NavigationSplitView`) postaju `ListDetailPaneScaffold` prema klasama veličine prozora (compact, medium, expanded). Isti raspored za preklopne telefone, uz pažnju na pregib (posture).
* Više prozora: Android ga podržava sam (split screen, slobodni prozori na tabletima i desktop načinu). Detaljni prozori s iOS-a (`DetailWindows`) postaju nova aktivnost u zasebnom prozoru gdje ima smisla.
* Tipkovnica: Ctrl+N za novi trening i ostali prečaci iz `AppCommands`, uz popis prečaca (Keyboard Shortcuts Helper).
* Povratak: sustavska gesta i predictive back. Ekran aktivnog treninga, uređivači i sheetovi moraju je ispravno obraditi (npr. uređivanje rasporeda pita prije izlaska).

### 7.2 Katalog vježbi

* Katalog iz `catalog.json` učitava se u memoriju pri pokretanju, kao na iOS-u. Pretraga je ista logika (`ExerciseSearch`).
* Početna kataloga: četiri kartice vrsta u mreži 2 × 2 (`LazyVerticalGrid`), retci Sve vježbe i Moje vježbe, pretraga (`SearchBar` iz Material 3) i filteri u bottom sheetu.
* Klip vježbe: ExoPlayer u petlji, bez zvuka i bez traženja audio fokusa (ne prekida glazbu), pauzira se izvan ekrana i u pozadini. "Smanji kretanje" na Androidu je postavka "Ukloni animacije" (skala trajanja animacija 0): tada se prikazuje poster i gumb za pokretanje.
* Vlastite vježbe sa slikom: Photo Picker (bez dozvole za galeriju), slika u privatnoj mapi aplikacije.
* Povijest vježbe ("Tvoja povijest") ista logika (`ExerciseHistory`).

### 7.3 Aktivni trening na telefonu

* Ekran treninga: `LazyColumn` s karticama vježbi, jedna otvorena, retci serija s težinom, ponavljanjima, volumenom i kvačicom.
* **Kotačić za težinu i ponavljanja:** Compose nema sistemski kotačić. Izrada vlastitog s `LazyColumn` i snap ponašanjem (koraci 2,5 kg ili 5 lbs, ponavljanja 1 do 50, polazna vrijednost kao na iOS-u, dodir na broj otvara numeričku tipkovnicu). Ovo je najvažnija kontrola aplikacije, pa dobiva vlastiti prototip i UI test.
* Brisanje serije povlačenjem ulijevo (`SwipeToDismissBox`) i Snackbar "Serija obrisana · Poništi". Isto za izbacivanje vježbe i izbornik "Uklonjene vježbe".
* Promjena redoslijeda povlačenjem: vlastita implementacija ili Reorderable biblioteka (odjeljak 3).
* Kalkulator ploča iz polja težine (dugi pritisak) i iz izbornika vježbe, bottom sheet preko cijelog ekrana.
* Sažimanje treninga u karticu na Početnoj povlačenjem prema dolje ili gumbom Smanji: ekran treninga je cijeli ekran (ili bottom sheet koji se može sažeti), a kartica na Početnoj prikazuje isto što i obavijest u tijeku.
* Zvuk i haptika na kraju odmora dok je aplikacija otvorena: `SoundPool` (uz poštovanje načina zvona i postavke zvuka) i `VibrationEffect`.

### 7.4 Rest timer, obavijest u tijeku (umjesto Live Activityja) i obavijesti

Ovo je dio s najviše razlika i najviše rizika, jer Android aplikaciju u pozadini gasi, a točni alarmi su ograničeni.

* **Dok trening traje, aplikacija drži obavijest u tijeku** (`WorkoutNotification`, kanal niske važnosti, bez zvuka). Zasad je to obična stalna obavijest, ne foreground service: trening se ne odvija u pozadini (podaci su u bazi), pa proces ne mora ostati živ, a kraj odmora javlja alarm. `WorkoutNotificationUpdater` nakon svakog spremanja osvježava obavijest samo kad se promijeni ono što prikazuje. `RestNotificationScheduler` primjenjuje `RestNotificationPolicy` i zakazuje alarm za kraj odmora (točan kad je dopušten, inače prozor od 5 s; `SCHEDULE_EXACT_ALARM` se na Androidu 14+ ne daje automatski), a `RestAlarmReceiver` vraća obavijest treninga s odbrojavanja na trajanje i prikazuje obavijest o kraju odmora samo kad ekran treninga nije u prvom planu. Ekran treninga sam javlja kraj odmora vibracijom i zvukom (postavka "Zvuk kraja odmora") i traži `POST_NOTIFICATIONS` kad počne prvi odmor. Ako se na uređajima pokaže da proizvođači gase proces ili kasne alarmi, prelazi se na foreground service (odluka ispod).
* **Vrsta foreground servisa:** `health` (praćenje vježbanja) traži jednu od dozvola poput prepoznavanja aktivnosti ili senzora tijela, a `specialUse` traži obrazloženje u Play Consoleu. Odluka se donosi u prototipu faze 0, uz provjeru Play pravila.
* **Sadržaj obavijesti, isto kao Live Activity:** naziv treninga i trajanje od početka (`setUsesChronometer`), za odmora odbrojavanje do kraja odmora (`setChronometerCountDown`, pa nisu potrebna stalna ažuriranja, kao `Text(timerInterval:)`; obavijest ima jedan sat, pa za odmora ne broji trajanje), trenutna vježba i serija, sljedeća vježba i broj gotovih serija. Gumb **Potvrdi seriju** (`WorkoutActionReceiver`, isto što i `CompleteSetIntent`) kad sljedeća serija ima sve vrijednosti; proširena obavijest ima gumbe **−** i **+** uz vrijednosti sljedeće serije (`LiveSetEditor` u `core/training`, isti koraci kao na iOS-u: korak težine vježbe, 1 ponavljanje, 5 s, 50 m). Dodir otvara ekran treninga. Obavijest je tiha (kanal niske važnosti), osim kraja odmora.
* **Android 16+:** obavijest se predlaže kao Live Update (`ProgressStyle`, promovirana obavijest u tijeku), pa se odbrojavanje vidi kao čip u statusnoj traci i na zaključanom zaslonu. Live Update ne dopušta vlastiti izgled obavijesti, pa se koristi standardni izgled s gumbima.
* **Boja i tema obavijesti** ("Prati aplikaciju" u Postavkama): obavijest foreground servisa smije biti obojena (`setColorized`), pa postavka boje ostaje. Tema (svijetla ili tamna) na Androidu prati sustav i ne može se birati za obavijest: ta postavka na Androidu otpada.
* **Kraj odmora:** kad je aplikacija u prvom planu, zvuk i haptika iz aplikacije. Kad nije, obavijest na zasebnom kanalu "Kraj odmora" visoke važnosti (korisnik ga može pustiti kroz Ne ometaj, kao time-sensitive na iOS-u). Promjena +10/−10 ili prekid premješta ili briše obavijest. Kad trening vodi sat, telefon ne javlja kraj odmora.
* **Dodir na obavijest** otvara ekran aktivnog treninga (`apolon://trening`).
* **Podsjetnici rasporeda** (fiksni dani i fleksibilno): `AlarmManager` s nepreciznim alarmom u prozoru (podsjetnik ne mora biti u sekundu), ponovno zakazivanje nakon pokretanja uređaja (`BOOT_COMPLETED`) i promjene vremena. Tijekom treninga podsjetnici se ne šalju, a današnji se otkazuju. Logika je ista (`Reminders`). Napravljeno: `ReminderScheduler` nakon svakog spremanja računa termine (`ReminderBuilder`) i zakazuje najviše 50 alarma s prozorom od 10 minuta, `ReminderAlarmReceiver` prikazuje obavijest (ne tijekom treninga), a `ReminderRescheduleReceiver` ponovno zakazuje nakon pokretanja telefona, nadogradnje aplikacije i promjene vremena ili zone. Uređivač rasporeda ima karticu podsjetnika (vrijeme, način, dani ili razmak), a Postavke prekidač "Podsjetnici rasporeda". Dodir podsjetnika otvara sljedeći trening rasporeda (`UpcomingWorkoutScreen`): početak treninga, izbacivanje ili zamjena vježbe samo u ovom ciklusu, poništavanje izmjena i preskakanje treninga. Dok trening traje, dodir se zanemaruje.
* **Dozvola za obavijesti** (`POST_NOTIFICATIONS`, Android 13+) traži se kad korisnik uključi podsjetnike ili pokrene prvi trening, s objašnjenjem.
* **Uputa za Focus** postaje uputa za način Ne ometaj ili Modes (Android 15+) i Bixby Routines na Samsungu.
* **Optimizacija baterije:** uputa (i provjera u Postavkama) za proizvođače koji gase servise, s poveznicom na postavke baterije aplikacije. Na iOS-u ovoga nema; na Androidu je to stvaran izvor grešaka "timer nije zazvonio".

### 7.5 Predlošci, rasporedi, programi i onboarding

Logika je u potpunosti iz GymKita (`ScheduleEngine`, `TemplateEngine`, `Programs`, `ProgramRecommender`, `CycleOverride`, `TemplateFromSession`). Sučelje: popisi s uređivanjem (crtice za povlačenje, brisanje, dodavanje), isti tijek Spremi / Izađi bez spremanja, onboarding na jednoj stranici s istim pitanjima i ponudom programa. Povezivanje s Apple Health u onboardingu postaje povezivanje s Health Connectom.

### 7.6 Povijest, statistika i praćenje tijela

* Popis treninga s filterom i kalendarom (Material 3 `DatePicker` nije dovoljan za točkice na danima, pa vlastita mjesečna mreža).
* Detalj treninga, uređivanje, "Novi trening iz ovog", brisanje: isto.
* Mapa mišića: crtanje putanja iz `body.json` u `Canvas`, bojenje prema tvrdim serijama, dodir na mišić (hit test po putanji).
* Pregled (tjedan, mjesec, godina), kartice statistike, grafovi napretka, statusi vježbi, pregled zadnja 4 tjedna, praćenje tijela s grafovima: logika iz `Stats`, grafovi iz odjeljka 3.

### 7.7 Početna, postavke, izvoz i dijagnostika

* Kartice na Početnoj (Započni, Ovaj tjedan, Zadnji trening, Težina, Ploče) s uređivanjem redoslijeda.
* Postavke iste kategorije. Tema Svijetlo / Tamno / Automatski i boja akcenta; uz to opcija "Boje sustava" (Material You dinamične boje), jer je to na Androidu očekivano.
* Izvoz CSV i JSON i uvoz: Storage Access Framework (spremanje i otvaranje datoteke bez dozvola za pohranu) i dijeljenje (`ShareSheet`). Isti formati kao iOS.
* Dijagnostika: lokalni dnevnik (`Diagnostics`), razlozi završetka procesa iz `ApplicationExitInfo` (rušenja, ANR, gašenje zbog memorije), izvoz na zahtjev korisnika. Ništa se ne šalje samo.
* Demo podaci i način za snimke zaslona: isti `DemoData`, uz Compose test koji radi snimke za Google Play.

### 7.8 Health Connect (umjesto HealthKita)

| HealthKit | Health Connect |
|---|---|
| Zapis `HKWorkout` | `ExerciseSessionRecord` (vrsta snaga / dizanje utega), s id-jem treninga u `clientRecordId` |
| Trening s kardio vježbama kao više `HKWorkout` zapisa | Jedan `ExerciseSessionRecord` sa segmentima (`ExerciseSegment`) za kardio i snagu. Jednostavnije nego na iOS-u; logika podjele vremena ostaje ista. |
| Čitanje kardio treninga iz aplikacije Workout | Čitanje `ExerciseSessionRecord` drugih aplikacija (Samsung Health, Google Fit, Strava...) uz `DistanceRecord`, `ActiveCaloriesBurnedRecord`, `TotalCaloriesBurnedRecord`, `HeartRateRecord` |
| Tjelesna masa i visina | `WeightRecord`, `HeightRecord`; upis težine iz aplikacije kao `WeightRecord` |
| Kalorije samo iz Appleovog proračuna | Kalorije samo iz Health Connecta (sat ili druga aplikacija). Bez sata polje se ne prikazuje, isto pravilo. |
| Pozadinsko čitanje | Dozvola `READ_HEALTH_DATA_IN_BACKGROUND` i periodični posao (WorkManager); bez nje uvoz pri otvaranju aplikacije |
| Podaci starije od 30 dana | Dozvola `READ_HEALTH_DATA_HISTORY` za prvi uvoz starijih treninga |

* Dozvole samo za tipove koji se koriste, traže se tek kad korisnik odabere povezivanje. Aplikacija mora imati ekran s objašnjenjem dozvola (Health Connect ga traži) i poveznicu na pravila privatnosti.
* **Google Play:** prijava zdravstvenih dozvola (Health apps declaration) u Play Consoleu, s obrazloženjem svake dozvole. Health Connect podaci se ne smiju koristiti za oglase ni slati trećima, a ostaju u lokalnoj bazi i ne idu u sigurnosnu kopiju ni sinkronizaciju.
* Na uređajima s Androidom 13 i starijim Health Connect je zasebna aplikacija iz Play Storea; aplikacija nudi instalaciju.
* **Stanje:** upis treninga i težine je gotov (dozvole `WRITE_EXERCISE` i `WRITE_WEIGHT`, ekran s objašnjenjem `HealthPermissionsActivity` za Android 13 i 14+). Čitanje kardio treninga, težine i visine u lokalnu bazu je gotovo; pozadinsko čitanje (`READ_HEALTH_DATA_IN_BACKGROUND`) i starije od 30 dana (`READ_HEALTH_DATA_HISTORY`) nisu.

### 7.9 Wear OS aplikacija (umjesto Apple Watcha)

Isti ekrani i ista pravila kao na satu (specifikacija, "Watch ekrani"), u Compose for Wear OS (`ScalingLazyColumn`, `TimeText`, Material 3 za Wear).

| watchOS | Wear OS |
|---|---|
| `HKWorkoutSession` (puls, kalorije, rad sa spuštenim zapešćem) | Health Services `ExerciseClient` u foreground servisu, vrsta vježbe snaga; Ongoing Activity da se trening vidi na brojčaniku i vraća u aplikaciju |
| Digital Crown za težinu i ponavljanja | Rotacijski unos (okretna kruna ili okretni okvir na Galaxy Watchu) preko `onRotaryScrollEvent` |
| Haptika na kraju odmora | `Vibrator` na satu |
| `WCSession.sendMessage` | `MessageClient` (trenutni događaji dok su oba uređaja dostupna) |
| `transferUserInfo` (zajamčena isporuka redom) | `DataClient` s jedinstvenom putanjom po događaju (`/event/<uuid>`), brisanje nakon potvrde. Redoslijed nije zajamčen, pa se slaže po vremenskoj oznaci i UUID-u (već tako radi `WorkoutEvent`). |
| `updateApplicationContext` | `DataClient` s fiksnom putanjom (`/context`), sat čita zadnje stanje |
| `startWatchApp` (iPhone pokreće sat) | Poruka satu, koji u `WearableListenerService` pokreće sesiju. Pokretanje foreground servisa iz pozadine na satu treba prototip; rezerva je obavijest na satu "Trening počeo na telefonu" s dodirom za pokretanje. |
| Komplikacije (sljedeći trening, odmor, tjedni cilj, brzi početak, težina) | `ComplicationDataSourceService` za iste komplikacije (kratki tekst, raspon za tjedni cilj, mala slika) i Tile "Sljedeći trening" s gumbom Započni |
| Smart Stack relevantnost | Ongoing Activity i Tile; nema ekvivalenta relevantnosti |
| Zapis treninga u Zdravlje sa sata | Sat zapisuje trening u Health Connect na telefonu preko podataka koje šalje telefonu (Health Services na satu ne piše izravno u Health Connect telefona). Telefon tada zna da trening ima puls i kalorije sa sata (`healthRecordedByWatch`). |

* Protokol (`SessionSnapshot`, `WorkoutCommand`, `WorkoutEvent`, `WatchContext`, `LiveSetEditor`) prenosi se 1:1 u `shared/wearprotocol`, kao JSON. Jedan uređaj vodi trening, isto pravilo kao na iOS-u.
* Sat može voditi trening bez telefona i poslati ga kad se veza uspostavi.
* Sat se objavljuje kao Wear OS aplikacija u istom Play listingu (zaseban modul, isti `applicationId`).

### 7.10 Widgeti, pločica i prečaci

* **Widgeti na početnom zaslonu (Glance):** Sljedeći trening (mali i srednji, s gumbom ▶), Ovaj tjedan, Težina s krivuljom, Zadnji trening, Zadnji rekord. Android widgeti mijenjaju veličinu, pa se izgled bira prema dostupnoj veličini (`SizeMode.Responsive`).
* **Snimka umjesto baze**, isti obrazac kao na iOS-u: aplikacija nakon spremanja slaže `WidgetSnapshot` (port `WidgetSnapshotBuilder`) i sprema JSON u svoju mapu, a widget ga čita. Osvježavanje samo kad se snimka promijeni, plus posao u ponoć za novi dan i novi tjedan (WorkManager ili alarm).
* **Pločica "Započni trening"** u Brzim postavkama (`TileService`) i statički prečaci na ikoni aplikacije: Započni sljedeći trening, Prazan trening, Upiši težinu. Dinamički prečaci za spremljene treninge: dva zadnja pokretana (`WorkoutShortcuts.recentTemplates`, `AppShortcuts`), s poveznicom `apolon://zapocni/<UUID>`; prazan trening je `apolon://prazan-trening`. Te dvije poveznice postoje samo na Androidu.
* **Prečaci koji rade u pozadini** (Završi trening, Upiši tjelesnu težinu): na Androidu nema sustava kao Prečaci. Završi trening je gumb u obavijesti u tijeku, a Upiši težinu otvara mali dijalog aplikacije. Logika ostaje u `WorkoutShortcuts` i `BodyTracking.addShortcutWeight`.
* **Deep linkovi `apolon://`** (`WidgetLink`) kao intent filter, za widgete, obavijest i prečace.
* **Napravljeno:** modul `domain/widgets` je port `WidgetData` i `WidgetSync` s istim testovima (snimka, tjedan, poveznice, spremanje i slaganje iz baze). U aplikaciji je pet Glance widgeta (`appwidgets/ApolonWidgets.kt`) s jednim izgledom svaki (`SizeMode.Single`), bijelom pozadinom i crnom u tamnoj temi. `WidgetRefresher` sekundu nakon spremanja baze slaže snimku u `files/widgets` i osvježava widgete samo kad se promijeni, a nepreciznim alarmom i u ponoć. Dodir na widget šalje poveznicu `apolon://…` u `MainActivity`: Početna, trening u tijeku, pokretanje sljedećeg treninga (▶), Statistika, praćenje tijela, zadnji trening ili trening s rekordom. Krivulja težine je slika (Glance nema crtanje). Pločica "Započni trening" u Brzim postavkama (`StartWorkoutTileService`) i statički prečaci na ikoni (Započni sljedeći trening, Upiši težinu) koriste iste poveznice. Još nije: izgled widgeta prema veličini (`SizeMode.Responsive`), prečac Prazan trening i dinamički prečaci za spremljene treninge.

### 7.11 Lokalizacija i pristupačnost

* Hrvatski i engleski od prvog dana. Skripta pretvara `Localizable.xcstrings` u Android resurse (formatiranje `%@` u `%s`, množine, rodovi gdje ih ima). CI provjerava da svaki tekst ima oba jezika. Android tekstovi koji ne postoje na iOS-u (dozvole, optimizacija baterije, Health Connect) dodaju se u isti String Catalog s oznakom, pa ostaje jedan izvor prijevoda.
* Jezik po aplikaciji (Android 13+ "Jezik aplikacije"), `localeConfig`.
* Dynamic Type postaje veličina fonta sustava (`sp`, nelinearno skaliranje na Androidu 14+). Svi ekrani moraju raditi do 200 %.
* VoiceOver postaje TalkBack: `contentDescription`, `semantics` za retke serija, kotačić i timer. Provjera s Accessibility Scannerom.

---

## 8. Dizajn

* Novi dokument `docs/DIZAJN_ANDROID.md`: Material 3 pravila za aplikaciju, istim redom kao `DIZAJN.md` (navigacija, toolbar, tipografija, ekran aktivnog treninga, prilagodljivost, pristupačnost, sat).
* **Tipografija:** SF Pro Rounded se ne smije koristiti na Androidu. Uloge teksta iz `AppFont` (screenTitle, cardTitle, itemTitle, metric...) ostaju, ali se mapiraju na Material type scale. Prijedlog: sistemski font za tekst i zaobljeni font pod licencom OFL (npr. Nunito ili Google Sans Flex, ako mu licenca to dopušta) za naslove i brojeve, s tabličnim brojkama. Font se isporučuje u aplikaciji, ne preuzima se, i ide u evidenciju licenci.
* **Ikona:** adaptivna ikona (prednji i stražnji sloj) i monokromatska verzija za tematske ikone, iz postojećeg dizajna ikone Apolon.
* **Boje:** isti akcent i tamni način kao standard; Material You dinamične boje kao dodatna opcija.
* **Ikone u sučelju:** SF Symbols nisu dopušteni izvan Appleovih platformi; koriste se Material Symbols (Apache 2.0), uz vlastite ikone gdje nema para (npr. bučica s oznakom trčanja).
* Prijedlozi redizajna iz projektnih datoteka (aktivni trening, Početna, katalog) vrijede i za Android, uz prilagodbu komponentama Materiala.

---

## 9. MoveKit na Androidu

* **Licenca:** vrijede ista pravila kao za iOS (`docs/movekit.md`): sadržaj se ugrađuje u aplikaciju, smije se pretvoriti u drugi format, a sirove datoteke ne smiju biti javno dostupne ni preuzimljive. Novi upit MoveKitu ne šalje se.
* **Format klipova:** HEVC nije zajamčen na svim Android uređajima. CatalogBuilder dobiva drugi izlaz: H.264 MP4 (najšira podrška) ili AV1 uz H.264 rezervu, 720 do 1080 px, bez zvuka, i posteri u WebP-u. Procjena veličine: 150 do 220 MB za sve vježbe.
* **Isporuka:** Play Feature Delivery / Play Asset Delivery: install-time asset pack za klipove, jer osnovni modul smije imati najviše oko 200 MB. Aplikacija bez paketa (CI, klon) radi kao na iOS-u, bez klipova i uputa.
* **Javni repozitorij:** isto pravilo kao danas. Skripta `scripts/movekit-android.sh` kopira privatni izlaz u `android/app/src/main/assets/movekit/` (ili u asset pack), a mapa je u `.gitignore`.
* Kao i iz IPA-e, sadržaj se iz instalirane aplikacije može izvući; to je isto stanje kao na iOS-u.
* **Testiranje prije objave:** testne verzije s klipovima dijele se samo poimence odabranim testerima (APK poslan izravno i interno testiranje na Google Playu), nikad preko javne poveznice.

### Testne verzije prije objave

* **Izravni APK** (prvi tjedni, nekoliko ljudi): jedan APK s klipovima unutra (bundletool, `--mode=universal`), potpisan uvijek istim ključem za izdanja da se nova verzija instalira preko stare. Sat se puni preko `adb`-a.
* **Interno testiranje na Google Playu** (do 100 testera po e-mailu, bez pregleda, ažuriranja sama): glavni kanal čim postoji račun programera. Pravilo 12 testera kroz 14 dana vrijedi tek za zatvoreno testiranje prije produkcije.

---

## 10. Privatnost, pravila i Google Play

* **Pravila privatnosti** (`site/privacy/`) dobivaju odjeljak za Android: podaci na uređaju, Android Backup, (kasnije) Google Drive sinkronizacija, Health Connect i kako se podaci brišu.
* **Data safety obrazac** na Google Playu. Dok aplikacija nema sinkronizaciju: "Ne prikuplja podatke". Kad se uvede sinkronizacija preko Drivea, treba provjeriti tumačenje Play pravila (podaci idu u korisnikov Drive, ali ih šalje aplikacija), i po potrebi prijaviti "fitness i osobni podaci, šifrirani u prijenosu, korisnik ih može obrisati".
* **Health Connect prijava** u Play Consoleu i provjera Googlea prije objave.
* **Foreground service prijava** u Play Consoleu (vrsta servisa i video koji pokazuje upotrebu).
* **Novi osobni račun programera na Google Playu** mora prije produkcije proći zatvoreno testiranje (trenutno barem 12 testera kroz 14 dana). To treba ugraditi u raspored (faza 14). Račun tvrtke nema to pravilo, što je povezano s mogućim prijenosom licence MoveKita na tvrtku.
* **Dobna oznaka:** IARC upitnik u Play Consoleu.
* Dozvole koje aplikacija traži: obavijesti, Health Connect tipovi, eventualno prepoznavanje aktivnosti (ako treba za vrstu foreground servisa), točni alarmi (opcionalno), `RECEIVE_BOOT_COMPLETED`, `FOREGROUND_SERVICE_*`, `INTERNET` tek uz sinkronizaciju. Bez lokacije, kontakata i pohrane.

---

## 11. Faze i procjena

Procjena je u tjednima rada jedne osobe uz Claude Code, istom metodom kao `docs/PLAN_IZRADE.md`. Port je brži od izvorne izrade jer su specifikacija, pravila i dizajn već odlučeni, ali Android ima više posla oko pozadinskog rada, više uređaja za testiranje i Play pravila.

| Faza | Sadržaj | Tjedni | Gotovo kad |
|---|---|---|---|
| **0. Postavljanje i prototipi** | Gradle projekt u `android/`, moduli, CI, pretvorba prijevoda. Prototipi: (a) foreground service s obaviješću, odbrojavanjem i gumbima −/+/✓ na Androidu 12, 14 i 16, na Pixelu i Samsungu; (b) kotačić za težinu; (c) Health Connect zapis sa segmentima; (d) Wear OS: Data Layer, Health Services i pokretanje sesije s telefona; (e) reprodukcija klipova (H.264 i AV1); (f) Drive `appDataFolder` prijava. | 2,5 | Svaki prototip ima zapis u `docs/prototipi-android.md` s nalazom i odlukom. |
| **1. Logika (port GymKita)** | `units`, `catalog`, `model`, `training`, `planning`, `stats`, `backup`, `health` u čistom Kotlinu; port testova; zajednički JSON testni slučajevi sa Swift strane. | 4 | Svi preneseni testovi i zajednički slučajevi prolaze; uvoz iOS JSON izvoza daje iste brojke statistike. |
| **2. Pohrana** | Room baza (korisnička i lokalna za zdravlje), DAO, repozitoriji, deduplikacija, indeksi, predmemorija rekorda, testovi migracija sheme. | 2 | Trening se sprema nakon svake promjene i preživljava gašenje procesa. |
| **3. Katalog vježbi** | Početna kataloga, popisi, pretraga, filteri, detalj s klipom, vlastite vježbe, povijest vježbe; CatalogBuilder izlaz za Android i asset pack. | 2,5 | Svih 582 vježbi s klipovima, a CI build radi i bez njih. |
| **4. Aktivni trening** | Ekran treninga, kotačić, serije svih vrsta unosa, supersetovi, RPE/RIR, odmor, kalkulator ploča, poništavanje, redoslijed, sažetak s rekordima, oporavak prekinutog treninga, foreground service i obavijest u tijeku, kraj odmora, sažimanje u karticu. | 5,5 | Cijeli trening se odradi s ugašenim ekranom samo preko obavijesti; kill procesa usred odmora ne gubi stanje. |
| **5. Predlošci, rasporedi, onboarding** | Uređivači, rasporedi i ciklusi, privremene izmjene, gotovi programi i preporuka, podsjetnici (AlarmManager, boot), onboarding. | 3 | Podsjetnici stižu nakon ponovnog pokretanja uređaja i ne stižu tijekom treninga. |
| **6. Povijest, statistika, tijelo** | Povijest s kalendarom i filterom, detalj, uređivanje, mapa mišića, Pregled po razdobljima, kartice statistike, grafovi, praćenje tijela. | 3,5 | Isti demo podaci daju iste brojke kao iOS (usporedba snimki zaslona). |
| **7. Početna, postavke, podaci** | Kartice Početne, sve postavke, izvoz i uvoz (vlastiti i strani CSV), Obriši sve podatke, dijagnostika, Android Backup pravila. | 2 | Izvoz s iPhonea uvezen na Android i natrag bez gubitka. |
| **8. Health Connect** | Dozvole i objašnjenje, zapis treninga, uvoz kardio treninga, težina i visina, pozadinski uvoz. | 2 | Trening se vidi u Samsung Healthu ili Fitu; aplikacija radi bez dozvole. |
| ~~**9. Wear OS**~~ (zasad ne) | Aplikacija na satu, protokol, vođenje treninga sa sata i bez telefona, praćenje treninga s telefona, Ongoing Activity, Tile, komplikacije. | 5 | Trening pokrenut na telefonu vodi se i sa sata; trening na satu bez telefona stiže na telefon kad se veza vrati. |
| **10. Widgeti, pločica, prečaci** | Glance widgeti, snimka, osvježavanje, Quick Settings tile, App Shortcuts, deep linkovi. | 2 | Widgeti se osvježe nakon treninga i u ponoć novog tjedna. |
| ~~**11. Tableti i preklopni**~~ (zasad ne) | Rasporedi s više okna za statistiku, planiranje i katalog, više prozora, tipkovnički prečaci. | 2 | Svi ključni ekrani imaju compact i expanded raspored; provjereno na tabletu i preklopnom emulatoru. |
| **12. Sinkronizacija (Drive)** | Prijava, dnevnik promjena, LWW, tombstoneovi, deduplikacija, stanje u Postavkama, brisanje iz Drivea. | 3 | Tri uređaja (dva telefona i tablet) nakon izmjena bez mreže imaju iste podatke. |
| **13. Lokalizacija, pristupačnost, privatnost** | Provjera prijevoda, TalkBack, veličina fonta, kontrast, pravila privatnosti, Data safety, Health Connect i FGS prijave, Baseline Profile i mjerenje pokretanja. | 1,5 | Ručna provjera pristupačnosti prođe na oba jezika. |
| **14. Beta i izdanje** | Zatvoreno testiranje (12 testera, 14 dana), ispravke, Play listing i snimke zaslona, postupno izdanje. | 3 | Aplikacija na Google Playu. |
| **Ukupno** | | **oko 43** (raspon 36 do 46); samo mobitel oko 36 | |

**Mogući redoslijed izdanja:** ako je bitno da Android stigne ranije, prvo izdanje može biti telefon i tablet bez sata i bez Drive sinkronizacije (faze 0 do 8, 10, 11, 13 i 14: oko 35 tjedana, raspon 30 do 38). Wear OS i sinkronizacija dolaze u 1.1. Time se odstupa od pravila "sat od prvog izdanja" iz specifikacije, pa je to Brunova odluka.

**Ovisnosti među fazama:** 1 prije svega osim 0; 2 prije 3 do 12; 4 prije 9 (sat koristi isti protokol i logiku treninga); 7 prije 12 (format zapisa); 13 i 14 na kraju. Faze 3, 5 i 6 mogu se raditi bilo kojim redom nakon 2.

---

## 12. Rizici

| Rizik | Vjerojatnost | Posljedica | Što radimo |
|---|---|---|---|
| Proizvođači gase foreground service ili kasne obavijesti (Samsung, Xiaomi) | Visoka | Kraj odmora ne zazvoni, korisnik gubi povjerenje | Prototip na više uređaja u fazi 0, oporavak iz baze, uputa za bateriju, rezervni alarm |
| Play odbije vrstu foreground servisa ili Health Connect dozvole | Srednja | Kašnjenje izdanja | Prijave pripremiti u fazi 13, ranije pitati kroz interni test |
| Pokretanje sesije na satu iz pozadine ne radi pouzdano | Srednja | Sat ne prati trening s telefona automatski | Rezervni tok s obaviješću na satu |
| Dvije implementacije logike se razilaze | Visoka s vremenom | Različite brojke na iOS-u i Androidu | Zajednički JSON testni slučajevi, pravilo u CLAUDE.md |
| Drive sinkronizacija je složenija od procjene | Srednja | Faza 12 traje dulje | Izdvojena faza, može ići u 1.1 |
| Fragmentacija (veličine ekrana, verzije, fontovi proizvođača) | Visoka | Greške u izgledu | Testna matrica: Pixel (najnoviji Android), Samsung srednje klase, mali ekran, tablet, preklopni, emulatori u CI-ju |
| Rad na dvije platforme usporava iOS | Visoka | Sporiji napredak iOS-a | Android počinje kad je iOS u beti ili nakon izdanja; nove funkcije prvo na iOS-u, Android prati u ciklusima |

Za testiranje treba barem jedan stvaran Android telefon (idealno Samsung, najčešći u Hrvatskoj) i Wear OS sat (Galaxy Watch ili Pixel Watch). Emulatori su dovoljni za tablete i preklopne.

---

## 13. Odluke za Bruna

1. **Sinkronizacija:** prvo izdanje s Android Backupom i izvozom, a Drive sinkronizacija kasnije (preporuka), ili Drive sinkronizacija od prvog izdanja (oko 3 tjedna više prije izdanja i Google prijava u aplikaciji)?
2. **Opseg prvog izdanja:** sve odjednom, s Wear OS-om (oko 43 tjedna), ili telefon i tablet prvo, a sat i sinkronizacija u 1.1 (oko 35 tjedana do prvog izdanja)?
3. **Kada početi:** paralelno s iOS betom ili nakon izdanja iOS-a? Preporuka: nakon iOS izdanja ili barem nakon zaključavanja iOS sheme, jer svaka promjena modela tada vrijedi za obje platforme.
4. **Repozitorij:** isti (`android/`, preporuka) ili zaseban?
5. **Ovisnosti:** dopustiti Vico i biblioteku za povlačenje redaka (uz upis licence) ili sve pisati sami?
6. **Font:** koji zaobljeni font zamjenjuje SF Pro Rounded.
7. **Račun na Google Playu:** osobni (zatvoreno testiranje 12 testera kroz 14 dana) ili tvrtka.

## 14. Prvi koraci

1. Otvoriti račun Google Play programera i Google Cloud projekt (za Drive, ako se odabere).
2. Nabaviti testni Android telefon i Wear OS sat.
3. Na iOS strani dodati generiranje zajedničkih JSON testnih slučajeva iz GymKit testova (`Fixtures/`), jer to koristi i iOS-u kao zaštita od regresija.
4. Fazu 0 započeti prototipom obavijesti u tijeku i kotačića, jer o njima najviše ovisi osjećaj aplikacije.
