# Performanse

Faza 14 mjeri tri stvari koje korisnik najviše osjeti: pokretanje aplikacije, otvaranje treninga i statistiku. Ovaj dokument kaže što se mjeri, kojim alatom, koji su ciljevi i kamo se upisuju rezultati.

## Što je ugrađeno u kod

Signposti (`PerformanceSignpost` u `App/Diagnostics/MetricsReporter.swift`) označavaju operacije. Vide se u Instrumentsu (Points of Interest i os_signpost), a MetricKit ih jednom dnevno zbraja u izvještaj koji se sprema u Postavke > O aplikaciji > Dijagnostika.

| Signpost | Gdje | Što obuhvaća |
|---|---|---|
| `AppServicesStart` | `GymApp.init` | otvaranje baze (lokalno ili s CloudKitom), veza sa satom, praćenje sinkronizacije |
| `CatalogLoad` | `CatalogStore` | učitavanje kataloga vježbi iz bundlea |
| `WorkoutStart` | Početna i pregled sljedećeg treninga | pokretanje treninga iz predloška (vježbe, serije i smart defaults) |
| `WorkoutOpen` | `ActiveWorkoutScreen` | prethodne vrijednosti za sve vježbe kad se ekran treninga otvori |
| `Statistics` | `StatisticsScreen` | volumen, učestalost i heatmap |
| `StatisticsRecords` | `StatisticsScreen` | osobni rekordi kroz cijelu povijest |

Vrijeme pokretanja (do prvog prikaza) MetricKit mjeri sam (`applicationLaunchMetrics`), a isto se vidi u Xcode Organizeru (Launch Time) kad aplikacija ima korisnike na TestFlightu.

U paketu `GymKit` test "Statistika za godinu dana" (`StatsTests`) mjeri statistiku nad godinom treninga i pada ako je red veličine pogrešan.

## Ispravci iz faze 14

* **Osobni rekordi u statistici:** svaki trening se prije uspoređivao s cijelom ranijom poviješću vježbe, pa je vrijeme raslo s kvadratom broja treninga. Sada se povijest nakon svakog treninga sažima (`PersonalRecordDetector.condensed`) na serije koje mogu odlučiti o rekordu. Test provjerava da su rekordi isti kao s punom poviješću.
* **Rekordi se ne računaju ponovno** kad se na ekranu Statistika promijeni samo razdoblje grafa ili heatmapa.
* **Pokretanje treninga iz predloška:** smart defaults za svaku vježbu prije su čitali serije iz svih ranijih izvođenja, a trebaju samo zadnje. Sada se serije čitaju samo dok se ne nađe zadnje izvođenje.

## Ciljevi

Mjeri se na najstarijem podržanom iPhoneu koji je dostupan, u Release buildu, s realnom količinom podataka (barem godina treninga, vidi niže).

| Mjerenje | Cilj |
|---|---|
| Hladno pokretanje do prvog prikaza | ispod 400 ms (Appleova preporuka) |
| `AppServicesStart` | ispod 100 ms |
| `WorkoutStart` (predložak sa 6 vježbi) | ispod 150 ms |
| `WorkoutOpen` | ispod 100 ms |
| `Statistics` | ispod 250 ms |
| `StatisticsRecords` | ispod 250 ms |

## Kako izmjeriti (Mac i iPhone)

1. U Xcodeu: Product > Profile (⌘I), Release build na iPhoneu spojenom kabelom.
2. **Pokretanje:** predložak App Launch. Prije mjerenja ugasiti aplikaciju i pričekati par sekundi, mjeriti tri puta i uzeti srednju vrijednost.
3. **Operacije:** predložak Time Profiler, pa dodati instrument os_signpost (ili Points of Interest). Filtrirati po kategoriji `Performanse` (MetricKit sam određuje subsystem log handlea). Svaki signpost iz tablice ima trajanje.
4. Ako je nešto sporije od cilja, u Time Profileru odabrati raspon tog signposta i pogledati najteže funkcije (Invert Call Tree, Hide System Libraries).

Podaci za mjerenje: uvoz sigurnosne kopije s realnim podacima (Postavke > Podaci > Uvezi iz datoteke) ili vlastiti podaci nakon nekoliko tjedana bete. Na kraju mjerenja aplikacija se može vratiti brisanjem podataka.

## Rezultati

Upisuje se nakon svakog mjerenja: datum, uređaj, verzija, količina podataka i brojke.

| Datum | Uređaj | Build | Treninga u bazi | Pokretanje | WorkoutStart | WorkoutOpen | Statistics | StatisticsRecords |
|---|---|---|---|---|---|---|---|---|
| | | | | | | | | |
