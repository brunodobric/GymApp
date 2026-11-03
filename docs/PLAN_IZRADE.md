# Plan izrade GymApp aplikacije

Plan se temelji na [specifikaciji v3](SPECIFIKACIJA.md). Opseg MVP-a je pun, kako je zadan u specifikaciji: iPhone, iPad i Apple Watch od prvog izdanja.

## Pretpostavke

* Razvija **jedan developer** s iskustvom u Swiftu i SwiftUI. Uz više ljudi faze 8 do 12 mogu se raditi paralelno.
* Minimalne verzije su **iOS / iPadOS 18 i watchOS 11**. Razvoj se radi u aktualnom Xcodeu.
* Procjene su u **radnim tjednima** punog radnog vremena, a uključuju pisanje testova. Ne uključuju čekanje na App Store review ni prijevod kataloga, koji ide kao zaseban posao.
* **Ukupna procjena je oko 40 tjedana**, dakle 9 do 10 mjeseci do prvog izdanja. S rezervom od 15 % za nepredviđeno to je oko 46 tjedana.

## Načela rada

1. **Ograničenja SwiftData + CloudKit vrijede od prvog dana** (odjeljak 5 specifikacije), iako se sinkronizacija uključuje tek u fazi 12. Ako se model kasnije prilagođava CloudKitu, to znači migraciju i rizik gubitka podataka.
2. **Logika je odvojena od sučelja.** Smart defaults, PR-ovi, volumen, rasporedi i pretvorba jedinica pišu se kao čisti Swift u zasebnom paketu i pokrivaju unit testovima. Isti kod koriste iPhone i Watch.
3. **Svaki ekran je od početka adaptivan.** Svaka faza isporučuje ekran koji ispravno radi na iPadu, makar u jednostavnom obliku. Faza 11 dodaje namjenske iPad layoute, ali ne popravlja pokvarene.
4. **Rizične stvari rade se rano kao prototip** (faza 0): WorkoutKit zakazivanje, SwiftData + CloudKit i WatchConnectivity. Ako nešto ne radi kako specifikacija pretpostavlja, specifikacija se mijenja prije nego što se na tome gradi.
5. **Aplikacija je stalno upotrebljiva.** Od kraja faze 3 aplikacija se svakodnevno koristi za vlastite treninge preko TestFlighta.

## Struktura projekta

```
GymApp/
├── GymApp.xcodeproj
├── App/                    # iOS + iPadOS target (SwiftUI app)
├── WatchApp/               # watchOS target
├── Widgets/                # Widget extension: Live Activity (iOS) i complications (watchOS)
├── Packages/
│   └── GymKit/             # lokalni Swift Package, dijele ga svi targeti
│       ├── Models/         # SwiftData modeli i shema (VersionedSchema)
│       ├── Persistence/    # ModelContainer: korisnička baza + baza kataloga
│       ├── Catalog/        # čitanje kataloga, pretraga, filteri
│       ├── Training/       # logika treninga: smart defaults, volumen, PR, 1RM, rest timer
│       ├── Planning/       # rasporedi, ciklusi, privremene izmjene, podsjetnici
│       ├── Health/         # HealthKit i WorkoutKit
│       ├── Connectivity/   # WatchConnectivity protokol
│       ├── Units/          # kg/lbs, formatiranje
│       └── DesignSystem/   # boje, tipografija, zajedničke komponente
├── Tools/
│   └── CatalogBuilder/     # skripta: free-exercise-db + mapiranje + prijevodi → baza kataloga
├── Resources/
│   ├── Catalog/            # mapping.json, prijevodi, odabrani set vježbi
│   └── Localizable.xcstrings
├── docs/
│   ├── SPECIFIKACIJA.md
│   └── PLAN_IZRADE.md
└── .github/workflows/      # CI: build i testovi na macOS runneru
```

## Pregled faza

