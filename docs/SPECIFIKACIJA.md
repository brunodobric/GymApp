# Specifikacija i Arhitektura Gym Aplikacije (v3)

Ovaj dokument sadrži ažuriranu i proširenu specifikaciju moderne iOS (Swift) gym aplikacije. Obuhvaća najbolje elemente iz originalnog plana i uključuje poboljšanja fokusirana na UX, pouzdanost podataka, vizualni sadržaj i retenciju korisnika.

**Što je novo u v3:** uklonjena proturječja (račun, sinkronizacija Watcha, notifikacije, rasporedi, RPE, kalorije), dodan model podataka (odjeljak 8), vrste serija, oporavak prekinutog treninga, tehnička ograničenja SwiftData + CloudKit, plan lokalizacije kataloga i obaveze oko privatnosti. Opseg MVP-a ostaje isti kao u v2. Popis svih izmjena nalazi se na kraju dokumenta.

**Važno:** Aplikacija mora biti od starta optimizirana za **iPhone** (uključujući veće modele i dual-device scenarije) i **iPad**. Na iPadu korisnici očekuju bogato iskustvo za pregled grafova, statistika, analize napretka i slaganje/planiranje treninga. Companion **Apple Watch** aplikacija je obavezna od prvog releasea.

---

## 1. Baza podataka i Katalog vježbi

### Primarni izvor podataka
* **Izvor:** **MoveKit** (movekit.com), paket "Complete Exercise Library": 582 vježbe, svaka s animiranim klipom, posterom i metapodacima (mišići, oprema, obrazac pokreta, razina, upute, česte greške).
* **Licenciranje:** komercijalna licenca (MoveKit License Agreement v1.0). Klipove i tekstove smijemo ugraditi u aplikaciju, pretvoriti u drugi format i izrezati. Navođenje izvora nije obavezno. Sirove datoteke ne smiju biti javno dostupne, pa licencirani sadržaj nije u javnom repozitoriju (`docs/movekit.md`). Do studenog 2026 izvor je bio free-exercise-db (Unlicense).
* **Količina:** svih 582 vježbi iz paketa.
* **Vizualni sadržaj:** animirani klip u petlji i poster za svaku vježbu, korak-po-korak upute i česte greške. Body heatmap (primarni i sekundarni mišići) za vizualni prikaz.
* **Animacija vježbe:** na detalju vježbe MoveKit klip se vrti u petlji bez zvuka, a gumb u kutu pauzira i nastavlja. Klip stoji dok nije na ekranu ili je aplikacija u pozadini i ne prekida glazbu koju korisnik sluša. Uz Smanji kretanje klip ne kreće sam: prikazuje se poster, a korisnik ga može pokrenuti gumbom. U mreži kataloga prikazuje se poster. Build bez MoveKit paketa (CI, klon repozitorija) nema klipove ni upute, pa detalj vježbe prikazuje samo mišiće i detalje.

### Kategorizacija i Strukturiranje
* **Kategorije / Anatomija:** Prsa, Leđa, Ramena, Ruke, Noge, Core/Trbuh, Kardio.
* **Mapiranje kategorija:** MoveKit koristi vlastite nazive mišića, opreme i obrazaca pokreta (npr. `primaryMuscles: ["Quadriceps"]`, `movementPattern: ["Squat"]`). Ručna tablica `Tools/CatalogBuilder/mapping.json` prevodi ih na naše kategorije, mišićne skupine, opremu i regije body heatmapa, a `overrides.json` ispravlja pojedine vježbe. Obje su dio repozitorija i koriste se pri izgradnji kataloga.
* **Mišićne skupine:** Primarni i sekundarni mišići s mapiranjem na body heatmap.
* **Oprema:** Bučice, Šipka, Sprave/Kablovi, Vlastita težina (Bodyweight), Kettlebell, Trake, itd.
* **Tipovi pokreta:** Push / Pull / Legs (izračunato na temelju primarnih mišića).
* **Dodatni filteri:** Razina težine (beginner/intermediate/advanced), tip (isolation/compound), dostupna oprema korisnika.

### Unos i upravljanje vlastitim vježbama (Custom Exercises)
* **Lokalno kreiranje:** Mogućnost dodavanja vlastitih vježbi (naziv, opis, kategorija, oprema, opcionalne slike).
* **Arhitektura modela:** Polje `isCustom = true` (ili `source = "user"`).
* **Prava nad podacima:** Korisnik može uređivati i brisati samo vlastite vježbe. Službene su zaštićene.
* **Brisanje custom vježbe koja ima povijest:** vježba se ne briše fizički nego se arhivira (skriva iz kataloga i odabira), kako odrađeni treninzi i statistika ne bi izgubili podatke.

### Pohrana kataloga
* Službeni katalog isporučuje se uz aplikaciju kao **datoteka samo za čitanje** (`catalog.json`, koju generira `Tools/CatalogBuilder`) i učitava se u memoriju. Nije u SwiftData bazi: nepromjenjiv je i malen, pa nema migracija ni sinkronizacije, a pretraga je trenutna. Ne sinkronizira se, jer bi se inače vježbe slale u iCloud svakog korisnika.
* Klipovi i posteri isporučuju se u bundleu (HEVC 1280 px, oko 110 MB za sve vježbe; On-Demand Resources ako veličina postane problem) i nikad ne idu u iCloud. Javni dio kataloga (`Resources/Catalog/catalog.json`: nazivi, mišići, oprema, vrsta unosa) je u repozitoriju, a upute, česte greške i mediji dolaze iz privatnog MoveKit dodatka (`Resources/MoveKit/`, ne commita se).
* Custom vježbe žive u korisničkoj bazi koja se sinkronizira.
* Korisnički podaci na službenu vježbu pokazuju preko stabilnog tekstualnog identifikatora (`catalogId`, MoveKit slug, npr. `barbell-squat`), a ne preko relacije između baza. Tako ažuriranje kataloga u novoj verziji aplikacije ne lomi povijest.
* **Prijelaz s free-exercise-db (katalog verzije 2):** `catalog.json` ima tablicu `legacyIds` (stari id → novi slug ili `null`, iz `Tools/CatalogBuilder/legacy-ids.json`). Katalog stari id prepoznaje pri traženju, a `CatalogIdMigration` u GymKitu pri pokretanju, nakon uvoza i nakon sinkronizacije prepisuje spremljene id-jeve u treninzima, predlošcima i izmjenama ciklusa. Vježba bez para u MoveKitu (8 od 187) postaje vlastita vježba istog naziva, pa povijest i rekordi ostaju.

### Lokalizacija kataloga (HR + EN)
* MoveKit postoji samo na engleskom. Hrvatski nazivi svih 582 vježbi su u `Tools/CatalogBuilder/names-hr.json` (javno, naš prijevod naziva). Prijevod uputa i čestih grešaka je MoveKit tekst, pa ide u privatni `translations-hr.json` uz paket; dok ga nema, upute se prikazuju na engleskom uz napomenu.
* Postupak: odabrani set vježbi (vidi "Količina") strojno se prevodi, a zatim ručno pregledava (osobito nazivi, jer se u teretanama često koriste engleski nazivi). Prijevodi se drže u String Catalogu ili u zasebnoj datoteci kataloga po jeziku.
* Ako je vježba bez pregledanog prijevoda, prikazuje se engleski naziv.
* Ovo je velik zasebni zadatak i treba ga planirati kao posebnu stavku rada, a ne kao dio programiranja.

---

## 2. Podržani tipovi treninga i Sustav bilježenja (Logging Engine)

Aplikacija podržava 3 glavna modula:

### A. Trening snage i hipertrofije (Bodybuilding / Powerlifting)
* **Unos po serijama:** Težina (kg/lbs) × Broj ponavljanja.
* **Vrste unosa po vježbi:** svaka vježba ima jednu vrstu unosa, koja određuje polja u retku i način računanja volumena:

