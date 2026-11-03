# Pravo, privatnost i sigurnost

Pregled pravila koja se odnose na GymApp, prema checklistu za male aplikacije (skill *app-sigurnost-i-pravo*). **Ovo nije pravni savjet.** Prije izdanja, a osobito prije uvođenja pretplata, preporučuje se provjera kod odvjetnika za tech i privatnost.

GymApp je u dobrom položaju jer nema vlastiti server, korisničke račune, analitiku ni SDK-ove trećih strana. Većina rizika s popisa zato ne postoji. Ono što ostaje:

## Vrijedi od prvog izdanja

| Područje | Što GymApp radi | Status |
|---|---|---|
| **Privacy policy** | Javni URL. Navodi da su podaci samo na uređaju i u korisnikovom iCloudu, da HealthKit podaci ne idu nikome i ne koriste se za oglase, da nema praćenja ni analitike. Mora točno odgovarati ponašanju aplikacije. | Faza 13 |
| **App Store privacy label** | "Data Not Collected", dok god nema analitike ni servera. Privacy Manifest (`PrivacyInfo.xcprivacy`) postoji u aplikaciji i na satu. | Manifest u fazi 0 |
| **HealthKit pravila** | Dozvole samo za korištene tipove, s jasnim objašnjenjem: zapis treninga; čitanje treninga, aktivnih kalorija, udaljenosti (hodanje i trčanje, bicikl, plivanje), pulsa, težine i visine. Dozvola se traži tek kad korisnik u onboardingu ili Postavkama odabere povezivanje. Podaci se ne šalju trećima. Aplikacija radi i bez dozvole. | Faza 7 (gotovo) |
| **HealthKit podaci i iCloud** | Pravilo App Storea 5.1.3 (ii) zabranjuje spremanje osobnih zdravstvenih podataka u iCloud. Uvezeni treninzi (kalorije, puls) i mjerenja iz Zdravlja su u korisničkoj bazi, koja se u fazi 12 sinkronizira preko CloudKita. Prije faze 12 odlučiti: uvezeni zapisi ostaju samo lokalni (zasebna konfiguracija baze) ili se pri svakom uređaju ponovno čitaju iz Zdravlja. | Odluka prije faze 12 |
| **GDPR (EU, uključujući Hrvatsku)** | Pravo na pristup i prenosivost pokriva export u CSV i JSON. Pravo na brisanje pokriva "Obriši sve podatke" (lokalno i iCloud). Minimalni podaci: bez imena, e-maila i lokacije. Prijenos podataka izvan EU ne radi aplikacija nego Apple (iCloud), što treba navesti u pravilima privatnosti. | Faze 6 i 12 |
| **Vanjski resursi** | Fontovi su sistemski, slike vježbi u bundleu. Aplikacija se ne spaja ni na kakav vanjski server osim Appleovih servisa. Ne smije se dodati Google Fonts, embed ni CDN. | Pravilo za cijeli projekt |
| **Session replay i tracking** | Ne koristi se. Za rušenja i performanse koristi se MetricKit i Xcode Organizer. | Pravilo za cijeli projekt |
| **Dobna oznaka i djeca (COPPA)** | Aplikacija nije namijenjena djeci i ne prikuplja osobne podatke prema razvojnom timu. Dobna oznaka u App Store Connectu: 4+ ili 12+ prema upitniku. Age gate nije potreban jer nema računa ni prikupljanja. | Faza 14 |
| **Pristupačnost** | Dynamic Type, VoiceOver oznake, dovoljan kontrast (WCAG 2.2 AA kao smjernica). | Faza 13 |
| **Open source licence** | free-exercise-db je Unlicense (javno vlasništvo), uz atribuciju u "O aplikaciji". Za svaku novu biblioteku provjeriti licencu i upisati je ovdje. Prednost imaju MIT, Apache i BSD. GPL se ne koristi. | Stalno |
| **Sigurnost podataka** | Podatke štiti iOS enkripcija uređaja i iCloud. Aplikacija ne drži ni ne šalje lozinke. Datoteke baze koriste zadanu zaštitu datoteka (Data Protection). | Faza 1 |

## Evidencija ovisnosti

| Komponenta | Licenca | Gdje se koristi |
|---|---|---|
| free-exercise-db | Unlicense | Katalog vježbi (podaci i slike) |
| MuscleMap (github.com/Jsplice/MuscleMap) | MIT, © 2026 Jsplice / MuscleMap contributors | SVG putanje muškog i ženskog tijela za heatmap (samo vektori, bez fotografija). Pretvara ih `scripts/convert-musclemap.py` u `Resources/BodyMap/body.json`. Copyright napomena i tekst licence (`LICENSE-MuscleMap.txt`) su u "O aplikaciji". |

## Ne vrijedi sada, ali treba provjeriti ako se uvede

* **Pretplate (freemium, specifikacija odjeljak 10):** uz gumb za kupnju jasno prikazati automatsku obnovu, cijenu, period i kako se otkazuje. Koristiti StoreKit i Appleov tok otkazivanja.
* **E-mail marketing:** aplikacija ne prikuplja e-mail. Ako se ikad uvede newsletter, potrebna je privola i odjava u svakoj poruci.
* **Push obavijesti s marketinškim sadržajem:** samo uz izričitu privolu. Podsjetnici za trening nisu marketing.
* **Dijeljenje rasporeda (post-MVP):** ako korisnici budu dijelili ili objavljivali sadržaj, treba procedura za prijavu povrede autorskih prava (DMCA) i uvjeti korištenja.
* **Vlastiti server ili analitika:** mijenja privacy label, zahtijeva ažuriranje pravila privatnosti i, za EU, pravnu osnovu i eventualno privolu.