| # | Faza | Procjena | Ovisi o |
|---|---|---|---|
| 0 | Postavljanje projekta i prototipi | 2 tj. | — |
| 1 | Model podataka i pohrana | 3 tj. | 0 |
| 2 | Katalog vježbi | 3 tj. | 1 |
| 3 | Aktivni trening na iPhoneu | 5 tj. | 1, 2 |
| 4 | Predlošci i rasporedi | 3 tj. | 3 |
| 5 | Povijest, statistika i praćenje tijela | 3 tj. | 3 |
| 6 | Dashboard, postavke, onboarding, export | 2 tj. | 3, 4 |
| 7 | HealthKit | 2 tj. | 3 |
| 8 | Apple Watch aplikacija | 5 tj. | 3, 7 |
| 9 | Live Activity i notifikacije odmora | 1,5 tj. | 3, 8 |
| 10 | WorkoutKit za kardio | 1,5 tj. | 4, 7 |
| 11 | iPad layouti | 2,5 tj. | 3 do 6 |
| 12 | CloudKit sinkronizacija | 2 tj. | 1 do 11 |
| 13 | Lokalizacija, pristupačnost, privatnost | 1,5 tj. | sve |
| 14 | Beta, poliranje i izdanje | 3 tj. | sve |
| | **Ukupno** | **≈ 40 tj.** | |

Usporedni posao (ne programiranje): **prijevod i pregled kataloga** na hrvatski. Počinje u fazi 2 i mora biti gotov prije faze 13.

---

## Faza 0: Postavljanje projekta i prototipi (2 tj.)

**Cilj:** projekt se gradi na CI-ju, a najrizičnije pretpostavke iz specifikacije su provjerene.

* Xcode projekt s tri targeta (iOS/iPadOS, watchOS, Widget extension) i lokalnim paketom `GymKit`.
* App Group i iCloud kontejner, potpisivanje, Bundle ID-ovi.
* GitHub Actions: build i testovi na svaki push (macOS runner). SwiftLint/SwiftFormat.
* Grane: `main` je uvijek ispravan, rad ide na feature granama s pull requestovima.
* **Prototip 1, SwiftData + CloudKit:** dva `ModelConfiguration` (sinkronizirana i lokalna samo za čitanje), model s `orderIndex`, provjera ponašanja na dva uređaja.
* **Prototip 2, WorkoutKit:** `WorkoutScheduler` zakazuje jednostavan plan trčanja na sat. Provjeriti dozvole, ograničenje broja zakazanih planova i ponašanje bez uparenog sata.
* **Prototip 3, WatchConnectivity:** razmjena događaja (`sendMessage`, `transferUserInfo`) s iPhoneom u prvom planu, u pozadini i kad je zaključan.

**Gotovo kad:** CI je zelen, a nalazi prototipa zapisani su u `docs/prototipi.md`. Ako neki prototip ne potvrdi specifikaciju, specifikacija se ažurira prije faze 1.

## Faza 1: Model podataka i pohrana (3 tj.)

**Cilj:** cijeli model iz odjeljka 8 specifikacije postoji, testiran je i spreman za CloudKit.

* SwiftData modeli: `CustomExercise`, `Schedule`, `ScheduleItem`, `WorkoutTemplate`, `TemplateExercise`, `TemplateSet`, `CycleOverride`, `Session`, `SessionExercise`, `SetLog`, `BodyMeasurement`, `DashboardCard`, `UserSettings`, uz `ExerciseRef` kao ugrađenu vrijednost.
* `VersionedSchema` v1 i `SchemaMigrationPlan` od početka.
* Pravila CloudKita: sve opcionalno ili sa zadanom vrijednošću, bez `unique`, relacije opcionalne, `orderIndex` za redoslijed.
* `ModelContainer` s dvije konfiguracije: korisnička baza i baza kataloga.
* Modul `Units`: spremanje u kg, pretvorba i formatiranje za kg i lbs.
* Pomoćne funkcije za dohvat: zadnja sesija za vježbu, sesije u rasponu datuma, aktivni trening.
* Uklanjanje duplikata po UUID-u (priprema za sync).

**Gotovo kad:** unit testovi pokrivaju kreiranje, redoslijed, brisanje (brisanje predloška ne briše sesije) i pretvorbu jedinica.

## Faza 2: Katalog vježbi (3 tj.)

**Cilj:** korisnik pregledava, pretražuje i filtrira vježbe te dodaje vlastite.