| Vrsta | Primjer | Polja | Volumen |
|---|---|---|---|
| Težina × ponavljanja | Bench press | kg, reps | kg × reps |
| Vlastita težina | Sklekovi | reps | ne računa se u volumen težine; prati se broj ponavljanja |
| Vlastita težina + teret | Zgibovi s pojasom | dodatni kg, reps | dodatni kg × reps (tjelesna masa se ne pribraja) |
| Potpomognuta | Zgibovi na stroju s protutegom | pomoć u kg, reps | ne računa se u volumen; PR je **manja** pomoć |
| Trajanje | Plank | sekunde | ukupno vrijeme |
| Trajanje + udaljenost | Farmer's walk, veslanje | vrijeme, metri (opcionalno kg) | ukupno vrijeme i udaljenost |

  Vrsta se za službene vježbe određuje kroz mapiranje kataloga, a za custom vježbe bira je korisnik.
* **Smart Defaults + Inline povijest:** Pamti se zadnji put odrađena težina i broj ponavljanja **po seriji** za svaku vježbu.  
  Primjer: ako je korisnik zadnji put na bench pressu radio 80 kg × 8, zatim 85 kg × 8, zatim 90 kg × 8 — sljedeći put će mu prva serija biti pretpopunjena s 80 kg, druga s 85 kg, itd.  
  Nema automatskog progresivnog prijedloga (zasad).  
  Prethodna serija je uvijek vidljiva u retku unosa.
* **Statusi serija:** Radne serije, Warm-up.  
  **Warm-up serije ne ulaze u PR-ove, volumen ni 1RM estimaciju.** Prikazuju se u povijesti, ali su vizualno odvojene. Smart defaults pamte ih zasebno od radnih serija.
* **RPE (Rate of Perceived Exertion):** Opcionalni unos po seriji, na ljestvici **od 1 do 10 u koracima od 0,5** (odabir kotačićem ili brzim gumbima, ne slobodnim unosom). Vrijednosti izvan ljestvice nisu moguće, kako statistika ne bi bila pokvarena.  
  U Postavkama korisnik može umjesto RPE odabrati **RIR** (ponavljanja u rezervi, 0–5+). Interno se sprema jedna vrijednost i preračunava za prikaz (RIR = 10 − RPE).  
  Vidljiv je odmah u retku unosa. Prikazuje se u povijesti i statistici.
* **Supersets:**  
  Prilikom kreiranja treninga postoji opcija **Dodaj superset**. Unutar superseta korisnik bira vježbe.  
  Tijekom treninga se prikazuje s naslovom “Superset” i ispod njega vježbe koje su u njemu.  
  Serije se izvode naizmjenično.  
  Defaultna pauza: 0 sekundi nakon svih vježbi osim zadnje u supersetu, a nakon zadnje vježbe vrijedi **zadana pauza iz Postavki** (tvornički 90 s), osim ako je za tu vježbu ili superset postavljena drukčija.  
  Primjer (2 vježbe, zadana pauza 90 s): pauza 0 nakon prve, 90 s nakon druge.  
  Primjer (3 vježbe, zadana pauza 120 s): pauza 0 nakon prve dvije, 120 s nakon treće.  
  Korisnik može dodati superset i ad-hoc tijekom samog treninga.
* **Osobni rekordi (PR):** Glavni rekord je procjena 1RM (Epley s ponavljanjima u rezervi iz RPE-a ili RIR-a, samo serije do 12 ponavljanja do otkaza). Uz nju se prate najteža serija po rasponu ponavljanja (1, 3, 5, 8, 10, 12, 15+), najveća težina, volumen vježbe u treningu i najviše ponavljanja; za potpomognute vježbe najmanja pomoć, za vježbe s trajanjem ili udaljenošću najdulje trajanje i najveća udaljenost. Samo radne serije. Rekord po volumenu jedne serije ne postoji.  
  Protiv previše rekorda: rekord se računa od četvrtog izvođenja vježbe, napredak mora biti barem 1 % i barem 0,5 kg, a nakon pauze od 6 tjedana prva dva treninga ne daju rekord. Sažetak ističe najviše jedan rekord po vježbi i najviše tri ukupno, poredane po veličini napretka prema uobičajenom kolebanju vježbe (složene vježbe 3 %, ostale 5 %, ponavljanja 8 %); ostali su pod "Još manjih rekorda".  
  Korisnik može u Postavkama potpuno isključiti PR-ove, odabrati koje tipove želi pratiti i isključiti pojedine vježbe iz rekorda.  
  Slavljenje se prikazuje na kraju treninga — u sažetku koji iskoči nakon zatvaranja treninga.

### B. Kardio trening (Cardio)
* **Unos:** Trajanje, Udaljenost, opcionalno prosječni puls.
* **Kalorije** se ne unose ručno. Prikazuju se samo kad postoje u HealthKitu (vidi "Kalorije" u odjeljku 6).

### C. Hibridni / CrossFit / WOD formati (kasnije)
* **AMRAP, For Time, EMOM / Intervalni tajmeri** s namjenskim sučeljima.

### Ekran aktivnog treninga
* Prikazuje se popis svih vježbi za taj trening.
* Prva vježba je otvorena po defaultu.
* Ispod naslova vježbe je popis serija. Svaki redak ima:
  * Težinu
  * Broj ponavljanja
  * Izračunati volumen
  * Kvačicu desno
* Klik na polje težine ili ponavljanja omogućuje izmjenu.
* Težina i ponavljanja se biraju kotačićem umjesto tipkovnice: težina u koracima od 2,5 kg (5 lbs), ponavljanja od 1 do 50. Kotačić kreće od trenutne vrijednosti, prošlog treninga ili prazne šipke. Dodir na broj iznad kotačića otvara tipkovnicu za vrijednost koje na kotačiću nema (npr. 83 kg). Isto vrijedi za ciljeve u predlošku.
* Klik na kvačicu kompletira seriju (zasivi redak) i pokreće rest timer.
* Rest timer se pojavljuje kao redak ispod s linijom koja teče i gumbima +10 / -10.
* U jednom trenutku samo jedna vježba može biti otvorena.
* Korisnik može otvarati i zatvarati vježbe i kompletirati serije bilo kojim redoslijedom.
* Nakon kompletiranja zadnje serije u vježbi, app se automatski vraća na prvu nekompletiranu vježbu.
* Korisnik može mijenjati redoslijed vježbi povlačenjem (drag & drop).
* **Plate Calculator je dostupan i ovdje:** dugi pritisak na polje težine (ili stavka u izborniku vježbe) otvara kalkulator s već upisanom težinom te serije.
* **Izbacivanje vježbe iz treninga može se poništiti:** nakon izbacivanja pojavljuje se traka "Vježba uklonjena · Poništi", a do kraja treninga vježbu je moguće vratiti i iz izbornika "Uklonjene vježbe" s već upisanim serijama.
* **Serija se briše povlačenjem retka ulijevo** (ili iz izbornika na oznaci serije). Nakon brisanja pojavljuje se traka "Serija obrisana · Poništi" koja vraća seriju na isto mjesto s upisanim vrijednostima.
* Kad se kompletira zadnja serija zadnje nekompletirane vježbe, pojavljuje se prozor: **Završi trening** ili **Dodaj vježbu**.
* Ako korisnik odabere Završi trening → prikazuje se sažetak treninga koji uključuje:
  * Trajanje
  * Ukupni volumen
  * PR-ove (ako postoje)
  * Kalorije (samo ako ih HealthKit ima za taj trening, inače se polje ne prikazuje)
  * Notes
  * Gumb **Zatvori** na dnu.

