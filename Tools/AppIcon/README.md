# Ikona aplikacije

`AppIcon.svg` je vektorski izvor ikone (1024×1024): bijela ruka nacrtana linijom debljine 26 px na tamnoplavom prijelazu. Ruka je precrtana po Brunovoj skici.

PNG za `App/` i `WatchApp/` (`AppIcon.appiconset/AppIcon.png`, 1024×1024, bez prozirnosti) iscrtava se iz SVG-a u bilo kojem pregledniku ili alatu za vektore, npr.:

```sh
rsvg-convert -w 1024 -h 1024 Tools/AppIcon/AppIcon.svg -o App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
cp App/Assets.xcassets/AppIcon.appiconset/AppIcon.png WatchApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

Debljina linije mijenja se u atributu `stroke-width`. Zaobljenje kutova i krug na satu dodaje sustav, pa SVG ostaje kvadratan.
