# Ikona aplikacije

`AppIcon.svg` je vektorski izvor ikone (1024×1024): bijela ruka nacrtana linijom debljine 26 px na tamnoplavom prijelazu. Ruka je precrtana po Brunovoj skici.

PNG za `App/` i `WatchApp/` (`AppIcon.appiconset/AppIcon.png`, 1024×1024, bez prozirnosti) iscrtava se iz SVG-a u bilo kojem pregledniku ili alatu za vektore, npr.:

```sh
rsvg-convert -w 1024 -h 1024 Tools/AppIcon/AppIcon.svg -o App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
cp App/Assets.xcassets/AppIcon.appiconset/AppIcon.png WatchApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

Debljina linije mijenja se u atributu `stroke-width`. Zaobljenje kutova i krug na satu dodaje sustav, pa SVG ostaje kvadratan.

## Android

Android koristi adaptivnu ikonu (`android/app/src/main/res/mipmap-anydpi/ic_launcher.xml`): pozadina je prijelaz preko cijelog sloja (`drawable/ic_launcher_background.xml`), a prednji sloj su iste putanje ruke kao u SVG-u (`drawable/ic_launcher_foreground.xml`), smanjene tako da cijeli SVG stane u vidljivi dio sloja (72 od 108 dp). Launcher sam izreže krug ili drugi oblik, pa ikona uvijek ispuni cijeli oblik. Kad se ruka u SVG-u promijeni, putanje se prepišu u prednji sloj.