### Oporavak prekinutog treninga
* Aktivni trening se sprema u bazu **nakon svake promjene** (svaka kompletirana serija, izmjena težine, promjena redoslijeda), a ne tek na kraju.
* Ako se aplikacija sruši, sustav je ugasi ili se mobitel isključi, pri sljedećem pokretanju pojavljuje se: **Nastavi trening** ili **Završi i spremi** ili **Odbaci**.
* Stanje rest timera sprema se kao trenutak završetka (datum i vrijeme), a ne kao preostale sekunde, pa se nakon oporavka ispravno nastavlja ili je već istekao.
* Trening koji je otvoren dulje od 6 sati bez ikakve aktivnosti nudi se za zatvaranje (s trajanjem do zadnje kompletirane serije).

---

## 3. Ključne funkcionalnosti i Korisničko iskustvo (UI/UX)

Aplikacija koristi **adaptivni layout** (SwiftUI size classes / NavigationSplitView) kako bi pružila optimalno iskustvo na iPhoneu i iPadu od prvog dana:

- **iPhone:** Brzi, jednoručni logging fokusiran na minimalan broj tapova, velike kontrole i jasnu hijerarhiju.
- **iPad:** Multi-column / sidebar layout. Idealno za pregled detaljnih grafova i statistika, usporedbu napretka, slaganje i uređivanje rutina, pregled kataloga vježbi s slikama i planiranje treninga unaprijed.

### Glavna navigacija (Tabovi)
Aplikacija je podijeljena na 5 glavnih tabova (Dashboard je početni):

1. **Dashboard** — Početni ekran.
   * Na vrhu kartica **Započni** istog oblika kao kartice ispod, s laganom poluprozirnom pozadinom u boji akcenta da se istakne: sljedeći trening svakog rasporeda i prazan trening.
   * Ispod sljedećeg treninga svakog rasporeda je red **Odaberi drugi trening**: otvara popis treninga tog rasporeda (sljedeći je označen, a trening koji se ponavlja nudi se jednom, s izmjenama tekućeg ciklusa) i ispod njega ostalih spremljenih treninga snage. Dodir pokreće odabrani. Raspored napreduje samo kad je odrađen njegov sljedeći trening, pa drugi trening ne pomiče niz.
   * Kad nema aktivnog rasporeda, a postoje spremljeni treninzi, prvi red kartice je **Odaberi trening**: otvara popis spremljenih treninga snage (s vježbama) i dodir pokreće odabrani. Prazan trening ostaje ispod. Isto radi ⌘N (i kad raspored nudi samo kardio).
   * Dok trening traje, ekran treninga se povlačenjem prema dolje (ili gumbom Smanji) sažima u tu karticu. Kartica prikazuje isto što i Live Activity: vježbu i seriju, odbrojavanje odmora, težinu i ponavljanja s gumbima − i + te kvačicu za potvrdu serije. Dodir na karticu ponovno otvara cijeli ekran treninga.
   * Ispod njega kartica zadnjeg treninga (datum, trajanje, tip). Zadano je prikazana, a korisnik je može ukloniti ili premjestiti kao ostale kartice.
   * Ispod toga gumb za dodavanje widgeta.
   * **Plate Calculator** je jedan od dostupnih widgeta.
   * Gore desno gumb **Postavke**.
2. **Odrađeni treninzi**
3. **Rasporedi**
4. **Katalog vježbi**
5. **Statistika**

- **iPhone:** Standardni bottom tab bar.
- **iPad:** Sidebar (NavigationSplitView) s istim sekcijama.

### Postavke (pristup s Dashboarda)
Prvi ekran je popis kategorija u grupama, a svaka kategorija otvara svoju stranicu: **Prikaz, Trening, Ploče i šipka** · **Obavijesti, Zdravlje, iCloud** · **Podaci** · **O aplikaciji**. Na iPadu je isti list s istim stranicama.

* **Tema:** Svijetlo / Tamno / Automatski (prema sustavu).
* **Accent boja:** Korisnik može birati accent boju aplikacije.
* **Live Activity:** prema zadanom prati temu i accent boju aplikacije. Kad se "Prati aplikaciju" isključi, bira vlastitu temu i boju (kreću od aplikacijinih). Tema vrijedi za zaključani zaslon; Dynamic Island je uvijek crn, pa se ondje mijenja samo boja.
* **Jedinice:** kg / lbs.
* **Default rest timer:** Podešavanje zadanog vremena (default 90s).
* **PR postavke:** Uključivanje/isključivanje i odabir tipova PR-ova.
* **Obavijesti:** Globalne postavke obavijesti.
* **Sinkronizacija (iCloud):**
  * Aplikacija **nema vlastiti korisnički račun ni prijavu**. Sinkronizacija ide preko korisnikovog iCloud računa i **CloudKit** privatne baze, bez vlastitog servera. Samo Apple ekosustav (iPhone, iPad, Watch).
  * Prikaz stanja: "Sinkronizirano preko iClouda", "iCloud nije prijavljen" (s uputom gdje se prijaviti u Postavkama sustava) ili "Sinkronizacija isključena".
  * Uključivanje / isključivanje sinkronizacije.
  * **Obriši sve podatke:** briše sve lokalne podatke i, ako je sinkronizacija uključena, podatke aplikacije u korisnikovom iCloudu. Prije brisanja nudi se export. Traži dvostruku potvrdu.
* **Mjerenje napora:** RPE ili RIR.
* **Zvuk kraja odmora:** uključen / isključen (vidi "Rest timer i notifikacije" u odjeljku 6).
* **Podaci:**
  * Export u CSV / JSON.
  * Import iz CSV-a (vlastiti backup — format koji app i exportira).
  * Import treninga iz CSV izvoza drugih aplikacija (vidi odjeljak 5).
* **O aplikaciji:** verzija, izvor kataloga (MoveKit), atribucija MuscleMap, pravila privatnosti.

### Opis tabova

1. **Dashboard** — opisan gore. "Widgeti" na Dashboardu su **kartice unutar aplikacije** (npr. zadnji trening, Plate Calculator, sljedeći trening, tjedni volumen) koje korisnik dodaje, uklanja i premješta. To nisu WidgetKit widgeti na početnom zaslonu sustava (oni su u popisu "Kasnije").
2. **Odrađeni treninzi** — Povijest svih završenih treninga s filterima i detaljima.
   * Lista treninga prikazuje: datum, tip i trajanje.
   * Klik na trening otvara detalje:
     * Sve vježbe
     * Sve serije po vježbi
     * Bilješke
     * Na dnu mapa mišića (tijelo sprijeda i straga) obojena prema broju tvrdih serija po mišiću, uz popis mišića s brojem serija. Skala je fiksna (1 do 2, 3 do 5, 6 do 9, 10 i više serija), pa lagan trening ostaje svijetao. Pravila brojanja su u odjeljku "Tvrde serije" niže. Isti prikaz ima sažetak nakon treninga. Trening bez serija (npr. uvezen iz Zdravlja) nema mapu.
   * Moguće je izbrisati trening.
   * U detaljima gore desno, uz brisanje, izbornik s dvije opcije:
     * **Uredi trening:** naknadno mijenjanje naziva, početka i kraja, vježbi, serija i bilješki. Izmjene se spremaju tek na "Spremi", a "Odustani" ih odbacuje. Kao kod završetka treninga, serije bez kvačice i vježbe bez završene serije se ne spremaju. Izmjene se ne prenose u Zdravlje.
     * **Novi trening iz ovog:** stvara novi trening (predložak) s istim nazivom, istim vježbama redom, pauzama, supersetovima i serijama (završene serije postaju ciljevi). Otvara se u uređivaču treninga, gdje se može preimenovati i izbaciti što ne treba. "Odustani" ga briše, a "Spremi" ga ostavlja u Rasporedima pod Treninzima.
   * Trening uvezen iz Zdravlja nema taj izbornik.
   * Gore desno gumb za **kalendar**:
     * Dani s odrađenim treningom imaju točkicu.
     * Klik na dan prikazuje ispod kalendara popis treninga odrađenih taj dan (isti prikaz kao u listi).
     * Klik na trening otvara detalje tog treninga.
   * Gumb za **sortiranje / filter**:
     * Po tipu treninga (snaga, kardio, crossfit…)
     * Po datumu (uzlazno / silazno)
