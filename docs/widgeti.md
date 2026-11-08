# Widgeti, kontrola i komplikacije

Widgeti na početnom i zaključanom zaslonu (iPhone, iPad, StandBy), kontrola "Započni trening" i komplikacije
na satu. Što prikazuju opisano je u `SPECIFIKACIJA.md` (odjeljak 6, "Widgeti i kontrole" i "Complications").

## Snimka umjesto baze

Widget extension nema pristup SwiftData bazi (CloudKit baza je u kontejneru aplikacije, a widget ima malo
memorije i vremena). Zato aplikacija slaže **snimku** (`WidgetSnapshot`, paket `WidgetData`) i sprema je kao
JSON u App Group `group.com.brunodobric.gymapp` (`WidgetSnapshotStore`). Widget samo čita tu datoteku.

* `Packages/GymKit/Sources/WidgetData`: snimka, spremanje, poveznice (`WidgetLink`) i logika bez baze
  (novi tjedan, krivulja težine, opis plana vježbe). Ovisi samo o `Units`, pa je linka i widget extension.
* `Packages/GymKit/Sources/WidgetSync`: `WidgetSnapshotBuilder` slaže snimku iz baze (sljedeći trening iz
  rasporeda, tekući tjedan, težina, zadnji trening i najnoviji rekord).
* `App/Widgets/WidgetRefresher.swift`: nakon svakog spremanja baze (`ModelContext.didSave`, s odgodom od
  sekunde) slaže novu snimku. Widgeti i kontrole se osvježavaju samo kad se snimka promijeni, jer sustav
  ograničava broj osvježavanja. Novi dio aplikacije koji sprema podatke (npr. Prečaci) zato ne treba ništa javljati.
* Snimka nosi tekstove koji ovise o jeziku i jedinici kad ih widget ne može sam složiti (vrijednost rekorda).
  Težina je u kg, a jedinica za prikaz ide uz nju.

Vremenska crta widgeta ima zapis za svaku iduću ponoć: tjedan, "danas" i "prije N dana" se mijenjaju i dok
je aplikacija zatvorena. Tjedan iz prošlog tjedna widget sam prazni (`WidgetSnapshot.Week.current(at:)`).

## Otvaranje aplikacije

* Dodir na widget otvara poveznicu `apolon://…` (`WidgetLink`): Početna, pregled tjedna, praćenje tijela ili
  zadnji trening. `RootView` je prima u `onOpenURL`, a Početna otvara list (`HomeRequest`).
* Gumb ▶ i kontrola izvršavaju `StartWorkoutFromWidgetIntent` (`Shared/LiveActivity`). Intent ima
  `openAppWhenRun`, pa ga sustav pokreće u aplikaciji: `AppRequestRouter` preda zahtjev Početnoj, koja pokreće
  sljedeći trening ili nastavlja trening u tijeku (isto kao ⌘N). U extensionu je izvedba prazna
  (`Widgets/WidgetActions.swift`), kao kod Live Activityja.

## Sat

Sat nema bazu s iPhonea. Tjedni cilj i težina idu satu u kontekstu (`WatchContextPayload.week` i
`bodyWeightKg`, opcionalno, pa stariji sat i dalje čita kontekst). Aplikacija na satu ih sprema u
`ComplicationState` (App Group), a komplikacije u `WatchWidgets/` ih čitaju.

## Provjera

* `swift test --package-path Packages/GymKit` pokriva snimku (`WidgetDataTests`) i slaganje iz baze
  (`WidgetSyncTests`).
* Na uređaju ili simulatoru: dodati svaki widget, odraditi trening, upisati težinu i provjeriti da se widgeti
  osvježe; prebaciti datum na idući tjedan i provjeriti prazan tjedan. Kontrolu dodati u Kontrolni centar.
