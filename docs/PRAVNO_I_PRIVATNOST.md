# Pravo, privatnost i sigurnost

Pregled pravila koja se odnose na GymApp, prema checklistu za male aplikacije (skill *app-sigurnost-i-pravo*). **Ovo nije pravni savjet.** Prije izdanja, a osobito prije uvođenja pretplata, preporučuje se provjera kod odvjetnika za tech i privatnost.

GymApp je u dobrom položaju jer nema vlastiti server, korisničke račune, analitiku ni SDK-ove trećih strana. Većina rizika s popisa zato ne postoji. Ono što ostaje:

## Vrijedi od prvog izdanja

| Područje | Što GymApp radi | Status |
|---|---|---|
| **Privacy policy** | `site/privacy/` (hrvatski) i `site/privacy/en/` (engleski), objavljuje ih `.github/workflows/pages.yml` na https://brunodobric.github.io/GymApp/privacy/. Aplikacija ih otvara iz Postavke > O aplikaciji na jeziku sučelja. Navodi da su podaci samo na uređaju i u korisnikovom iCloudu, da HealthKit podaci ne idu nikome i ne koriste se za oglase, da nema praćenja ni analitike, i kako radi MetricKit. Mora točno odgovarati ponašanju aplikacije: svaka promjena u radu s podacima mijenja i ovaj tekst i datum. | Faza 13 (gotovo) |
| **App Store privacy label** | "Data Not Collected", dok god nema analitike ni servera. Odgovori za App Store Connect su ispod. | Faza 13 (gotovo) |
| **Privacy Manifest** | `PrivacyInfo.xcprivacy` u sva četiri targeta. Bez praćenja i bez prikupljenih podataka. UserDefaults: `CA92.1` (aplikacija i sat), `1C8F.1` (App Group između satne aplikacije i complicationsa). Svaki novi API s obaveznim razlogom (datumi datoteka, slobodan prostor, vrijeme od pokretanja sustava) traži upis razloga. | Faza 13 (gotovo) |
| **HealthKit pravila** | Dozvole samo za korištene tipove, s jasnim objašnjenjem: zapis treninga; čitanje treninga, aktivnih kalorija, udaljenosti (hodanje i trčanje, bicikl, plivanje), pulsa, težine i visine. Dozvola se traži tek kad korisnik u onboardingu ili Postavkama odabere povezivanje. Podaci se ne šalju trećima. Aplikacija radi i bez dozvole. | Faza 7 (gotovo) |
| **HealthKit podaci i iCloud** | Pravilo App Storea 5.1.3 (ii) zabranjuje spremanje osobnih zdravstvenih podataka u iCloud. Odlučeno: uvezeni treninzi, mjerenja iz Zdravlja te kalorije i puls treninga spremaju se u zasebnu lokalnu bazu (konfiguracija `HealthLocal`, bez CloudKita). Svaki uređaj ih sam čita iz Zdravlja. Korisnička baza koja se sinkronizira nema zdravstvenih vrijednosti, a zapisi koji su u nju dospjeli (starije verzije, uvoz kopije) premještaju se u lokalnu bazu. | Faza 12 (gotovo) |
| **GDPR (EU, uključujući Hrvatsku)** | Pravo na pristup i prenosivost pokriva export u CSV i JSON. Pravo na brisanje pokriva "Obriši sve podatke" (lokalno i iCloud). Minimalni podaci: bez imena, e-maila i lokacije. Prijenos podataka izvan EU ne radi aplikacija nego Apple (iCloud), što treba navesti u pravilima privatnosti. | Faze 6 i 12 |
| **Vanjski resursi** | Fontovi su sistemski, slike vježbi u bundleu. Aplikacija se ne spaja ni na kakav vanjski server osim Appleovih servisa. Ne smije se dodati Google Fonts, embed ni CDN. | Pravilo za cijeli projekt |
| **Session replay i tracking** | Ne koristi se. Za rušenja i performanse koristi se MetricKit i Xcode Organizer. MetricKit izvještaji spremaju se samo u lokalni dnevnik (`Diagnostics` u GymKitu, `App/Diagnostics/`), bez korisničkih podataka; korisnik ih sam izvozi u Postavke > O aplikaciji > Dijagnostika. Ništa se ne šalje automatski, pa to nije "prikupljanje" u smislu privacy labela. | Faza 13 (gotovo) |
| **Dobna oznaka i djeca (COPPA)** | Aplikacija nije namijenjena djeci i ne prikuplja osobne podatke prema razvojnom timu. Dobna oznaka u App Store Connectu: 4+, odgovori na upitnik su u `AppStore/README.md`. Age gate nije potreban jer nema računa ni prikupljanja. | Faza 14 (gotovo) |
| **Pristupačnost** | Dynamic Type, VoiceOver oznake, dovoljan kontrast (WCAG 2.2 AA kao smjernica). Pravila i ručna provjera su u `docs/DIZAJN.md`. | Faza 13 (gotovo) |
| **Open source licence** | Katalog vježbi je MoveKit (komercijalna licenca, vidi ispod). Za svaku novu biblioteku provjeriti licencu i upisati je ovdje. Prednost imaju MIT, Apache i BSD. GPL se ne koristi. | Stalno |
| **Sigurnost podataka** | Podatke štiti iOS enkripcija uređaja i iCloud. Aplikacija ne drži ni ne šalje lozinke. Datoteke baze koriste zadanu zaštitu datoteka (Data Protection). | Faza 1 |