3. **Rasporedi** — Lista svih rasporeda.
   * Ako postoji samo jedan raspored, prikazuje se s naslovom (npr. “Moj raspored”).
   * Klik na raspored otvara popis treninga unutar njega.
   * Gore desno gumb **+** za dodavanje novog rasporeda.
   * Unutar otvorenog rasporeda:
     * Gore desno gumb **+** za dodavanje novog treninga ili rest dana.
     * Gore desno gumb **Postavke** rasporeda:
       * Trajanje (broj ciklusa ili "dok ga ne ugasim"). Ako je postavljen 1 ciklus, nakon odrađivanja svih treninga raspored postaje neaktivan (Započni više ne nudi treninge iz njega).
       * Podsjetnici: način rada (fiksni dani ili fleksibilno) i vrijeme, prema pravilima u odjeljku 6.
   * Unutar otvorenog treninga:
     * Gore desno gumb **+** za dodavanje nove vježbe ili superseta.
4. **Katalog vježbi** — Pregled, pretraga i dodavanje vježbi (predefinirane + custom).
   * Lista vježbi prikazuje samo nazive.
   * Gore je defaultni search bar.
   * Gore desno gumb za **filtere** (kategorije, mišićna skupina, dio tijela, oprema, custom/predefinirane).
   * Gore desno gumb **+** za dodavanje custom vježbe.
   * Klik na vježbu otvara detalje:
     * Naslov
     * Opis
     * Slika
     * Skupina mišića
     * Potrebna oprema
   * Mogućnost dodavanja vlastite slike za custom vježbe.
5. **Statistika** — Grafovi, 1RM, volumen, PRs, body measurements, heatmap.
   * Prikazuje se kao vertikalni popis kartica (jedna ispod druge).
   * Svaka kartica predstavlja jednu kategoriju (npr. graf napretka, 1RM, volumen, PR lista, body measurements, heatmap).

### Funkcije

1. **Brzi tajmer za odmor (Rest Timer):**
   * Automatsko pokretanje nakon označavanja serije.
   * Default 90 sekundi.
   * Korisnik može promijeniti za svaku vježbu ili pojedini set.
   * +10s / -10s tijekom aktivnog timera.
   * Zvučni i haptički signali (pravila u odjeljku 6, "Rest timer i notifikacije").
2. **Plate Calculator** (kartica na Dashboardu i unutar aktivnog treninga).  
   Korisnik unese ciljnu težinu, a app prikaže koje ploče treba staviti na šipku.  
   Podržava različite težine šipke (npr. 20 kg, 15 kg) i korisnikov skup dostupnih ploča.  
   Unutar treninga otvara se iz polja težine s već upisanom vrijednošću.  
   Na Dashboardu je cijela kartica dodirljiva i otvara kalkulator preko cijelog ekrana, gdje se ispod izračuna mogu uključiti i isključiti dostupne ploče i promijeniti težina šipke (iste postavke kao u Postavkama).
3. **Zamjena vježbi (Exercise Swap):** Uz očuvanje povijesti. Povijest se uvijek veže uz vježbu koja je stvarno odrađena, a ne uz onu iz predloška.
4. **Povijest i Napredak:**
   * Prethodni rezultati uvijek vidljivi u sučelju unosa.
   * Estimacija 1RM (Epley / Brzycki).
   * Tjedne tvrde serije po mišićnoj grupi (vidi "Tvrde serije").
   * Grafovi napretka (težina, volumen, PRs) — posebno optimizirani za veći ekran iPada.
5. **Gotovi programi i predlošci (Rasporedi):**
   * Osnovni full body (2 dana), Početnički full body A/B (3 dana), Full body A/B/C (3 dana), Upper / Lower (4 dana), Upper / Lower + PPL (5 dana), Push / Pull / Legs (6 dana).
   * Vježba u programu je obrazac kretanja s izvedbama po opremi (npr. potisak sa šipkom → s bučicama → sklekovi). Pri dodavanju se bira prva izvedba za opremu iz profila; izolacijska vježba bez opreme otpada.
   * Ponavljanja i pauze slijede iz cilja i iskustva: raspon ponavljanja (npr. 8–12, dvostruka progresija), za snagu glavne vježbe 3–6 ponavljanja. Početnik i opća kondicija rade seriju manje.
   * Preporuka iz profila (cilj, iskustvo, oprema, dani): oprema je tvrdi filtar, a dani, iskustvo i cilj daju bodove. Prikazuju se najbolji program i dvije alternative s razlogom. Podloga i izvori: ACSM 2026, Pelland i sur. 2026, Schoenfeld i sur. 2016, 2019 i 2021.
   * Dodani program dobiva fiksne dane podsjetnika prema broju dana tjedno (vrijeme podsjetnika postavlja korisnik).
   * Neograničeno kreiranje vlastitih rasporeda (na iPadu drag-and-drop ili multi-select za brže slaganje).
6. **Praćenje tijela:**
   * Mjerenja: visina, težina, opseg struka, opseg prsa, ruke i noge.
   * Težina i visina se mogu vući iz HealthKit.
   * Korisnik može ručno unijeti dodatna mjerenja.
   * Prikazuje se povijest i graf za svaku mjeru.
7. **Onboarding:**
   * Cilj (hipertrofija / snaga / rekompozicija / opća kondicija).
   * Jedinice (kg / lbs).
   * Visina i težina (opcionalno).
   * Povezivanje s Apple Health (odmah pitati da/ne).
   * Iskustvo (početnik / srednji / napredni) — opcionalno.
   * Dostupna oprema i broj dana tjedno — opcionalno.

---

## 4. Analitika i Napredak

* **1RM estimacija** i praćenje kroz vrijeme.
* **Volume tracking** po mišićnim grupama (tjedno/mjesečno).
* **Grafovi i vizualizacije:** Napredak težine, volumena, frekvencije.
* **Body measurements** s grafovima.
* **PR lista** s filterima i datumima.
* **Muscle heatmap** koji prikazuje prosjek tvrdih serija tjedno po mišiću u zadnjih 30 dana, 90 dana ili godinu dana, na fiksnoj skali s legendom: ispod 5, 5 do 9, 10 do 20 (zona za rast) i iznad 20 serija. Ispod mape su glavni mišići s manje od 5 serija tjedno, a dodir mišića pokazuje serije tjedno, treninge tjedno i zadnji trening.
* **Serije po mišiću tjedno:** prosjek zadnja 4 ili 12 tjedana, s označenom zonom 10 do 20 serija. Usporedba ovog i prošlog tjedna je u serijama.
* **Trend snage po mišiću:** medijan mjesečne promjene procjene 1RM glavnih vježbi mišića u zadnjih 8 tjedana.
* **Status vježbe:** napreduje, stoji, plato (stoji barem 4 tjedna), pada ili premalo podataka. Računa se iz Theil–Senovog nagiba logaritma procjene 1RM (ili ponavljanja za vlastitu težinu) u zadnjih 8 tjedana, od 4 izvođenja. Napredak mora biti veći od kolebanja vježbe, koje se od 6 izvođenja uči iz podataka (2 do 8 %).
* **Pregled zadnja 4 tjedna:** četiri dijela umjesto jedne ocjene: snaga (statusi vježbi), volumen (glavni mišići u zoni tvrdih serija prema cilju), redovitost (treninzi prema planu) i napor (udio serija s 0 do 3 ponavljanja u rezervi). Uz pregled ide prijedlog za dalje (lakši tjedan, manje dana, više ili manje serija, veća težina, zaboravljen mišić).
* **Prikaz statistike:** osnovni ili detaljni, besplatna postavka. Detaljni dodaje zbroj dobrih dijelova pregleda, sve prijedloge, raspodjelu napora i intenziteta serija, najtežu seriju po ponavljanjima, relativnu snagu, odmor između serija i ocjenu napora treninga (sRPE, Foster i sur. 2001) u sažetku.
* **Sažetak treninga:** tvrde serije, usporedba s prošlim izvođenjem istog predloška (tonaža, tvrde serije, trajanje), procjena 1RM po vježbi s promjenom prema prošlom izvođenju i tvrde serije mišića u tom tjednu.
* **Tvrde serije:** mjera volumena po mišiću za mapu i grafove. Broji se završena radna serija; serija s upisanim RPE-om ispod 6 (RIR 5 i više) ne broji se, a serija bez RPE-a broji se uvijek. Mišić kojem je vježba glavna dobiva cijelu seriju, a mišić koji pomaže pola. Vježbe s vlastitom težinom broje se jednako. Tonaža (kg × ponavljanja) ostaje za napredak pojedine vježbe i karticu tjednog volumena na Početnoj, jer nije usporediva između mišića različite veličine. Izvori: Schoenfeld i sur. 2017 (doza i odgovor), Pelland i sur. (frakcijsko brojanje pomoćnih serija), Robinson i sur. 2024 (blizina otkaza).

