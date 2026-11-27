# Google Play materijali

Sve što se upisuje u Play Console za Android aplikaciju Apolon (mobitel i Wear OS sat), na hrvatskom (`hr`, zadani jezik) i engleskom (`en-US`). Tekst se mijenja ovdje, a u Play Console se kopira. CI (`Tools/PlayStore/check_metadata.py`) provjerava duljine i da oba jezika imaju sve datoteke. Postupak izdanja i odgovori za obrasce su u `docs/android-izdanje.md`.

| Datoteka | Polje u Play Consoleu | Ograničenje |
|---|---|---|
| `metadata/<jezik>/title.txt` | App name | 30 znakova |
| `metadata/<jezik>/short_description.txt` | Short description | 80 znakova |
| `metadata/<jezik>/full_description.txt` | Full description | 4000 znakova |
| `metadata/<jezik>/release_notes.txt` | Release notes | 500 znakova |
| `graphics/icon-512.png` | App icon | 512 × 512, PNG, iz `App/Assets.xcassets/AppIcon.appiconset` |
| `graphics/feature-graphic-<jezik>.png` | Feature graphic | 1024 × 500 |

Naslov i kratki opis ne smiju imati emotikone, velika slova radi isticanja ni riječi o rangu, cijeni ili akciji ("najbolji", "#1", "besplatno").
