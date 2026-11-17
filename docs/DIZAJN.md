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
| 3 | Plan | `calendar` | Rasporedi i treninzi |
| 4 | Vježbe | `dumbbell.fill` | Katalog vježbi |
| 5 | Statistika | `chart.bar.fill` | Statistika |

* Tabovi se nikad ne skrivaju ni onemogućuju. Prazna sekcija prikazuje `ContentUnavailableView` s objašnjenjem.
* Na iPadu se tab bar pretvara u sidebar (`.tabViewStyle(.sidebarAdaptable)`), a na iPhoneu je dolje. Odluka ovisi o size classu, ne o uređaju.
* Split view (`NavigationSplitView`) koristi se samo u regular širini. Trenutni odabir u listi uvijek je označen.
* **Svaki tab je u regular širini podijeljen na lijevi i desni stupac** (`TabSplitView` u `App/Design/SplitLayout.swift`): iPad, iPhone u vodoravnom položaju i unutarnji zaslon otvorenog iPhonea Duo. Oba stupca su uvijek vidljiva (stil `.balanced`, bez gumba za skrivanje bočnog stupca), pa se ni uspravni otvoreni zaslon ne pretvara u jedan razvučeni stupac. Na vanjskom zaslonu (compact) tab je jedan stupac, kao na iPhoneu.
  * Povijest: popis treninga lijevo, detalji treninga desno.
  * Plan: rasporedi i treninzi lijevo, uređivač desno.
  * Vježbe: odabir vrste (kapsule), pretraga i popis vježbi lijevo, vježba desno. Dok vježba nije odabrana, desno su kartice vrsta, koje mijenjaju popis lijevo.
  * Aktivni trening: otvorena vježba (video, mišići i upute) lijevo, popis vježbi i serija desno. Lijevi stupac prati otvorenu vježbu (bez nje prvu s neodrađenim serijama), a gumb za upute na kartici vježbe tad otvara tu vježbu umjesto lista.
  * Početna i Statistika: kartice lijevo, ekran dodirnute kartice desno (`DetailLink`, odabrana kartica dobiva obrub u boji akcenta). Zadani desni stupac je zadnji trening (Početna) odnosno pregled tjedna (Statistika).
* Preklapanje i otvaranje iPhonea Duo ne gubi mjesto: otvoreni ekran desnog stupca postaje vrh stoga na vanjskom zaslonu i obrnuto (zajednički `path` odnosno odabir u svakom tabu).

## Toolbar

* Naslovi su kratki (do 15 znakova) i nikad nisu "Apolon".
* Standardni Back i Close gumbi, bez teksta "Natrag".
* Najviše jedna istaknuta akcija (npr. **Završi**, **Gotovo**) i to na trailing strani.
* Akcije su sistemski simboli bez rubova i bez obojenih pozadina toolbara. Kad projekt prijeđe na iOS 26 SDK, barovi koriste Liquid Glass i scroll edge effect, bez vlastitih pozadina.
* Najviše oko tri grupe stavki u toolbaru. Rijetke akcije idu u izbornik.

## Tipografija

Smjer "Apolon, mirniji": zaobljeni bold za naslove i brojeve, obični SF Pro za opise. Stilovi su na jednom mjestu, `Shared/Design/AppFont.swift`, i dijele ih aplikacija, Live Activity i sat.