---

## 5. Podaci, Pouzdanost i Sinkronizacija

* **Offline-first:** Svi podaci se spremaju i čitaju lokalno (SwiftData).
* **Export / Import:**
  * Export u CSV i JSON.
  * Import iz CSV-a (vlastiti backup — format koji app i exportira).
  * **Import treninga iz druge aplikacije:** CSV s točkom-zarezom u kojem svaki trening počinje zaglavljem `"Naziv · Day N · Week N · Plan";"2026-11-02 4:27 pm";"53 min"`, a ispod su vježbe (`"1. Naziv · Oprema · 10 reps"`) s tablicama serija (`#;KG;REPS` ili `#;MINS`). Aplikacija sama prepozna format pri "Uvezi iz datoteke".
    * Prije uvoza prikazuje se pregled: broj novih i već uvezenih treninga, razdoblje, broj serija i kamo ide koja vježba (katalog, postojeća ili nova vlastita vježba).
    * Vježbe se povezuju s katalogom prema nazivu i opremi (`ForeignExerciseMatcher` u GymKitu). Vježba bez pravog para u katalogu postaje vlastita vježba; ako vlastita vježba istog naziva već postoji, koristi se ona.
    * Vrijednost s `+` ("+12.5") je vlastita težina + teret, a `-` prazna serija koja se ne uvozi. Datum je lokalno vrijeme uređaja.
    * Svaki trening dobiva stabilan UUID iz zaglavlja i datuma, pa ponovni uvoz iste ili novije datoteke dodaje samo nove treninge.
* **Opcionalni CloudKit sync:**  
  Sinkronizira se sve korisničko (treninzi, rasporedi, custom vježbe, mjerenja, postavke). Službeni katalog vježbi **ne** sinkronizira se (vidi odjeljak 1).  
  Automatski ako je uključen, ili ručno.  
  Podaci uvijek ostaju lokalno, čak i ako je sync isključen.  
  U slučaju konflikta: **last write wins** (zadnja promjena pobjeđuje) — najjednostavnije za MVP.
* **Backup strategija:** Lokalni backup + opcionalni iCloud.
* **Sve težine spremaju se u kilogramima.** Pretvorba u lbs radi se samo za prikaz i unos, kako promjena jedinica ne bi mijenjala podatke ni stvarala greške zaokruživanja. Unos u lbs pretvara se u kg s punom preciznošću.

### Tehnička ograničenja SwiftData + CloudKit
Ova pravila vrijede za sve modele koji se sinkroniziraju i moraju se poštovati od prvog dana, jer se kasnije teško mijenjaju:
* Svako svojstvo mora biti opcionalno ili imati zadanu vrijednost.
* Nisu dopuštena jedinstvena ograničenja (`@Attribute(.unique)`). Jedinstvenost se osigurava u kodu (UUID kao `id`, uklanjanje duplikata nakon synca).
* Sve relacije moraju biti opcionalne, a pravilo brisanja ne smije biti `deny`.
* Redoslijed elemenata (vježbe u treningu, serije) sprema se kao eksplicitno polje `orderIndex`, jer CloudKit ne čuva redoslijed relacija.
* Shema se nakon prvog izdanja smije samo proširivati (nova opcionalna polja i modeli). Brisanje ili preimenovanje polja zahtijeva novu verziju sheme i migraciju. Prije izdanja shema se mora objaviti u CloudKit produkcijsko okruženje.
* Watch ne koristi CloudKit za tijek aktivnog treninga (vidi "Sinkronizacija iPhone ↔ Watch").

---

## 6. Ekosustav i Integracije (iOS, iPadOS & Apple Watch)

### Planirani treninzi, rasporedi i notifikacije

Korisnik gradi planove na tri razine:

**Vježbe → Treninzi → Rasporedi**

```
┌─────────────────┐
│   RASPORED      │  (npr. "PPL 6 dana", "Full Body")
│  • Ime          │
│  • Opis         │
│  • Ciklusi      │
│  • Podsjetnici  │
└────────┬────────┘
         │ sadrži više
         ▼
┌─────────────────┐
│   TRENING       │  (npr. "Push", "Pull", "Legs", "Trčanje 5km")
│  • Ime          │
│  • Opis         │
│  • Vrsta        │  (snaga / kardio)
└────────┬────────┘
         │ sadrži više
         ▼
┌─────────────────┐
│   VJEŽBA        │  (predefinirana ili custom)
│  • Naziv        │
│  • Serije/reps  │
│  • Oprema...    │
└─────────────────┘
```

#### Pravila
* **Vježbe:** Predefinirane (iz kataloga) ili custom. Mogu se dodati:
  * unaprijed u katalogu,
  * prilikom kreiranja treninga/rasporeda,
  * ili tijekom samog treninga.
* **Trening:** Ima ime i opcionalni opis. Sastoji se od proizvoljnog broja vježbi.
  * **Notes:** Korisnik može dodati bilješke na razini cijelog treninga.  
    Unose se tijekom treninga ili nakon. Prikazuju se u sažetku i u povijesti. Nema ograničenja duljine.
* **Raspored:** Ima ime i opcionalni opis. Sastoji se od proizvoljnog broja treninga.
  * **Osnova je redoslijed, ne kalendar.** Raspored je niz treninga (npr. Push → Pull → Legs → Odmor). "Započni" uvijek nudi **sljedeći neodrađeni trening u nizu**, bez obzira na datum. Ciklus završava kad su odrađeni (ili izričito preskočeni) svi treninzi u nizu, i tada počinje sljedeći ciklus.
  * **Propušteni dan:** ništa se ne pomiče niti preskače automatski. Ako je korisnik u utorak trebao raditi Pull i nije došao, u srijedu je i dalje na redu Pull. Korisnik može ručno preskočiti trening (privremena izmjena, vidi niže).
  * **Ciklusi:** Korisnik može definirati koliko ciklusa raspored traje (fiksni broj) ili da traje dok ga ručno ne ugasi.
  * **Rest dani:** Opcionalni elementi niza. Služe za podsjetnike u fleksibilnom načinu i za prikaz plana. "Započni" ih preskače.
  * **Podsjetnici (kalendar služi samo za njih):** korisnik bira jedan od dva načina za cijeli raspored:
    * **Fiksni dani:** odabere dane u tjednu i vrijeme (npr. pon, sri, pet u 17:00). Tih dana stiže "Danas je na redu [sljedeći trening u nizu]". Dani nisu vezani uz pojedini trening, nego samo kažu kad se trenira.
    * **Fleksibilno:** podsjetnik stiže X dana nakon zadnjeg odrađenog treninga (zadano 1, s preskakanjem rest dana iz niza) u odabrano vrijeme.
  * Podsjetnik se ne šalje ako je taj dan već odrađen trening iz tog rasporeda.