* `Tools/CatalogBuilder`: preuzima free-exercise-db (fiksirana verzija), primjenjuje `mapping.json` (kategorije, mišići, oprema, vrsta unosa, regije heatmapa), uzima odabrani set i prijevode te stvara bazu kataloga i optimizirane slike.
* Ručno: tablica mapiranja i odabir 150 do 200 vježbi.
* Pokretanje prijevoda (usporedni posao): strojni prijevod odabranog seta i datoteka za ručni pregled.
* Ekran kataloga: lista naziva, pretraga, filteri (kategorija, mišić, oprema, službene/vlastite).
* Detalj vježbe: slika, upute, mišići, oprema.
* Vlastite vježbe: kreiranje, uređivanje, slika, arhiviranje umjesto brisanja kad postoji povijest.
* Atribucija free-exercise-db u "O aplikaciji".

**Gotovo kad:** katalog se gradi skriptom bez ručnih koraka, pretraga je trenutna na cijelom setu, a vlastita vježba s povijesti ne može se izgubiti brisanjem.

## Faza 3: Aktivni trening na iPhoneu (5 tj.)

**Cilj:** srce aplikacije. Trening snage bilježi se s 1 do 2 tapa po seriji. Ovo je najvažnija faza i ne smije se skraćivati.

* Pokretanje praznog treninga i dodavanje vježbi iz kataloga (predlošci dolaze u fazi 4).
* Ekran aktivnog treninga prema odjeljku 2: jedna otvorena vježba, retci serija, kvačica, drag & drop, automatski prijelaz na sljedeću nekompletiranu vježbu, prozor "Završi trening / Dodaj vježbu".
* Sve vrste unosa: težina × ponavljanja, vlastita težina, dodatni teret, potpomognuto, trajanje, trajanje + udaljenost.
* Warm-up i radne serije.
* **Smart defaults** po poziciji serije, odvojeno za warm-up. Prethodna serija vidljiva u retku.
* Rest timer: automatski start, +10/−10, zadana pauza po vježbi, spremanje kao vrijeme završetka.
* Supersetovi: kreiranje, naizmjenični redoslijed, pauza 0 pa zadana.
* RPE (1–10, korak 0,5) ili RIR.
* Uklanjanje vježbe s poništavanjem i popisom "Uklonjene vježbe".
* Plate Calculator unutar treninga (i kao zasebna komponenta za Dashboard).
* PR detekcija (samo radne serije, pravila po vrsti unosa) i sažetak treninga s bilješkama.
* **Oporavak prekinutog treninga:** spremanje nakon svake promjene i ponuda "Nastavi / Završi i spremi / Odbaci".
* Kardio sesija s ručnim unosom (trajanje, udaljenost, puls).

**Gotovo kad:** stvarni trening od 6 vježbi i 20 serija odrađen je bez zapinjanja, prisilno gašenje aplikacije usred treninga ne gubi ništa, a unit testovi pokrivaju smart defaults, volumen po vrsti unosa i PR pravila. **Od ovog trenutka aplikacija ide na TestFlight za osobnu upotrebu.**

## Faza 4: Predlošci i rasporedi (3 tj.)

**Cilj:** korisnik slaže treninge i rasporede, a "Započni" zna što je sljedeće.

* Uređivač treninga (predloška): vježbe, ciljane serije, supersetovi, pauze, redoslijed.
* Uređivač rasporeda: niz treninga i rest dana, broj ciklusa ili neograničeno, aktivan ili neaktivan.
* Logika napredovanja: sljedeći neodrađeni trening u nizu, kraj ciklusa, gašenje nakon zadnjeg ciklusa, propušteni dan ništa ne pomiče.
* Privremene izmjene po ciklusu: preskoči trening, izbaci vježbu, zamijeni vježbu, uz poništavanje dok trening nije završen.
* Pokretanje treninga iz predloška kopira podatke u `Session`.
* Gotovi programi: Full Body (3 dana), Upper/Lower (4), Push/Pull/Legs (3 do 6).
* Podsjetnici: fiksni dani ili fleksibilno, ne šalju se ako je trening već odrađen, otkazuju se tijekom aktivnog treninga.

