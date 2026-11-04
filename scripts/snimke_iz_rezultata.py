#!/usr/bin/env python3
"""Kopira snimke zaslona iz `xcresulttool export attachments` u mapu za App Store.

Izvoz daje datoteke s UUID nazivima i manifest.json; naziv snimke (npr. "01-pocetna")
je u `suggestedHumanReadableName`, ispred prvog "_".

Pokretanje: python3 scripts/snimke_iz_rezultata.py <izvezena mapa> <odredište>
"""

import json
import shutil
import sys
from pathlib import Path


def copy(exported: Path, target: Path) -> list[str]:
    manifest = json.loads((exported / "manifest.json").read_text(encoding="utf-8"))
    copied = []
    for test in manifest:
        for attachment in test.get("attachments", []):
            source = exported / attachment["exportedFileName"]
            name = attachment.get("suggestedHumanReadableName", source.name).split("_")[0]
            destination = target / f"{Path(name).stem}{source.suffix}"
            shutil.copyfile(source, destination)
            copied.append(destination.name)
    return sorted(copied)


if __name__ == "__main__":
    files = copy(Path(sys.argv[1]), Path(sys.argv[2]))
    print(f"{len(files)} snimki: {', '.join(files)}")