#### Privremene izmjene po ciklusu (ne utječu na budućnost)
* Za svaki pojedinačni ciklus/dan korisnik može:
  * **Izbaciti cijeli trening** iz tog ciklusa (npr. preskočiti dan).
  * **Izbaciti vježbu** iz treninga samo za taj dan.
  * **Privremeno zamijeniti vježbu** (npr. sprava zauzeta → odrađuje alternativu).
* Sve te izmjene se bilježe samo za taj konkretni trening/dan.
* Originalni raspored i sastav treninga ostaju nepromijenjeni za buduće cikluse.
* U povijesti se prikazuje **samo ono što je odrađeno** (nema oznaka “zamijenjeno” ili “preskočeno”).
* Izbačenu vježbu ili preskočeni trening **moguće je vratiti** dok taj trening nije završen (traka "Poništi" odmah nakon radnje i popis "Uklonjene vježbe" u izborniku treninga).

#### Notifikacije i pokretanje
* Aplikacija šalje lokalne notifikacije kada dođe red na planirani trening (ako su uključene).
* **Za trčanje / kardio:** aplikacija preko **WorkoutKit `WorkoutScheduler`** unaprijed zakazuje plan treninga (npr. intervali, cilj udaljenosti) u native Apple Workouts aplikaciju na Watchu, za dan i vrijeme podsjetnika.
  * Na dan treninga plan se pojavi u Workouts aplikaciji na Watchu, a korisnik ga **pokreće sam**. iPhone aplikacija ne može izravno pokrenuti Workouts aplikaciju na Watchu.
  * Klik na podsjetnik na iPhoneu otvara našu aplikaciju s pregledom plana i uputom "Pokreni na satu u aplikaciji Workout". Ako plan nije zakazan, nudi gumb za zakazivanje.
  * Native app vodi cijeli trening.
  * Nakon završetka aplikacija pročita `HKWorkout` iz HealthKit i uveze podatke.
  * **Prije početka razvoja ovog dijela** treba prototipom potvrditi ponašanje `WorkoutScheduler` API-ja (ograničenja broja zakazanih planova, dozvole, ponašanje bez Watcha) na aktualnoj verziji watchOS-a.
* **Za snagu:** Notifikacija otvara vlastitu Watch / iPhone aplikaciju za logging serija.

### Ponašanje notifikacija tijekom aktivnog treninga
* Tijekom aktivnog treninga (na **Apple Watchu** ili na **iPhoneu**) aplikacija **ne šalje svoje podsjetnike** (rasporedi, motivacijske poruke). Već zakazani podsjetnici za taj dan se otkazuju.
* Aplikacija ne može utišati notifikacije drugih aplikacija. U onboardingu i postavkama nudi se uputa za postavljanje sustavskog Focus načina (npr. "Fitness"), koji korisnik može automatski uključiti pri početku treninga preko Shortcuts.

### Rest timer i notifikacije
Jedina notifikacija koju aplikacija šalje tijekom treninga je **kraj odmora**, i to samo kad je potrebna:
* **Aplikacija otvorena na iPhoneu:** zvuk i haptika iz same aplikacije, bez notifikacije.
* **iPhone zaključan ili aplikacija u pozadini, trening na iPhoneu:** pri pokretanju timera zakazuje se lokalna notifikacija za trenutak isteka (zvuk ako je uključen u Postavkama, razina "time-sensitive", za koju aplikacija ima entitlement `com.apple.developer.usernotifications.time-sensitive`, pa obavijest prolazi kroz Fokus). Obavijest ima svoj prekidač u Postavkama, odvojen od podsjetnika rasporeda. Ako korisnik promijeni timer (+10/−10) ili ga prekine, notifikacija se premješta ili otkazuje.
* **Trening se vodi na Watchu:** haptika na satu, a na iPhoneu nema notifikacije kraja odmora (samo Live Activity).
* Aplikacija ne drži audio sesiju aktivnom u pozadini samo radi timera.
* Na iPhoneu može biti aktivna **Live Activity** koja prikazuje:
  * Na vrhu naziv treninga i trajanje od početka
  * Preostalo vrijeme rest timera (traka + odbrojavanje u sekundama u realnom vremenu). U sažetom Dynamic Islandu lijevo je krug koji se prazni, a desno odbrojavanje u naglasnoj boji.
  * Trenutnu / sljedeću vježbu
  * Broj serija
  * Težinu i ponavljanja (ili trajanje i udaljenost) sljedeće serije, s gumbima − i + za promjenu (isti koraci kao Digital Crown na satu)
  * Kvačicu za potvrdu sljedeće serije
* Live Activity ne iskače s upozorenjem na kraju odmora: ažuriranje s `AlertConfiguration` mora se poslati u trenutku isteka, a aplikacija je tada u pozadini suspendirana i nema poslužitelja za push. Kraj odmora zato javlja obična notifikacija.
* Live Activity je tiha (bez zvuka i notifikacijskih bannera). Timer u njoj prikazuje se sustavskim odbrojavanjem (`Text(timerInterval:)`), pa ne treba stalna ažuriranja.
* Dodir na Live Activity (izvan gumba) otvara aplikaciju izravno na puni ekran aktivnog treninga.
* Gasi se automatski kad trening završi.

### Apple Health (HealthKit)
* Spremanje treninga (`HKWorkout`) — zatvaranje Activity Rings (za vlastite sesije).
* Čitanje završenih treninga iz native Workouts app (posebno trčanje) radi uvoza u povijest aplikacije.
* Čitanje tjelesne mase, visine i drugih biometrijskih podataka.
* **Kalorije:** Koristi se isključivo Appleov proračun (`activeEnergyBurned` + `basalEnergyBurned` iz HealthKit). Ne radi se vlastiti model.
  * Kad se trening vodi na Watchu (`HKWorkoutSession`), kalorije postoje i prikazuju se u sažetku i povijesti.
  * Kad se trening snage bilježi samo na iPhoneu bez Watcha, HealthKit nema pouzdan podatak, pa se **polje kalorija ne prikazuje** (ni u sažetku ni u povijesti). Ne prikazuje se "0" ni procjena.
* **Dozvole:** traže se samo za tipove podataka koji se stvarno koriste, uz jasno objašnjenje u `NSHealthShareUsageDescription` i `NSHealthUpdateUsageDescription`. Aplikacija mora raditi i kad korisnik odbije pristup.

### Apple Watch companion aplikacija (watchOS) — obavezna od starta
* Kontinuirano mjerenje pulsa.
* Označavanje serija i pokretanje/zaustavljanje rest timera sa zapešća.
* Haptička vibracija po isteku tajmera.
* Osnovni pregled aktivnog treninga i prethodnih serija.
* Sinkronizacija s iPhone aplikacijom u realnom vremenu (vidi niže).
* Watch aplikacija može voditi trening i kad iPhone nije u blizini. Podaci se spremaju na satu i šalju na iPhone kad se veza uspostavi.
* **Trening pokrenut na iPhoneu pokreće i sat** (`HKHealthStore.startWatchApp`), ako je sat uparen i u Postavkama je uključeno "Pokreni trening i na satu" (zadano uključeno). Trening i dalje vodi iPhone, a sat za njega drži `HKWorkoutSession`: mjeri puls i kalorije, ostaje otvoren dok je zapešće spušteno i vibrira na kraju odmora. Na kraju sat sprema trening u Zdravlje i šalje iPhoneu UUID, kalorije i puls (`WorkoutCommand.healthRecorded`), a iPhone tada svoj zapis u Zdravlje ne radi (`Session.healthRecordedByWatch`). Kraj odmora tada javlja sat, pa iPhone ne zakazuje obavijest. Ako sat ne pokrene sesiju (npr. nema dozvole za Zdravlje), iPhone sprema trening i javlja kraj odmora kao i prije.
* **Za kardio/trčanje:** planovi zakazani preko WorkoutKit pojavljuju se u native Workouts aplikaciji, gdje ih korisnik pokreće.
* **Complications:** Prikaz sljedećeg treninga. Podržano na svim Watch face-ovima gdje je moguće.