**Gotovo kad:** testovi pokrivaju napredovanje kroz cikluse, propuštene dane, privremene izmjene i zakazivanje podsjetnika u oba načina.

## Faza 5: Povijest, statistika i praćenje tijela (3 tj.)

**Cilj:** korisnik vidi što je radio i kako napreduje.

* Odrađeni treninzi: lista, detalj, brisanje, kalendar s točkicama, filter po vrsti i sortiranje po datumu.
* Statistika kao kartice (Swift Charts): napredak težine po vježbi, procjena 1RM (Epley/Brzycki), tjedni i mjesečni volumen po mišićnoj skupini, frekvencija, PR lista s filterima.
* Body heatmap (frekvencija i volumen po regiji).
* Praćenje tijela: mjere, ručni unos, povijest i graf po mjeri (HealthKit uvoz dolazi u fazi 7).
* Predmemorija PR-ova i statistike radi brzine, uz mogućnost ponovnog izračuna.

**Gotovo kad:** statistika za godinu dana podataka (generirani testni podaci) otvara se ispod pola sekunde na starijem podržanom iPhoneu.

## Faza 6: Dashboard, postavke, onboarding, export (2 tj.)

* Dashboard: "Započni" (sljedeći trening iz aktivnog rasporeda ili prazan trening), kartica zadnjeg treninga, kartice koje korisnik dodaje i premješta (Plate Calculator, sljedeći trening, tjedni volumen).
* Postavke prema specifikaciji: tema, accent boja, jedinice, zadana pauza, PR postavke, RPE/RIR, zvuk kraja odmora, ploče i šipke, obavijesti.
* Onboarding: cilj, jedinice, visina i težina, Apple Health (pitanje se postavlja ovdje, povezivanje u fazi 7), iskustvo, oprema i dani u tjednu.
* Export u CSV i JSON te import vlastitog CSV-a.
* "Obriši sve podatke" (lokalno, a iCloud dio dodaje se u fazi 12).

**Gotovo kad:** export pa import na čistoj instalaciji vraća identične podatke (automatski test).

## Faza 7: HealthKit (2 tj.)

* Dozvole samo za korištene tipove, uz opise. Aplikacija radi i bez dozvole.
* Spremanje `HKWorkout` za treninge s iPhonea.
* Čitanje težine i visine za praćenje tijela.
* Uvoz kardio treninga iz Workouts aplikacije u povijest, bez duplikata.
* Kalorije: prikazuju se samo kad postoje u HealthKitu, inače se polje skriva.

**Gotovo kad:** trening se pojavljuje u aplikaciji Zdravlje i zatvara Activity Rings, a trčanje iz Workouts aplikacije pojavi se u povijesti točno jednom.

## Faza 8: Apple Watch aplikacija (5 tj.)

**Cilj:** cijeli trening snage može se voditi sa sata.

* watchOS aplikacija s ekranima iz specifikacije: početni, aktivni trening, rest timer, sažetak.
* `HKWorkoutSession` i `HKLiveWorkoutBuilder`: puls, kalorije, aplikacija ostaje aktivna tijekom treninga.
* Unos serija na satu: Digital Crown za težinu i ponavljanja, smart defaults iz `updateApplicationContext`.
* WatchConnectivity protokol: događaji s UUID-om i vremenom, `sendMessage` i `transferUserInfo`, jedan uređaj vodi trening, a drugi zrcali i šalje izmjene.
* Samostalan rad bez iPhonea uz sinkronizaciju kad se veza vrati.
* Haptika na kraju odmora.
* Complications (WidgetKit za watchOS): sljedeći trening i aktivni rest timer.

**Gotovo kad:** trening od početka do kraja odrađen je samo na satu, s iPhoneom izvan dosega dio vremena, i završni zapis na iPhoneu je potpun i bez duplikata.

