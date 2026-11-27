#!/usr/bin/env python3
"""Provjera Google Play tekstova (PlayStore/metadata/<jezik>/*.txt).

Provjerava ograničenja duljine u Play Consoleu, da svaki jezik ima sve datoteke i da tekst nema
emotikone ni riječi koje Play pravila ne dopuštaju u naslovu i kratkom opisu (npr. "najbolji", "#1").
Greške se ispisuju jedna po retku, a izlazni kod je 1.

Pokretanje: python3 Tools/PlayStore/check_metadata.py [korijen PlayStore mape]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DIR = ROOT / "PlayStore"
LANGUAGES = ["hr", "en-US"]

# Datoteka: najviše znakova (Play Console broji znakove, ne bajtove).
FIELDS = {
    "title.txt": 30,
    "short_description.txt": 80,
    "full_description.txt": 4000,
    "release_notes.txt": 500,
}
# Polja u kojima Play pravila o metapodacima ne dopuštaju rangiranje, cijene i promocije.
STRICT_FIELDS = {"title.txt", "short_description.txt"}
FORBIDDEN = re.compile(r"(#1|\bnajbolj|\bbest\b|\btop\b|\bfree\b|\bbesplat|\bsale\b|\bpopust)", re.IGNORECASE)
EMOJI = re.compile("[\U0001F300-\U0001FAFF☀-⛿✀-➿]")


def check(base: Path) -> list[str]:
    errors: list[str] = []
    for language in LANGUAGES:
        folder = base / "metadata" / language
        for name, limit in FIELDS.items():
            path = folder / name
            if not path.is_file():
                errors.append(f"{path}: nedostaje")
                continue
            text = path.read_text(encoding="utf-8").strip()
            if not text:
                errors.append(f"{path}: prazno")
            if len(text) > limit:
                errors.append(f"{path}: {len(text)} znakova, najviše {limit}")
            if name in STRICT_FIELDS:
                if FORBIDDEN.search(text):
                    errors.append(f"{path}: riječ koju Play ne dopušta u ovom polju ({FORBIDDEN.search(text).group(0)})")
                if EMOJI.search(text):
                    errors.append(f"{path}: emotikon")
    return errors


def main() -> int:
    base = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DIR
    errors = check(base)
    for error in errors:
        print(error)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