## App Store Connect: privatnost

Odgovori za App Privacy u App Store Connectu (vrijede dok aplikacija nema server, analitiku ni SDK-ove trećih strana):

* **Privacy Policy URL:** https://brunodobric.github.io/GymApp/privacy/ (engleska verzija: `/privacy/en/`).
* **Data Collection:** "No, we do not collect data from this app." Rezultat je oznaka **Data Not Collected**. Obrazloženje: podaci su na uređaju i u korisnikovoj privatnoj CloudKit bazi, kojoj razvojni tim nema pristup; Apple to ne smatra prikupljanjem. HealthKit podaci ne napuštaju uređaj. MetricKit izvještaji ostaju na uređaju, a izvoz pokreće korisnik.
* **Tracking:** ne.
* **Export Compliance:** aplikacija koristi samo Appleovu enkripciju (HTTPS i iCloud), pa je izuzeta. `ITSAppUsesNonExemptEncryption = NO` je u Info.plist aplikacije i sata, pa App Store Connect ne pita kod svakog builda.
* **Napomena za App Review (HealthKit):** "Apolon saves strength workouts to Health so they count toward Activity rings, and reads cardio workouts, body mass and height to show them in the workout history and body tracking. Health data is stored only on device, is never synced to iCloud, and is never shared. The app works fully without Health access; permission is requested only when the user chooses to connect Health during onboarding or in Settings."
* **Dobna oznaka:** 4+, odgovori na upitnik su u `AppStore/README.md`.
* **Support URL:** https://brunodobric.github.io/GymApp/podrska/ (engleska verzija: `/support/`).

## Evidencija ovisnosti

| Komponenta | Licenca | Gdje se koristi |
|---|---|---|
| MoveKit, Complete Exercise Library (movekit.com) | Komercijalna, MoveKit License Agreement v1.0 (licenca na Bruna Dobrića, prijenos na tvrtku moguć jednom) | Katalog vježbi: klipovi, posteri, metapodaci, upute i česte greške. Pisanom potvrdom (e-mail, studeni 2026) dopušteno je ugraditi sadržaj u aplikaciju i isporučiti ga preko Applea, pretvoriti klipove u drugi format, izrezati ih, napraviti postere i ukloniti metapodatke. Navođenje izvora nije obavezno. Uvjeti: sirove datoteke ne smiju biti javno dostupne ni preuzimljive (nema javnih poveznica, aplikacija nema izvoz klipova), a licenca i certifikat čuvaju se uz pakete. Zato licencirani sadržaj nije u javnom repozitoriju: postupak je u `docs/movekit.md`. U repozitoriju su samo naši podaci (mapiranje, hrvatski nazivi). |
| free-exercise-db | Unlicense | **Više se ne koristi** (zamijenjen MoveKitom u studenom 2026). |
| Everkinetic (github.com/everkinetic/data) | CC BY-SA 4.0, © Greg Priday i suradnici | **Više se ne koristi** (izbačeno u studenom 2026). Starije verzije aplikacije sadrže izmijenjene crteže. Njihova javna kopija pod istom licencom ostaje u povijesti ovog repozitorija: `Resources/Drawings/` na commitu `52fe599`. |
| MuscleMap (github.com/Jsplice/MuscleMap) | MIT, © 2026 Jsplice / MuscleMap contributors | SVG putanje muškog i ženskog tijela za heatmap (samo vektori, bez fotografija). Pretvara ih `scripts/convert-musclemap.py` u `Resources/BodyMap/body.json`. Copyright napomena i tekst licence (`LICENSE-MuscleMap.txt`) su u "O aplikaciji" na iOS-u i Androidu. |

## Ne vrijedi sada, ali treba provjeriti ako se uvede

* **Pretplate (freemium, specifikacija odjeljak 10):** uz gumb za kupnju jasno prikazati automatsku obnovu, cijenu, period i kako se otkazuje. Koristiti StoreKit i Appleov tok otkazivanja.
* **E-mail marketing:** aplikacija ne prikuplja e-mail. Ako se ikad uvede newsletter, potrebna je privola i odjava u svakoj poruci.
* **Push obavijesti s marketinškim sadržajem:** samo uz izričitu privolu. Podsjetnici za trening nisu marketing.
* **Dijeljenje rasporeda (post-MVP):** ako korisnici budu dijelili ili objavljivali sadržaj, treba procedura za prijavu povrede autorskih prava (DMCA) i uvjeti korištenja.
* **Vlastiti server ili analitika:** mijenja privacy label, zahtijeva ažuriranje pravila privatnosti i, za EU, pravnu osnovu i eventualno privolu.
