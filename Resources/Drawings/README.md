# Crteži vježbi (Everkinetic)

Ova mapa je javna kopija izmijenjenih crteža vježbi koje koristi aplikacija Apollo. Crteži su u `Drawings.xcassets`, po dva za svaku vježbu: `…-start.svg` (početni položaj) i `…-end.svg` (završni položaj).

## Izvor i licenca

* Izvor: [everkinetic/data](https://github.com/everkinetic/data), commit `446bb9a3d0c3beb6b84f7c9d77dfc8af707a2ab6` (`dist/svg`).
* Autori: © Greg Priday i suradnici projekta Everkinetic.
* Licenca: [Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)](https://creativecommons.org/licenses/by-sa/4.0/). Puni tekst je u [LICENSE.md](LICENSE.md).

Izmijenjeni crteži objavljuju se pod istom licencom (CC BY-SA 4.0). Licenca vrijedi samo za crteže u ovoj mapi, ne za kod aplikacije.

## Izmjene

`Tools/CatalogBuilder/build_catalog.py` (funkcija `clean_svg`) mijenja svaki crtež ovako:

* uklonjena je bijela pozadina (grupa s bijelom ispunom),
* linije su obojene crnom, a aplikacija ih boji bojom teksta prema temi (tamne u svijetlom, svijetle u tamnom načinu),
* širina i visina postavljene su prema `viewBox`u,
* datoteke su preimenovane: `0042-relaxation.svg` → `Everkinetic-0042-start.svg`, `0042-tension.svg` → `Everkinetic-0042-end.svg`.

Oblik linija nije mijenjan. Koja vježba aplikacije koristi koji crtež piše u `Tools/CatalogBuilder/everkinetic.json`.
