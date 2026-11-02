# Prototipi (faza 0)

Tri prototipa provjeravaju pretpostavke iz specifikacije prije nego što se na njima gradi. Kod je u Debug buildu: na ekranu **Početna** gumb s čekićem (gore lijevo) otvara **Prototipi**. Na satu je ulaz **Veza s iPhoneom**.

Prototipi se moraju isprobati na **stvarnim uređajima**: simulator ne pokazuje stvarno ponašanje iClouda, WorkoutKita i veze sa satom. Za CloudKit trebaju dva uređaja s istim Apple ID-om.

## Priprema

1. Na Macu: `brew install xcodegen`, pa u korijenu repozitorija `xcodegen generate`.
2. U `project.yml` upisati svoj `DEVELOPMENT_TEAM` (ili ga odabrati u Xcodeu za sva tri targeta).
3. U Apple Developer računu Xcode će sam stvoriti App ID-ove. Potrebno je da postoje:
   * iCloud kontejner `iCloud.com.brunodobric.gymapp`,
   * App Group `group.com.brunodobric.gymapp`,
   * HealthKit uključen za aplikaciju i sat.
   Ako je bundle prefiks `com.brunodobric` zauzet ili ne odgovara, promijeniti ga u `project.yml` na svim mjestima.
4. Pokrenuti shemu `GymApp` na iPhoneu. Watch aplikacija instalira se automatski na upareni sat.

---

## Prototip 1: SwiftData + CloudKit

**Pitanje:** rade li dvije konfiguracije (sinkronizirana i lokalna) zajedno, čuva li se redoslijed preko `orderIndex` i koliko traje sinkronizacija.

**Postupak**
1. Na uređaju A otvoriti **SwiftData + CloudKit**. Zapisati stanje iClouda.
2. Dodati 5 stavki. Zapisati vrijeme.
3. Na uređaju B otvoriti isti ekran i zabilježiti kad se stavke pojave.
4. Na uređaju B promijeniti redoslijed (Uredi, povlačenje). Provjeriti redoslijed na uređaju A.
5. Dodati stavke na oba uređaja dok je jedan u načinu rada u zrakoplovu, pa ga spojiti. Provjeriti ima li gubitaka ili duplikata.
6. Na uređaju A dodirnuti **Napuni lokalni katalog (870)**. U [CloudKit konzoli](https://icloud.developer.apple.com) (Development okruženje, privatna baza) provjeriti da postoje zapisi `CD_PrototypeSyncedItem`, a da **ne postoje** zapisi kataloga.
7. Na uređaju B lokalni katalog mora ostati 0.

**Nalazi**

| Provjera | Rezultat | Napomena |
|---|---|---|
| Baza se otvara s dvije konfiguracije | | |
| Vrijeme do pojave na drugom uređaju | | |
| Redoslijed se prenosi ispravno | | |
| Offline izmjene: gubitci / duplikati | | |
| Lokalni katalog nije u iCloudu | | |

## Prototip 2: WorkoutKit zakazivanje

**Pitanje:** može li aplikacija zakazati plan trčanja u aplikaciju Workout na satu i kako to izgleda korisniku (specifikacija, odjeljak 6).

**Postupak**
1. Otvoriti **WorkoutKit zakazivanje**. Zapisati "Podržano" i "Najviše planova".
2. **Zatraži dozvolu**. Zapisati kako izgleda dijalog.
3. **Zakaži trčanje za 5 min**. Na satu otvoriti aplikaciju Workout: pojavljuje li se plan, kada i gdje.
4. Pokrenuti plan na satu i završiti ga (može kratko). Provjeriti mijenja li se "završen" u popisu.
5. **Zakaži trčanje za 24 h** nekoliko puta i provjeriti što se dogodi kad se prijeđe najveći broj planova.
6. Ponoviti korak 3 sa satom isključenim ili izvan dosega.

**Nalazi**

| Provjera | Rezultat | Napomena |
|---|---|---|
| Podržano / najviše planova | | |
| Plan se pojavljuje na satu (kada, gdje) | | |
| Korisnik ga pokreće sam (potvrđeno) | | |
| Status "završen" se ažurira | | |
| Ponašanje iznad ograničenja | | |
| Ponašanje bez sata | | |

## Prototip 3: WatchConnectivity

**Pitanje:** kako se ponašaju tri kanala u stvarnim uvjetima teretane i radi li prepoznavanje duplikata.

**Postupak** (ekran **Veza sa satom** na iPhoneu i **Veza s iPhoneom** na satu)
1. Obje aplikacije u prvom planu: poslati `sendMessage` u oba smjera. Zapisati kašnjenje (ms).
2. iPhone zaključan, aplikacija u pozadini: poslati `sendMessage` sa sata (očekuje se "nije dostupan") i `transferUserInfo`. Otključati iPhone, otvoriti aplikaciju i provjeriti je li događaj stigao.
3. `applicationContext` poslati nekoliko puta zaredom: drugi uređaj treba primiti samo zadnji.
4. **Isti događaj dvaput**: drugi primitak mora biti označen kao "DUPLIKAT odbačen".
5. iPhone udaljiti izvan dosega (ili Bluetooth isključen, Wi-Fi uključen), pa ponoviti korak 1.

**Nalazi**

| Provjera | Rezultat | Napomena |
|---|---|---|
| sendMessage, oba u prvom planu (ms) | | |
| transferUserInfo s iPhoneom zaključanim | | |
| applicationContext šalje samo zadnje stanje | | |
| Duplikat prepoznat | | |
| Ponašanje izvan dosega | | |

---

## Odluke nakon prototipa

Upisati ovdje što se mijenja u specifikaciji. Ako sve odgovara, napisati "Bez izmjena".