**Stanje (studeni 2026.):** kod je spojen (PR #22) i provjeren na uparenim simulatorima iPhonea i sata. Na stvarnom satu još treba provjeriti Digital Crown, haptiku kraja odmora sa spuštenim zapešćem i trening s iPhoneom izvan dosega. Provjera čeka TestFlight (faza 14) ili instalaciju na sat iz Xcodea.

## Faza 9: Live Activity i notifikacije odmora (1,5 tj.)

* Live Activity (Zaključani zaslon i Dynamic Island): rest timer sustavskim odbrojavanjem, trenutna i sljedeća vježba, broj serija, gumb za potvrdu serije (App Intent).
* Tiha je i gasi se na kraju treninga.
* Lokalna notifikacija kraja odmora samo kad je iPhone zaključan i trening se vodi na iPhoneu, uz premještanje kod +10/−10.
* Uputa za Focus način u postavkama.

**Kako je napravljeno:** stanje za Live Activity (sljedeća serija, sljedeća vježba, broj serija) i pravilo za obavijest o kraju odmora su u GymKitu (`LiveStatus.swift`, s testovima). `WorkoutLiveUpdates` u aplikaciji slaže Live Activity i obavijest iz aktivnog treninga u bazi nakon svake promjene: s ekrana treninga, sa sata, iz gumba u Live Activityju i pri povratku u aplikaciju. Gumb "Potvrdi seriju" je `LiveActivityIntent`, koji sustav izvodi u procesu aplikacije, pa radi i kad je iPhone zaključan. Gumb se prikazuje samo kad serija ima upisane vrijednosti, inače dodir na Live Activity otvara aplikaciju. Trening započet na satu dok je iPhone zaključan dobiva Live Activity tek kad se aplikacija otvori, jer je iOS dopušta pokrenuti samo iz otvorene aplikacije.

**Provjera na uređaju:** Dynamic Island, gumb na zaključanom zaslonu i obavijest sa zaključanim iPhoneom provjeravaju se na stvarnom iPhoneu (simulator ne zaključava ekran kao uređaj).

## Faza 10: WorkoutKit za kardio (1,5 tj.)

* Kardio predlošci (trčanje, intervali) u rasporedima.
* Zakazivanje plana preko `WorkoutScheduler` prema podsjetnicima, uz ponovno zakazivanje kad se raspored promijeni.
* Podsjetnik otvara pregled plana s uputom za pokretanje na satu.
* Uvoz odrađenog treninga (iz faze 7) povezuje se s planiranim treningom u rasporedu, pa raspored napreduje.
* Ponašanje prema nalazima prototipa iz faze 0.

**Kako je napravljeno:** kardio trening je predložak vrste `cardio` s planom (`CardioPlan` u GymKitu: aktivnost, mjesto, zagrijavanje, blokovi rada i oporavka s brojem ponavljanja, hlađenje) umjesto vježbi. Novi kardio trening kreće od gotovog predloška (lagano trčanje, 5 km, intervali 8 × 1 min, intervali 6 × 400 m). Za sljedeći kardio trening aktivnog rasporeda `CardioWorkoutScheduler` zakazuje plan na sat za termin prvog podsjetnika, a nakon svake promjene rasporeda miče stari plan i zakazuje novi. Što treba promijeniti računa GymKit (`CardioScheduleSync`, s testovima). Id plana izvodi se iz rasporeda, stavke, ciklusa i sadržaja plana, pa se ne sprema i jednak je na svakom uređaju. Dodir na podsjetnik otvara pregled plana s uputom za pokretanje na satu i gumbom "Zakaži na satu" kad plan nije zakazan. Na Početnoj kardio ne pokreće trening u aplikaciji nego otvara isti pregled. Uvezeni trening sa sata povezuje se s rasporedom po planu koji HealthKit zapiše uz trening (`HKWorkout.workoutPlan`), a ako ga nema, po odrađenom planu u WorkoutKitu istog dana (`CardioPlanLinker`). Nakon toga raspored napreduje.

**Otvoreno:** nalazi prototipa WorkoutKita (`docs/prototipi.md`) još nisu upisani, pa je ponašanje složeno prema specifikaciji. Na stvarnom satu treba provjeriti kako se plan pojavljuje u aplikaciji Workout, zapisuje li HealthKit plan uz trening i što se događa bez sata u dosegu. Provjera čeka TestFlight.

## Faza 11: iPad layouti (2,5 tj.)

* `NavigationSplitView` sa sidebarom za sve tabove.
* Statistika u više stupaca i veći grafovi s usporedbom.
* Uređivači treninga i rasporeda: katalog i trening jedan pored drugog, drag & drop, odabir više vježbi odjednom.
* Katalog kao mreža sa slikama.
* Stage Manager i više prozora gdje ima smisla. Tipkovnički prečaci za osnovne radnje.

**Gotovo kad:** svi ključni ekrani prolaze provjeru na iPadu 11", 13" i u Split Viewu.

## Faza 12: CloudKit sinkronizacija (2 tj.)

* Uključivanje sinkronizacije za korisničku bazu i prikaz stanja (sinkronizirano, iCloud nije prijavljen, isključeno).
* Uključivanje i isključivanje u postavkama.
* Uklanjanje duplikata nakon synca i "last write wins".
* "Obriši sve podatke" briše i iCloud zapise.
* Objava sheme u CloudKit produkcijsko okruženje.
* Provjera na tri uređaja (iPhone, iPad, drugi iPhone) i s isključenim iCloudom.

**Gotovo kad:** podaci stvoreni offline na dva uređaja spoje se bez gubitka i duplikata.

## Faza 13: Lokalizacija, pristupačnost, privatnost (1,5 tj.)

* Hrvatski i engleski: sučelje kroz String Catalog, a katalog kroz pregledane prijevode. Provjera duljine tekstova na malim ekranima.
* Dynamic Type do najveće veličine na ključnim ekranima, VoiceOver oznake, kontrast.
* Pravila privatnosti na javnom URL-u, `PrivacyInfo.xcprivacy`, privatnosni opis u App Store Connectu.
* MetricKit za rušenja i performanse.

## Faza 14: Beta, poliranje i izdanje (3 tj.)

* Javni TestFlight s nekoliko korisnika iz teretane.
* Mjerenje performansi (pokretanje, otvaranje treninga, statistika) i ispravci.
* Ispravljanje grešaka iz bete.
* App Store materijali: snimke zaslona za iPhone, iPad i Watch na oba jezika, opis i ključne riječi.
* Slanje na review.

---

## Testiranje kroz cijeli projekt

* **Unit testovi** u `GymKit` za svu logiku (smart defaults, volumen, PR, 1RM, jedinice, rasporedi, izmjene, import/export, WatchConnectivity poruke). Pokreću se na CI-ju na svaki push.
* **Testovi migracije** kad se shema promijeni nakon prvog TestFlight izdanja.
* **UI test** osnovnog tijeka: Započni → serije → Završi → sažetak → povijest.
* **Ručna provjera na uređajima** na kraju svake faze (iPhone, iPad, Watch), jer simulator ne pokazuje stvarno ponašanje HealthKita, satova, Live Activityja i notifikacija.

## Glavni rizici

| Rizik | Utjecaj | Mjera |
|---|---|---|
| SwiftData + CloudKit se ponaša nepredvidivo (duplikati, spora sinkronizacija) | Visok | Prototip u fazi 0, pravila modela od faze 1, uklanjanje duplikata u kodu |
| WorkoutKit ne dopušta tijek koji specifikacija opisuje | Srednji | Prototip u fazi 0. Ako ne radi, kardio s Watcha ide preko naše aplikacije |
| Sinkronizacija sata i iPhonea gubi ili duplicira serije | Visok | Događaji s UUID-om, jedan uređaj vodi trening, testovi protokola |
| Faza 3 traje dulje od procjene | Visok | Ne skraćuje se. Ako kasni, kasnije faze se pomiču, a opseg ostaje |
| Prijevod kataloga kasni | Srednji | Počinje u fazi 2 kao usporedni posao. Nepregledane vježbe privremeno ostaju na engleskom |
| App Store review odbije zbog HealthKita ili privatnosti | Srednji | Faza 13 i jasni opisi dozvola. Rezerva u fazi 14 |

## Prvi koraci

1. Kreirati Xcode projekt s tri targeta i paketom `GymKit` te postaviti CI (faza 0).
2. Napraviti tri prototipa i zapisati nalaze.
3. Krenuti s modelom podataka (faza 1).

Xcode projekt mora se kreirati na Macu. Ostalo (paket `GymKit`, modeli, logika i testovi, CI, alat za katalog) može se pisati izravno u repozitoriju.