#### Sinkronizacija iPhone ↔ Watch
* **Tijekom aktivnog treninga koristi se WatchConnectivity**, a ne CloudKit. CloudKit je spor i nema zajamčeno vrijeme isporuke.
  * `sendMessage` za trenutne događaje dok su oba uređaja dostupna (serija kompletirana, timer pokrenut, promjena težine).
  * `transferUserInfo` za događaje koji moraju stići i kad druga strana trenutno nije dostupna (zajamčena isporuka redom).
  * `updateApplicationContext` za zadnje stanje (npr. sljedeći trening i smart defaults za prikaz na satu).
* Svaki događaj ima UUID i vremensku oznaku, pa se duplikati prepoznaju, a sukob se rješava zadnjom promjenom.
* **Jedan uređaj vodi trening.** Ako je trening pokrenut na satu, sat je izvor istine, a iPhone prikazuje i može upisivati promjene koje se šalju na sat (i obrnuto).
* Nakon završetka treninga uređaj koji ga je vodio sprema konačni zapis u lokalnu bazu, a dalje (iPad, drugi uređaji) ide preko CloudKita.
* iPad nema Watch vezu i aktivni trening na Watchu ne prati uživo.

#### Watch ekrani
1. **Početni ekran**
   * Sljedeći trening (naziv + dan)
   * Gumb **Započni**
2. **Aktivni trening**
   * Trenutna vježba
   * Trenutna serija (težina × reps)
   * Veliki gumb za kompletiranje serije
   * Rest timer (veliki broj + haptic)
   * Gumb za sljedeću / prethodnu vježbu
3. **Rest timer (kad je aktivan)**
   * Veliki odbrojavač
   * +10 / -10
   * Haptic na kraju
4. **Sažetak (nakon završetka)**
   * Trajanje
   * Broj serija
   * Gumb Zatvori

### iPad optimizacija
* Detaljni grafovi i statistike u split-view ili multi-column layoutu.
* Udobno slaganje i uređivanje treninga/rutina na velikom ekranu.
* Podrška za Stage Manager i multi-window gdje ima smisla.

---

## 7. Tehnički stog i Arhitektura

* **Platforma:** iOS (iPhone) + iPadOS + watchOS — svi od prvog releasea.
* **Jezik i Okvir:** Swift + SwiftUI (s adaptivnim layoutima, size classes, NavigationSplitView za iPad).
* **Lokalna baza:** SwiftData. Dvije konfiguracije: korisnička baza (sinkronizira se preko CloudKita) i baza kataloga (samo za čitanje, ne sinkronizira se).
* **Minimalna verzija sustava:** iOS / iPadOS 18 i watchOS 11 ili novije (SwiftData je na iOS-u 17 imao puno grešaka, osobito s CloudKitom). Pred izlazak (2027.) treba provjeriti udio korisnika na starijim verzijama i po potrebi podići minimum na aktualnu verziju minus jedna.
* **Arhitektura:** Offline-first, modularna (feature-based ili clean architecture). Podrška za multi-device putem opcionalnog CloudKit synca, a za iPhone ↔ Watch tijekom treninga putem WatchConnectivity.
* **Bez vlastitog servera:** nema backend, nema korisničkih računa, nema analitike trećih strana.
* **Jedinice:** Podrška za kg/lbs. Spremanje uvijek u kg, pretvorba samo za prikaz i unos.
* **Lokalizacija:** Hrvatski + Engleski od početka (sučelje kroz String Catalog; katalog vježbi prema postupku iz odjeljka 1).
* **Pristupačnost:** Podrška za Dynamic Type i osnovne VoiceOver oznake.
* **Responsive dizajn:** Svi ključni ekrani (logging, analitika, rutine, katalog) moraju imati namjenski iPhone i iPad layout od starta.
* **Praćenje rušenja i performansi:** MetricKit i Xcode Organizer (bez SDK-ova trećih strana, kako bi privatnosni opis u App Storeu ostao jednostavan).
* **Testovi:**
  * Unit testovi za logiku koja se ne smije pokvariti: smart defaults, PR detekcija, volumen po vrsti serije, 1RM, pretvorba jedinica, napredovanje kroz raspored i cikluse, privremene izmjene, import/export (CSV koji se exportira mora se moći importati bez gubitka).
  * Testovi migracije sheme prije svakog izdanja koje mijenja model.
  * UI test osnovnog tijeka: Započni → kompletiraj serije → Završi → sažetak → povijest.
* **Privatnost:**
  * Pravila privatnosti (javni URL) obavezna su zbog HealthKita i App Storea. Navode da su podaci samo na uređaju i u korisnikovom iCloudu, da se ne dijele i da nema praćenja.
  * Privacy Manifest (`PrivacyInfo.xcprivacy`) i App Store privatnosni opis ("Data Not Collected", ako ostane bez analitike).
  * HealthKit podaci se ne smiju koristiti za oglašavanje ni slati trećima.

---

## 8. Model podataka

Ključno pravilo: **predložak** (ono što je planirano) i **odrađeni trening** (ono što je stvarno izvedeno) su odvojeni modeli. Odrađeni trening kopira potrebne podatke iz predloška pri pokretanju i nakon toga je neovisan. Zato privremene izmjene, zamjene vježbi i kasnije promjene predloška nikad ne mijenjaju povijest.

### Katalog (zasebna baza, ne sinkronizira se)
* **CatalogExercise:** `catalogId` (MoveKit slug), nazivi po jeziku, upute i česte greške po jeziku (iz privatnog dodatka), kategorija, primarni i sekundarni mišići, oprema, razina, mehanika (isolation/compound), tip pokreta (push/pull/legs), vrsta unosa (vidi tablicu u odjeljku 2), klip i poster (putanje u MoveKit dodatku).

### Korisnička baza (sinkronizira se)
* **CustomExercise:** `id`, naziv, opis, kategorija, mišići, oprema, vrsta unosa, slika (opcionalno, kao `externalStorage`), `isArchived`.
* **ExerciseRef** (ugrađena vrijednost, ne zaseban model): `catalogId` ili `customExerciseId`, plus spremljeni naziv za prikaz ako vježba nestane.

**Planiranje**
* **Schedule** (raspored): `id`, naziv, opis, broj ciklusa (ili neograničeno), način podsjetnika (fiksni dani / fleksibilno), dani u tjednu, vrijeme podsjetnika, razmak za fleksibilni podsjetnik u danima (zadano 1), `isActive`, trenutni ciklus i pozicija u nizu. Pozicija je indeks sljedeće stavke; rest dani i preskočeni treninzi se prelaze, ciklus završava nakon zadnjeg treninga (rest dani na kraju niza se ne čekaju), a nakon zadnjeg ciklusa raspored postaje neaktivan. Raspored napreduje samo kad je odrađen upravo njegov sljedeći trening.
* **ScheduleItem:** `scheduleId`, `orderIndex`, vrsta (trening ili rest dan), `workoutTemplateId`.
* **WorkoutTemplate** (trening/predložak): `id`, naziv, opis, vrsta (snaga / kardio).
* **TemplateExercise:** `templateId`, `orderIndex`, `ExerciseRef`, vrsta unosa, `supersetGroupId` (opcionalno; vježbe s istom vrijednošću čine superset), pauza u sekundama (opcionalno, inače zadana), napomena.
* **TemplateSet:** `templateExerciseId`, `orderIndex`, vrsta (radna / warm-up), ciljana težina i ponavljanja (opcionalno).
* **CycleOverride** (privremena izmjena): `scheduleId`, broj ciklusa, `scheduleItemId`, vrsta izmjene (preskoči trening / izbaci vježbu / zamijeni vježbu), ciljna vježba i zamjena (s vrstom unosa). Izmjena vrijedi samo za taj ciklus; preskakanje se poništava dok raspored ne prođe tu stavku.

