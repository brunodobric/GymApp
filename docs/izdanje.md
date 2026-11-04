# Beta i izdanje (faza 14)

Redoslijed: priprema u App Store Connectu, interni TestFlight, javni TestFlight s nekoliko korisnika iz teretane, ispravci, App Store materijali, slanje na review. Koraci su na Brunovom Macu, u App Store Connectu i na uređajima; kod i skripte su u repozitoriju.

## 1. Jednokratna priprema

- [ ] Plaćeni Apple Developer Program (Personal Team ne može na TestFlight ni u App Store). U `Config/Local.xcconfig` samo `DEVELOPMENT_TEAM`, bez redaka `GYMAPP_*`.
- [ ] CloudKit shema objavljena u Production (`docs/sinkronizacija.md`, "Objava sheme u produkciju"). Bez toga sinkronizacija u TestFlight buildu ne radi.
- [ ] GitHub Pages: Settings > Pages > Source: **GitHub Actions**, pa provjeriti da se otvaraju https://brunodobric.github.io/GymApp/privacy/ i `/podrska/`.
- [ ] Kontakt u pravilima privatnosti i na stranici podrške radi za posjetitelje (javni repozitorij ili e-mail adresa).
- [ ] App Store Connect > Apps > **+** > New App: platforme iOS (watchOS ide uz iOS aplikaciju), naziv iz `AppStore/metadata/hr/name.txt`, primarni jezik hrvatski, Bundle ID `com.brunodobric.gymapp`, SKU `apollo-ios`.
- [ ] App Information i Pricing prema `AppStore/README.md` (kategorija, cijena, dobna oznaka, App Privacy).

## 2. Build za TestFlight

```sh
scripts/testflight.sh
```

Skripta odbija necommitane promjene i Personal Team postavke, arhivira Release build (iPhone, iPad i sat zajedno) s brojem builda jednakim broju commitova i šalje ga u App Store Connect. Verzija je `MARKETING_VERSION` iz `project.yml` (1.0.0). Ručna alternativa: Xcode > Product > Archive > Distribute App > App Store Connect.

Nakon obrade (10 do 30 minuta) build je u App Store Connect > TestFlight. Export Compliance se ne pita jer je `ITSAppUsesNonExemptEncryption` u Info.plist.

## 3. Interni test

- [ ] TestFlight > Internal Testing: grupa s Brunom. Build stiže odmah, bez reviewa.
- [ ] Na svom iPhoneu, iPadu i satu proći ručne provjere: `docs/sinkronizacija.md` (provjera na uređajima), `docs/DIZAJN.md` (pristupačnost) i osnovni tijek: onboarding, trening s predloškom na iPhoneu, trening sa sata, Live Activity, sažetak, povijest, statistika, izvoz i uvoz.
- [ ] Izmjeriti performanse prema `docs/performanse.md` i upisati rezultate.

## 4. Javni TestFlight (korisnici iz teretane)

1. TestFlight > External Testing > **+**: grupa "Teretana". Dodati build.
2. **Test Information** (obavezno za vanjske testere): opis bete, e-mail za povratne informacije, Privacy Policy URL, i "What to Test" (ispod). Prvi build za vanjske testere ide na Beta App Review (obično dan-dva); sljedeći buildovi iste verzije uglavnom prolaze odmah.
3. **Public Link** uključiti, s ograničenjem na 10 do 20 testera. Link poslati ljudima iz teretane uz kratku poruku: instaliraju TestFlight, otvore link, a grešku prijave tako da naprave snimku zaslona i dodirnu Share Beta Feedback (ili u TestFlightu: Apollo > Send Beta Feedback).

**What to Test (hr):**

> Hvala što testiraš Apollo! Bilježi svoje stvarne treninge barem dva tjedna. Najviše nas zanima: je li unos serija brz tijekom treninga, slažu li se prethodni rezultati i prijedlozi težine, radi li tajmer odmora i obavijest kad je mobitel zaključan, te ako imaš Apple Watch, trening sa sata. Grešku prijavi snimkom zaslona i opisom koraka. Ako aplikacija padne, TestFlight će ponuditi da pošalješ izvještaj.

**What to Test (en):**

> Thanks for testing Apollo! Please log your real workouts for at least two weeks. We are most interested in whether logging sets is quick during a workout, whether previous results and suggested weights look right, whether the rest timer and its notification work with a locked phone, and, if you have an Apple Watch, training from the watch. Report a bug with a screenshot and the steps. If the app crashes, TestFlight will offer to send a report.

## 5. Greške iz bete

- Povratne informacije i rušenja: App Store Connect > TestFlight > Feedback i Crashes, te Xcode > Window > Organizer > Crashes (simbolizirani stack trace).
- Svaka greška postaje GitHub issue predloškom **Greška** (`.github/ISSUE_TEMPLATE/greska.yml`), s težinom. Ispravak ide kroz granu i PR kao i do sada, s testom u GymKitu gdje god je greška u logici.
- Novi build nakon ispravaka: `scripts/testflight.sh` (broj builda raste sam). Testerima se u "What to Test" kratko napiše što je ispravljeno.
- Beta traje dok dva tjedna zaredom nema nove greške težine "Blokira izdanje".

## 6. Prije slanja na review

- [ ] Nema otvorenih grešaka "Blokira izdanje".
- [ ] Performanse u ciljevima iz `docs/performanse.md` na najstarijem dostupnom iPhoneu.
- [ ] Snimke zaslona: `scripts/snimke-zaslona.sh` za iPhone i iPad, ručno za sat (`AppStore/README.md`), na oba jezika, pregledane.
- [ ] Tekstovi iz `AppStore/metadata/` upisani za hrvatski i engleski (CI provjerava duljine).
- [ ] App Review Information: napomena iz `AppStore/review_notes.txt`, kontakt podaci, "Sign-in required" isključen.
- [ ] Verzija i build: odabrati zadnji TestFlight build u verziji 1.0.0.
- [ ] Version Release: **Manually release this version**, da izdanje ide kad je Bruno spreman.

## 7. Slanje i odgovor reviewa

1. Add for Review > Submit. Review obično traje 1 do 3 dana.
2. **Odbijanje:** razlog stiže u App Store Connect > Resolution Center. Najčešći razlozi za ovakvu aplikaciju i odgovor:
   - *2.1 (nepotpuna aplikacija ili nejasan tijek):* dopuniti `review_notes.txt` koracima i odgovoriti u Resolution Centeru.
   - *5.1.1 / 5.1.3 (HealthKit i privatnost):* aplikacija radi bez Zdravlja, podaci iz Zdravlja ne idu u iCloud; odgovor se temelji na napomeni za HealthKit iz `docs/PRAVNO_I_PRIVATNOST.md`.
   - *Metadata (snimke ili opis):* ispraviti u App Store Connectu i ponovno poslati bez novog builda.
3. **Odobreno:** Release This Version. Nakon izdanja: tag `v1.0.0` na commitu builda (`git tag v1.0.0 <commit> && git push origin v1.0.0`), a shema podataka se od sada samo proširuje (`CLAUDE.md`).

## Nakon izdanja

- `MARKETING_VERSION` u `project.yml` se diže za svako novo izdanje (1.0.1 za ispravke, 1.1.0 za nove funkcije), a `AppStore/metadata/<jezik>/release_notes.txt` opisuje promjene.
- Promotivni tekst (`promotional_text.txt`) može se mijenjati bez nove verzije.