* **SF Pro Rounded** (stilovi iz `AppFont`): naslovi ekrana i kartica, nazivi treninga, rasporeda, vježbi i programa, mala oznaka verzalom i svi brojevi (težina, ponavljanja, vrijeme, volumen, rekordi).
* **Obični SF Pro** (sistemski stilovi, npr. `.subheadline`): opisi i sekundarni tekst, gumbi, retci formi, zaglavlja sekcija. Postavke, onboarding (osim naslova pitanja) i katalog vježbi su u običnom SF Pro.
* **Retci listi:** naziv treninga, rasporeda ili programa u retku je `itemTitle`, a opis ispod njega (datum, broj vježbi, ciklus) je obični `.subheadline`. Tako izgledaju Povijest, Plan, Gotovi programi i biranje treninga. Iznimka su retci vježbi u katalogu i u biranju vježbi: naziv vježbe je tamo u običnom SF Pro, jer su to duge liste za pretraživanje, a ne naslovi.
* `.fontDesign(.rounded)` se ne stavlja na cijeli ekran ili karticu, jer tada zaobli i opise. Stil se bira po ulozi teksta.
* **Težine:** bold za naslove i istaknute brojeve, semibold za brojeve u retku i polju za unos, regular za opise. Bez light i medium.
* **Naslovi u navigacijskoj traci** su zaobljeni (`App/Design/NavigationBarFont.swift`): veliki bold, mali semibold.
* **Dynamic Type:** uvijek tekstualni stil. Fiksna veličina samo kroz `@ScaledMetric`.
* **Sat:** brojevi su zaobljeni semibold (`.system(..., design: .rounded, weight: .semibold)`), nazivi `Font.itemTitle`, ostalo obični SF Pro.

| Stil | Uloga | Primjer |
|---|---|---|
| `screenTitle` | veliki naslov u sadržaju | naziv treninga na detalju |
| `cardTitle` | naslov kartice ili istaknutog retka | "Započni: Push dan", pitanje u onboardingu |
| `itemTitle` | naziv vježbe, treninga, rasporeda ili programa | kartica vježbe, Povijest, Plan, Live Activity |
| `cardHeading` | naslov kartice verzalom uz ikonu | ZADNJI TRENING |
| `eyebrow` | mala oznaka verzalom | ODMOR, zaglavlje tablice serija, SUPERSET |
| `metricLarge` | najveći broj | odbrojavanje odmora, kotačić |
| `metric` | istaknut broj na kartici | volumen tjedna, odmor na kartici |
| `metricSmall` | manji istaknut broj | težina i ponavljanja u kartici treninga |
| `fieldValue` | vrijednost u polju za unos | težina i ponavljanja u retku serije |
| `rowValue` | broj u retku liste | serija na detalju, rekord |
| `rowValueSmall` | manji broj u retku | redni broj serije, prošli put |

## Ekran aktivnog treninga (iPhone)

* Kontrole za unos serije su u srednjem i donjem dijelu ekrana, za rad jednom rukom.
* Ciljane površine najmanje 44 × 44 pt. Kvačica serije je velika.
* Retci serija podržavaju swipe akcije (brisanje serije, warm-up).
* Brojevi koriste `monospacedDigit()`, pa se redak ne pomiče dok timer odbrojava.
* U regular širini (iPad, otvoreni iPhone Duo) ekran je podijeljen: lijevo otvorena vježba s videom i uputama, desno ovaj popis s kontrolama unosa.

## Prilagodljivost

* Svi ekrani rade od najmanjeg iPhonea do iPada 13" i u Split Viewu i Stage Manageru.
* **Dynamic Type:** do najveće veličine pristupačnosti tekst se ne reže. Vodoravni retci prelaze u okomite kad tekst naraste.
* Poštuju se safe area i Dynamic Island. Nema fiksnih širina.
* Dark Mode je zadani izgled, ali i svijetli mora biti ispravan.
* Hrvatski tekstovi su dulji od engleskih: svaki ekran se provjerava na hrvatskom.

## Boja

* **Paleta:** šest plavo-sivih tonova, `#06141B`, `#11212D`, `#253745`, `#4A5C6A`, `#9BA8AB` i `#CCD0CF` (`AppPalette` u `Shared/Design`, na Androidu `AppPalette` u `ui/theme/Theme.kt`). Uloge:

  | Uloga | Svijetla | Tamna | Zamjenjuje |
  |---|---|---|---|
  | Podloga ekrana (`background`) | `#E6E9E8` | `#06141B` | `systemGroupedBackground` |
  | Kartica i redak popisa (`card`) | `#F7F8F8` | `#11212D` | `secondarySystemGroupedBackground` |
  | Ispuna (`fill`): prazne točke, trake, sličice | `#CCD0CF` | `#253745` | `tertiarySystemFill` |
  | Blaža ispuna (`subtleFill`): polja, neodabrane opcije | `#E6E9E8` | `#1A2C39` | `quaternarySystemFill` |
  | Razdjelnik (`separator`), nije za tekst | `#9BA8AB` | `#4A5C6A` | |
  | Primarni tekst (`text`) | `#06141B` | `#CCD0CF` | `label` |
  | Sekundarni tekst (`secondaryText`) | `#4A5C6A` | `#9BA8AB` | `secondaryLabel` |
  | Akcent Čelik (`accent`) | `#253745` | `#CCD0CF` | |
  | Tekst na punom akcentu (`onAccent`) | `#FFFFFF` | `#06141B` | bijela |

  Dva svijetla tona (`#E6E9E8`, `#F7F8F8`) izvedena su iz `#CCD0CF`; tamna tema koristi samo paletu. Kontrast na kartici: primarni tekst 17,6 i 10,6 : 1, sekundarni 6,5 i 6,7 : 1, akcent 11,5 i 10,6 : 1. Sat ostaje na čistoj crnoj (OLED), a akcent mu je tamna vrijednost.
