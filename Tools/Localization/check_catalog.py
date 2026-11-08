#!/usr/bin/env python3
"""Provjera String Cataloga (Localizable.xcstrings, InfoPlist.xcstrings i fraze za Prečace u AppShortcuts.xcstrings).

Izvorni jezik je hrvatski: ključ je hrvatski tekst iz koda. Svaki ključ koji se
prevodi mora imati prevedeni engleski tekst s istim formatnim argumentima.

CI prvo pokrene `xcodebuild -exportLocalizations`, koji u katalog upiše sve
tekstove koje je kompajler izvukao iz koda, a zatim ovu skriptu. Novi tekst bez
engleskog prijevoda tako ruši CI i ispisuje se u logu.

Pokretanje: python3 Tools/Localization/check_catalog.py [putanje...] [--json]
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CATALOGS = [
    ROOT / "Resources" / "Localization" / "Localizable.xcstrings",
    ROOT / "App" / "InfoPlist.xcstrings",
    ROOT / "App" / "AppShortcuts.xcstrings",
    ROOT / "WatchApp" / "InfoPlist.xcstrings",
]
REQUIRED_LANGUAGE = "en"

# %@, %lld, %1$@, %.1f, %ld, %d, %%. Pozicija (1$) se ne uspoređuje, samo vrsta.
SPECIFIER = re.compile(r"%(?:(\d+)\$)?[-+ 0#]*(?:\d+)?(?:\.\d+)?(hh|h|ll|l|q|z|t|j|L)?([@dDuUxXoOfFeEgGcCsSpaA%])")


def specifiers(text: str) -> list[str]:
    """Vrste formatnih argumenata u tekstu, bez pozicije i bez %%."""
    found = []
    for match in SPECIFIER.finditer(text):
        kind = match.group(3)
        if kind == "%":
            continue
        length = match.group(2) or ""
        # %d i %lld su za Swift isti cijeli broj, a %f i %lf isti decimalni.
        if kind in "dDiuU":
            found.append("int")
        elif kind in "fFeEgGaA":
            found.append("double")
        else:
            found.append(length + kind)
    return sorted(found)


PLACEHOLDER = re.compile(r"\$\{(\w+)\}")


def placeholders(text: str) -> set[str]:
    """Zamjene u frazi za Prečace, npr. {"applicationName", "workout"} iz "Započni ${workout} u ${applicationName}"."""
    return set(PLACEHOLDER.findall(text))


def all_placeholders(entry: dict) -> set[str]:
    """Sve zamjene iz izvornih (hrvatskih) fraza ključa: ključ je prva fraza, ostale su u stringSetu."""
    source = entry.get("localizations", {}).get("hr", {}).get("stringSet", {}).get("values", [])
    found: set[str] = set()
    for text in source:
        found |= placeholders(text)
    return found


def string_units(localization: dict) -> list[tuple[str, dict]]:
    """Svi stringUnit zapisi lokalizacije: običan tekst, varijacije i zamjene.

    Fraze za Prečace (AppShortcuts.xcstrings) imaju stringSet: više fraza s jednim stanjem.
    Svaka fraza se provjerava kao zaseban tekst.
    """
    units = []
    if "stringUnit" in localization:
        units.append(("", localization["stringUnit"]))
    if "stringSet" in localization:
        string_set = localization["stringSet"]
        for index, value in enumerate(string_set.get("values", []), start=1):
            units.append((f"fraza {index}", {"state": string_set.get("state"), "value": value}))
    for kind, cases in localization.get("variations", {}).items():
        for case, nested in cases.items():
            for name, unit in string_units(nested):
                units.append((f"{kind}.{case}{'.' + name if name else ''}", unit))
    for name, substitution in localization.get("substitutions", {}).items():
        for case_name, unit in string_units(substitution):
            units.append((f"substitution.{name}.{case_name}", unit))
    return units


def check(catalog: dict) -> tuple[list[str], list[str], list[str]]:
    """Vraća (ključevi bez prijevoda, ostale greške, zastarjeli ključevi)."""
    missing: list[str] = []
    errors: list[str] = []
    stale: list[str] = []
    if catalog.get("sourceLanguage") != "hr":
        errors.append("Izvorni jezik kataloga mora biti hr.")
    for key, entry in sorted(catalog.get("strings", {}).items()):
        if entry.get("extractionState") == "stale":
            stale.append(key)
            continue
        if entry.get("shouldTranslate") is False:
            continue
        localization = entry.get("localizations", {}).get(REQUIRED_LANGUAGE)
        if not localization:
            missing.append(key)
            continue
        units = string_units(localization)
        if not units:
            missing.append(key)
            continue
        uses_substitutions = "substitutions" in localization
        expected = specifiers(key)
        allowed_placeholders = placeholders(key) | all_placeholders(entry)
        for case, unit in units:
            value = unit.get("value", "")
            if unit.get("state") != "translated" or not value.strip():
                errors.append(f"{key!r} [{case or 'tekst'}]: prijevod nije označen kao preveden.")
                continue
            if case.startswith("fraza "):
                # Fraza za Prečace mora imati naziv aplikacije i smije imati samo parametre iz izvornih fraza.
                found = placeholders(value)
                if "applicationName" not in found or not found <= allowed_placeholders:
                    errors.append(f"{key!r} [{case}]: zamjene {sorted(found)} ne odgovaraju izvornim frazama.")
                continue
            if uses_substitutions or case.startswith("substitution."):
                continue
            actual = specifiers(value)
            # Oblik "one" u množini smije izostaviti broj ("One set" umjesto "1 set").
            if case.startswith("plural.") and not case.startswith("plural.other"):
                if any(actual.count(s) > expected.count(s) for s in set(actual)):
                    errors.append(f"{key!r} [{case}]: argumenti {actual} ne odgovaraju ključu {expected}.")
            elif actual != expected:
                errors.append(f"{key!r} [{case or 'tekst'}]: argumenti {actual} ne odgovaraju ključu {expected}.")
    return missing, errors, stale


def main(argv: list[str]) -> int:
    args = [a for a in argv if not a.startswith("--")]
    paths = [Path(a) for a in args] or DEFAULT_CATALOGS
    failed = False
    for path in paths:
        catalog = json.loads(path.read_text(encoding="utf-8"))
        missing, errors, stale = check(catalog)
        total = len(catalog.get("strings", {}))
        print(f"== {path.relative_to(ROOT) if path.is_relative_to(ROOT) else path}")
        if "--json" in argv:
            print(json.dumps({"missing": missing, "errors": errors, "stale": stale}, ensure_ascii=False, indent=1))
        else:
            for key in missing:
                print(f"Nema engleskog prijevoda: {key!r}")
            for error in errors:
                print(f"Greška: {error}")
            for key in stale:
                print(f"Zastarjelo (više se ne koristi u kodu): {key!r}")
        print(f"Ključeva: {total}, bez prijevoda: {len(missing)}, grešaka: {len(errors)}, zastarjelih: {len(stale)}.")
        failed = failed or bool(missing or errors or stale)
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