**Izvedba**
* **Session** (odrađeni trening): `id`, `templateId` i `scheduleId` (opcionalno, samo za praćenje odakle je pokrenut), naziv u trenutku pokretanja, vrsta, početak, kraj, stanje (u tijeku / završen / odbačen), uređaj koji ga vodi, bilješke, kalorije (opcionalno, iz HealthKita), `healthKitWorkoutId` (opcionalno), uvezen iz Workouts aplikacije (da/ne), udaljenost i prosječni puls za kardio.
* **SessionExercise:** `sessionId`, `orderIndex`, `ExerciseRef` (stvarno odrađena vježba), `supersetGroupId`, `isRemoved` (za poništavanje unutar treninga).
* **SetLog:** `sessionExerciseId`, `orderIndex`, vrsta (radna / warm-up), težina u kg, ponavljanja, dodatna težina ili pomoć u kg, trajanje u sekundama, udaljenost u metrima, RPE (spremljen kao broj od 1 do 10), `completedAt`.

**Ostalo**
* **PersonalRecord:** izvedeni podatak, računa se iz `SetLog` zapisa i može se u svakom trenutku ponovno izračunati. Sprema se u predmemoriju radi brzine, ali nije izvor istine.
* **BodyMeasurement:** `id`, vrsta (težina, visina, struk, prsa, ruka, noga, custom), vrijednost u metričkim jedinicama, datum, izvor (ručno / HealthKit).
* **DashboardCard:** vrsta kartice, `orderIndex`, postavke kartice.
* **UserSettings:** jedan zapis: jedinice, zadana pauza, tema, accent boja, tema i boja Live Activityja, RPE/RIR, PR postavke, zvuk kraja odmora, dostupne ploče i težine šipke.

### Pravila
* Svi identifikatori su UUID. Svi modeli poštuju ograničenja iz odjeljka 5 (opcionalna polja, bez `unique`, `orderIndex` za redoslijed).
* Smart defaults čitaju se iz zadnjeg završenog `Session` zapisa koji sadrži istu vježbu, po poziciji serije i odvojeno za warm-up i radne serije.
* Brisanje predloška ili rasporeda ne briše odrađene treninge.

---

## 9. Prioriteti razvoja (MVP vs. Kasnije)

### MVP (preporučeni prvi release)
* Katalog vježbi (MoveKit) s animacijama i uputama.
* Snaga logging s inline poviješću, smart defaults i rest timerom (optimiziran za iPhone).
* Rasporedi (gotovi + vlastiti) — uključujući udobno slaganje na iPadu.
* Plate Calculator (na Dashboardu i unutar treninga).
* Basic PR-ovi i osnovni grafovi/statistike (posebno dobro na iPadu).
* Body measurements.
* **Apple Watch aplikacija** (serije + rest timer + osnovni pregled).
* **Watch complications** (npr. sljedeći trening, aktivni rest timer).
* **iPad optimizacija** (adaptivni layout, multi-column za analitiku i planiranje).
* Planirani treninzi + lokalne notifikacije (s rasporedima, ciklusima i podsjetnicima u dva načina).
* Osnovni WorkoutKit flow za trčanje (zakazivanje plana u Workout aplikaciju na satu + naknadni uvoz podataka).
* Live Activity na iPhoneu tijekom treninga na Watchu (tiha, bez zvuka i bannera).
* RPE i supersets.
* Notes na razini treninga.
* CloudKit sync (opcionalno) i WatchConnectivity sync tijekom treninga.
* Oporavak prekinutog treninga.
* Vrste serija (težina, vlastita težina, dodatni teret, potpomognuto, trajanje).
* HR + EN lokalizacija sučelja i odabranog seta vježbi.
* Pravila privatnosti, Privacy Manifest i osnovni testovi.
* Export u CSV/JSON.
* Onboarding.

### Kasnije (post-MVP)
* Napredna analitika i grafovi.
* Warm-up calculator.
* Import iz datoteka drugih aplikacija (osim CSV formata iz odjeljka 5, koji je napravljen).
* Hibridni WOD / CrossFit formati u potpunosti.
* Program generator / AI preporuke.
* Dijeljenje rasporeda.
* WidgetKit widgeti na početnom zaslonu.

---

## 10. Dodatne napomene

* Fokus na **brzinu logiranja** (cilj: 1–2 tapa po seriji) na iPhoneu, uz bogatiji pregled na iPadu.
* **Opće smjernice dizajna i performansi:**
  * Aplikacija mora biti **brza** — svi ključni ekrani (posebno logging) otvaraju se trenutno, bez lag-a.
  * **Jednostavnost** — minimalan broj koraka za svaku akciju, jasna hijerarhija.
  * **Čist dizajn** — minimalistički UI, puno bijelog prostora, bez nepotrebnih elemenata, jak fokus na sadržaj.
  * **Native SwiftUI komponente** — korištenje sistemskih tabova (`TabView`), naslova, gumba, listi, navigacije (`NavigationStack`/`NavigationSplitView`), tipografije i drugih standardnih SwiftUI elemenata. Izgled i ponašanje moraju biti u skladu s Apple Human Interface Guidelines.
  * Dark mode kao standard.
* Jasna atribucija u *O aplikaciji* sekciji (čak i za public domain podatke).
* Monetizacija: Free s ograničenjima ili freemium (npr. napredna analitika / neograničene rutine kao premium) — definirati kasnije.
* Multi-device: iPhone + iPad + Apple Watch moraju raditi zajedno od prvog dana (lokalno, s opcionalnim CloudKit syncem).

---

## Popis izmjena u odnosu na v2

1. Uklonjena prijava (Apple, Google, e-mail). Sinkronizacija ide preko iClouda bez računa, a "brisanje računa" postalo je "Obriši sve podatke".
2. Dodana sinkronizacija iPhone ↔ Watch preko WatchConnectivity tijekom treninga. CloudKit služi samo za pohranu i ostale uređaje.
3. Razdvojena pravila: aplikacija utišava samo svoje podsjetnike, a kraj odmora javlja lokalnom notifikacijom kad je mobitel zaključan. Dodana uputa za Focus način.
4. Kalorije se prikazuju samo kad ih HealthKit ima, inače se polje skriva. Uklonjen ručni unos kalorija za kardio.
5. WorkoutKit: plan se zakazuje preko `WorkoutScheduler`, a korisnik ga pokreće na satu. Dodan zadatak provjere prototipom.
6. Rasporedi: redoslijed je osnova, propušteni dan ništa ne pomiče, kalendar služi samo za podsjetnike, a podsjetnici imaju dva jasno definirana načina.
7. Plate Calculator dostupan i unutar treninga.
8. RPE ograničen na 1–10 u koracima od 0,5, uz opciju RIR.
9. Izbačenu vježbu ili preskočeni trening moguće je vratiti do kraja treninga.
10. Pauza nakon superseta uzima zadanu vrijednost iz Postavki.
11. Sređena numeracija odjeljka 3 (tabovi i funkcije odvojeni).
12. Dodan model podataka (odjeljak 8) s odvojenim predloškom i odrađenim treningom. Težina se uvijek sprema u kg.
13. Dodane vrste serija (vlastita težina, dodatni teret, potpomognuto, trajanje) i pravila volumena.
14. Warm-up serije izričito isključene iz PR-ova, volumena i 1RM.
15. Dodan oporavak prekinutog treninga.
16. Dodana ograničenja SwiftData + CloudKit i zasebna baza kataloga koja se ne sinkronizira.
17. Minimalna verzija podignuta na iOS 18 / watchOS 11.
18. Dodan plan prijevoda kataloga i mapiranja kategorija.
19. Dodani privatnost, praćenje rušenja i testovi. Pojašnjeno da su Dashboard "widgeti" kartice u aplikaciji.

---

*Dokument ažuriran: studeni 2026 (v3). Obuhvaća originalne dobre prakse i poboljšanja fokusirana na korisničko iskustvo, pouzdanost podataka i konkurentnost.*