* **Akcent je jedan, Čelik.** Izbor boje u Postavkama je uklonjen. `AccentChoice` u GymKitu ima samo `steel` i i dalje se prenosi (sat, widgeti, Live Activity, sigurnosna kopija); svaka stara spremljena boja čita se kao Čelik. Isti je u `AccentColor` u katalozima aplikacije i sata, pa sustav (upozorenja, prvo pokretanje) ima istu boju.
* **Tekst na akcentu je `onAccent`, nikad `.white`:** u tamnoj temi je akcent svijetao. Gumbi `.borderedProminent` zato dobivaju `.foregroundStyle(AppPalette.onAccent)`.
* **Akcent i paleta u kodu:** `appPalette()` na korijenu prozora (i na listovima koji ga trebaju) postavlja `.tint`, `@Environment(\.appAccent)` za pozadine, grafove i Canvas te primarni i sekundarni tekst (`foregroundStyle(text, secondaryText)`). Naslovi u navigacijskoj traci dobivaju boju teksta kroz `NavigationBarFont`. Popisi (`List`, `Form`) dobivaju `.appListBackground()`, a redovi `.listRowBackground(AppPalette.card)`; popis s odabirom (stupac na iPadu) boji odabrani redak sam (`selectableRowBackground`), jer vlastita boja retka skriva sistemsko isticanje. Ne koriste se `Color.accentColor`, sistemska `.blue` ni sistemske pozadine.
* **Semantičke boje ne prate akcent:** zelena je završena serija (i gumb "Završi seriju" na satu), narančasta zagrijavanje, rekord i niz, crvena brisanje i greške, a mišićne skupine imaju svoje boje. Zato akcent nije ni zelen, ni crven, ni narančast.

## Pristupačnost

* **Dynamic Type:** veličine elemenata uz tekst (oznaka serije, polja za unos, odbrojavanje na satu) idu kroz `@ScaledMetric`, ne fiksne brojeve. Retci s više polja (redak serije, traka odmora) kod veličina pristupačnosti (`dynamicTypeSize.isAccessibilitySize`) prelaze u dva retka.
* **VoiceOver:** svaki gumb sa samo simbolom ima tekst (`Button("Preskoči", systemImage:)` s `.labelStyle(.iconOnly)` ili `accessibilityLabel`). Znakovi koji se ne čitaju dobro (×, Z, +10) dobivaju izgovorljiv opis: "Serija 2, 80 kg, 8 ponavljanja", "Zagrijavanje", "Produlji odmor za 10 sekundi". Odabrano stanje ide kroz `.isSelected`, a ukrasne slike su `accessibilityHidden`.
* **Grafovi** imaju `accessibilityLabel` koji kaže što prikazuju, a heatmap tijela ima tekstualni sažetak.
* **Kontrast:** boje palete imaju barem 4,5 : 1 za tekst i ne mijenjaju se za "Povećaj kontrast"; semantičke boje su sistemske i prilagođavaju se. Zasivljenje i prigušivanje prozirnošću (završene serije) isključuje se kad je `colorSchemeContrast == .increased`. Stanje se nikad ne prikazuje samo bojom: završena serija ima i punu zelenu kvačicu (nezavršena je obrubljena ili svijetla), dan s treningom i točku i opis za VoiceOver.
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
