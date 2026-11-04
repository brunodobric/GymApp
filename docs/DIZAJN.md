# Pravila dizajna (Apple HIG)

Pravila iz Apple Human Interface Guidelines (skill *apple-hig-dizajn*) primijenjena na GymApp. Vrijede za svaki ekran. Kod reviewa ekrana provjerava se ovaj popis.

## Principi u kontekstu aplikacije

* **Purpose:** najvažnije je brzo bilježenje serije u teretani. Sve ostalo je sporedno tom zadatku.
* **Agency:** korisnik može poništiti radnje (izbacivanje vježbe, preskakanje treninga, brisanje serije). Vođeni tokovi (onboarding) uvijek se mogu preskočiti.
* **Responsibility:** svaka dozvola (Zdravlje, obavijesti) traži se tek kad je potrebna, uz rečenicu zašto.
* **Delight:** fitness aplikacija treba davati energiju: proslava PR-a u sažetku, jasna haptika na kraju odmora. Bez ukrasa koji usporavaju unos.

## Navigacija

* **Tab bar je samo za navigaciju.** Akcije (Započni, Dodaj, Postavke) idu u sadržaj ili toolbar.
* Pet tabova s labelama od jedne riječi i ispunjenim SF Symbolima:

| Tab | Labela | Simbol | U specifikaciji |
|---|---|---|---|
| 1 | Početna | `house.fill` | Dashboard |
| 2 | Povijest | `clock.fill` | Odrađeni treninzi |
| 3 | Rasporedi | `calendar` | Rasporedi |
| 4 | Vježbe | `dumbbell.fill` | Katalog vježbi |
| 5 | Statistika | `chart.bar.fill` | Statistika |

* Tabovi se nikad ne skrivaju ni onemogućuju. Prazna sekcija prikazuje `ContentUnavailableView` s objašnjenjem.
* Na iPadu se tab bar pretvara u sidebar (`.tabViewStyle(.sidebarAdaptable)`), a na iPhoneu je dolje. Odluka ovisi o size classu, ne o uređaju.
* Split view (`NavigationSplitView`) koristi se samo u regular širini. Trenutni odabir u listi uvijek je označen.

## Toolbar

* Naslovi su kratki (do 15 znakova) i nikad nisu "Apollo".
* Standardni Back i Close gumbi, bez teksta "Natrag".
* Najviše jedna istaknuta akcija (npr. **Završi**, **Gotovo**) i to na trailing strani.
* Akcije su sistemski simboli bez rubova i bez obojenih pozadina toolbara. Kad projekt prijeđe na iOS 26 SDK, barovi koriste Liquid Glass i scroll edge effect, bez vlastitih pozadina.
* Najviše oko tri grupe stavki u toolbaru. Rijetke akcije idu u izbornik.

## Ekran aktivnog treninga (iPhone)

* Kontrole za unos serije su u srednjem i donjem dijelu ekrana, za rad jednom rukom.
* Ciljane površine najmanje 44 × 44 pt. Kvačica serije je velika.
* Retci serija podržavaju swipe akcije (brisanje serije, warm-up).
* Brojevi koriste `monospacedDigit()`, pa se redak ne pomiče dok timer odbrojava.

## Prilagodljivost

* Svi ekrani rade od najmanjeg iPhonea do iPada 13" i u Split Viewu i Stage Manageru.
* **Dynamic Type:** do najveće veličine pristupačnosti tekst se ne reže. Vodoravni retci prelaze u okomite kad tekst naraste.
* Poštuju se safe area i Dynamic Island. Nema fiksnih širina.
* Dark Mode je zadani izgled, ali i svijetli mora biti ispravan.
* Hrvatski tekstovi su dulji od engleskih: svaki ekran se provjerava na hrvatskom.

## Pristupačnost

* **Dynamic Type:** veličine elemenata uz tekst (oznaka serije, polja za unos, odbrojavanje na satu) idu kroz `@ScaledMetric`, ne fiksne brojeve. Retci s više polja (redak serije, traka odmora) kod veličina pristupačnosti (`dynamicTypeSize.isAccessibilitySize`) prelaze u dva retka.
* **VoiceOver:** svaki gumb sa samo simbolom ima tekst (`Button("Preskoči", systemImage:)` s `.labelStyle(.iconOnly)` ili `accessibilityLabel`). Znakovi koji se ne čitaju dobro (×, Z, +10) dobivaju izgovorljiv opis: "Serija 2, 80 kg, 8 ponavljanja", "Zagrijavanje", "Produlji odmor za 10 sekundi". Odabrano stanje ide kroz `.isSelected`, a ukrasne slike su `accessibilityHidden`.
* **Grafovi** imaju `accessibilityLabel` koji kaže što prikazuju, a heatmap tijela ima tekstualni sažetak.
* **Kontrast:** boje su sistemske (prilagođavaju se za "Povećaj kontrast"). Prigušivanje prozirnošću (završene serije) isključuje se kad je `colorSchemeContrast == .increased`. Stanje se nikad ne prikazuje samo bojom: završena serija ima i kvačicu, dan s treningom i točku i opis za VoiceOver.
* **Smanji kretanje:** animacije prijelaza poštuju `accessibilityReduceMotion`.

### Ručna provjera prije izdanja

1. Postavke > Pristupačnost > Prikaz i veličina teksta > Veći tekst: najveća veličina. Proći Početnu, aktivni trening (redak serije, traka odmora), povijest, statistiku i postavke na iPhoneu SE. Ništa se ne reže i sve je dostupno scrollanjem.
2. VoiceOver: odraditi cijeli trening (Započni, unos serije, kvačica, odmor, Završi) bez gledanja u ekran.
3. Povećaj kontrast i Smanji prozirnost: završene serije i oznake ostaju čitljive.
4. Xcode Accessibility Inspector > Audit na glavnim ekranima.
5. Isto na satu: najveći tekst i VoiceOver na ekranu treninga i odmora.

## Apple Watch

* Nema tab bara. Ekran aktivnog treninga ima najviše tri gumba sa simbolima ili dva s tekstom u retku.
* Važne akcije su velike i dostupne bez scrollanja. Digital Crown služi za težinu i ponavljanja.
* Haptika na kraju odmora je obavezna.
