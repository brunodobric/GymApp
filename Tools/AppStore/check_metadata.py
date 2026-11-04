#!/usr/bin/env python3
"""Provjera App Store tekstova (AppStore/metadata/<jezik>/*.txt i AppStore/review_notes.txt).

Provjerava Appleova ograničenja duljine, da svaki jezik ima sve obavezne
datoteke, da ključne riječi nemaju razmake ni ponavljanja i da URL-ovi
počinju s https://. Greške se ispisuju jedna po retku, a izlazni kod je 1.

Pokretanje: python3 Tools/AppStore/check_metadata.py [korijen AppStore mape]
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DIR = ROOT / "AppStore"
LANGUAGES = ["hr", "en-US"]

# Datoteka: (najviše, mjeri se u "chars" ili "bytes", obavezna)
FIELDS = {
    "name.txt": (30, "chars", True),
    "subtitle.txt": (30, "chars", True),
    "promotional_text.txt": (170, "chars", True),
    "description.txt": (4000, "chars", True),
    # App Store Connect ključne riječi broji u bajtovima (UTF-8), pa č, ć, ž, š, đ broje dvostruko.
    "keywords.txt": (100, "bytes", True),
    "release_notes.txt": (4000, "chars", True),
    "support_url.txt": (255, "chars", True),
    "privacy_url.txt": (255, "chars", True),
}
REVIEW_NOTES_LIMIT = 4000


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8").strip()


def size(text: str, unit: str) -> int:
    return len(text.encode("utf-8")) if unit == "bytes" else len(text)


def check_language(folder: Path) -> list[str]:
    errors = []
    language = folder.name
    if not folder.is_dir():
        return [f"{language}: nema mape {folder}"]
    texts: dict[str, str] = {}
    for name, (limit, unit, required) in FIELDS.items():
        path = folder / name
        if not path.exists():
            if required:
                errors.append(f"{language}/{name}: datoteka nedostaje")
            continue
        text = read(path)
        texts[name] = text
        if required and not text:
            errors.append(f"{language}/{name}: prazno")
        length = size(text, unit)
        if length > limit:
            unit_label = "bajtova" if unit == "bytes" else "znakova"
            errors.append(f"{language}/{name}: {length} {unit_label}, najviše {limit}")
        if name.endswith("_url.txt") and text and not text.startswith("https://"):
            errors.append(f"{language}/{name}: URL mora počinjati s https://")
    for name in sorted(p.name for p in folder.glob("*.txt")):
        if name not in FIELDS:
            errors.append(f"{language}/{name}: nepoznata datoteka")
    errors += check_keywords(language, texts.get("keywords.txt", ""), texts.get("name.txt", ""), texts.get("subtitle.txt", ""))
    return errors


def check_keywords(language: str, keywords: str, name: str, subtitle: str) -> list[str]:
    if not keywords:
        return []
    errors = []
    items = keywords.split(",")
    if any(item != item.strip() for item in items):
        errors.append(f"{language}/keywords.txt: bez razmaka oko zareza (troše mjesto)")
    words = [item.strip().lower() for item in items]
    if "" in words:
        errors.append(f"{language}/keywords.txt: prazna ključna riječ")
    duplicates = sorted({word for word in words if word and words.count(word) > 1})
    if duplicates:
        errors.append(f"{language}/keywords.txt: ponavlja se {', '.join(duplicates)}")
    title_words = {word.strip(":,.").lower() for word in f"{name} {subtitle}".split()}
    repeated = sorted(word for word in set(words) if word in title_words)
    if repeated:
        errors.append(f"{language}/keywords.txt: {', '.join(repeated)} je već u nazivu ili podnaslovu")
    return errors


def check(directory: Path) -> list[str]:
    errors = []
    for language in LANGUAGES:
        errors += check_language(directory / "metadata" / language)
    notes = directory / "review_notes.txt"
    if not notes.exists():
        errors.append("review_notes.txt: datoteka nedostaje")
    elif len(read(notes)) > REVIEW_NOTES_LIMIT:
        errors.append(f"review_notes.txt: {len(read(notes))} znakova, najviše {REVIEW_NOTES_LIMIT}")
    return errors


def main(argv: list[str]) -> int:
    directory = Path(argv[1]) if len(argv) > 1 else DEFAULT_DIR
    errors = check(directory)
    for error in errors:
        print(error)
    if errors:
        return 1
    print(f"App Store tekstovi su ispravni ({', '.join(LANGUAGES)}).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
