# Sinkronizacija preko iClouda (faza 12)

Korisnička baza (SwiftData) sinkronizira se preko CloudKita, u privatnu bazu kontejnera `iCloud.com.brunodobric.gymapp`. Katalog vježbi je dio aplikacije i ne sinkronizira se. Tijek aktivnog treninga između iPhonea i sata ide preko WatchConnectivityja, ne preko iClouda.

## Kako radi

* **Uključivanje:** Postavke > iCloud > "Sinkronizacija preko iClouda" (zadano uključeno). Postavka je na uređaju (`UserDefaults`, ključ `syncEnabled`) i vrijedi od sljedećeg pokretanja, jer se otvorena baza ne može sigurno zamijeniti dok je ekrani koriste.
* **Otvaranje baze:** `AppServices` otvara bazu s `cloudKitDatabase: .private(...)`. Ako to ne uspije, baza se otvara lokalno, a Postavke pokazuju "Sinkronizacija nije pokrenuta". Build za besplatni Personal Team (`PERSONAL_TEAM`) uvijek je lokalan.
* **Stanje:** `SyncMonitor` čita stanje iCloud računa (`CKContainer.accountStatus`, `CKAccountChanged`) i događaje `NSPersistentCloudKitContainer.eventChangedNotification`. Logika stanja je u GymKitu (`Models/Sync.swift`).
* **Duplikati:** nakon svakog uvoza s iClouda i pri pokretanju `Deduplication.removeAllDuplicates` uklanja zapise s istim UUID-om, višak zapisa postavki i istu vrstu kartice na Početnoj.
* **Last write wins:** isti zapis promijenjen na dva uređaja razrješava CloudKit (vrijedi zadnja promjena). Više zapisa postavki nastaje samo kad novi uređaj stvori svoje postavke prije nego što stignu one iz iClouda. Tada ostaje zapis s obavljenim onboardingom, zatim onaj koji se više razlikuje od zadanih vrijednosti, zatim najmanji `id` (`UserSettings.preferred(in:)`). Shema se zbog toga nije mijenjala: nova verzija sheme s dijeljenim modelima rušila je SwiftData.
* **Obriši sve podatke:** kad sinkronizacija radi, prvo se briše zona `com.apple.coredata.cloudkit.zone` u privatnoj bazi (svi zapisi aplikacije u iCloudu), a tek onda podaci na uređaju. Ako iCloud nije dostupan, ništa se ne briše, jer bi se podaci obrisani samo na uređaju vratili sinkronizacijom.

## Objava sheme u produkciju

TestFlight i App Store koriste **Production** okruženje CloudKita, a Debug build iz Xcodea **Development**. Shema se mora objaviti u produkciju prije prvog TestFlight builda sa sinkronizacijom i nakon svake promjene sheme.

1. Pokrenuti Debug build iz Xcodea na uređaju prijavljenom u iCloud (plaćeni tim, ne Personal Team).
2. Početna > čekić > Prototipi > **CloudKit shema** > **Stvori shemu u Developmentu**. Alat šalje po jedan probni zapis svakog tipa sa svim poljima i odmah ga briše, pa u shemi ne nedostaju polja koja su obično prazna.
3. U [CloudKit konzoli](https://icloud.developer.apple.com): kontejner `iCloud.com.brunodobric.gymapp` > Development > Schema. Provjeriti da postoje tipovi `CD_Session`, `CD_SessionExercise`, `CD_SetLog`, `CD_WorkoutTemplate`, `CD_TemplateExercise`, `CD_TemplateSet`, `CD_Schedule`, `CD_ScheduleItem`, `CD_CycleOverride`, `CD_CustomExercise`, `CD_BodyMeasurement`, `CD_DashboardCard`, `CD_UserSettings`.
4. **Deploy Schema Changes…** u Production.
5. Nakon izdanja shema se smije samo proširivati (nova opcionalna polja i tipovi). CloudKit u produkciji ne dopušta brisanje ni preimenovanje polja.

## Provjera na uređajima

Tri uređaja s istim Apple ID-om (iPhone, iPad, drugi iPhone), TestFlight build. Upisati rezultat i napomenu.

| # | Provjera | Rezultat | Napomena |
|---|---|---|---|
| 1 | Postojeći lokalni podaci (iz build-a prije faze 12) pojave se na drugom uređaju | | |
| 2 | Trening završen na iPhoneu pojavi se na iPadu (vrijeme do pojave) | | |
| 3 | Offline na dva uređaja: svaki doda trening i mjerenje, pa se spoje. Ništa ne nedostaje, nema duplikata | | |
| 4 | Ista postavka promijenjena offline na dva uređaja: nakon spajanja svi uređaji imaju istu vrijednost (zadnju promjenu) | | |
| 5 | Isti JSON uvezen na dva uređaja: nakon sinkronizacije nema duplikata | | |
| 6 | Redoslijed vježbi i serija u predlošku jednak na svim uređajima | | |
| 7 | Odjava iz iClouda: Postavke pokazuju "iCloud nije prijavljen", aplikacija radi lokalno | | |
| 8 | Isključivanje sinkronizacije, ponovno pokretanje: "Sinkronizacija isključena", izmjene ne idu na druge uređaje | | |
| 9 | Ponovno uključivanje: izmjene napravljene dok je bila isključena stignu na druge uređaje | | |
| 10 | "Obriši sve podatke" na jednom uređaju: podaci nestanu i na ostalima, a u CloudKit konzoli (Production) nema zapisa | | |
| 11 | "Obriši sve podatke" bez mreže: poruka da iCloud nije dostupan, ništa nije obrisano | | |
| 12 | Novi uređaj s praznom aplikacijom: nakon onboardinga dođu podaci s ostalih uređaja | | |
