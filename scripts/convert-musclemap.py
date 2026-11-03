#!/usr/bin/env python3
"""Pretvara SVG putanje mišića iz MuscleMap repozitorija (MIT) u jedan JSON resurs za aplikaciju.

Samo čita tekst TypeScript datoteka (ne izvršava ih). Upotreba:
    python3 scripts/convert-musclemap.py <putanja do MuscleMap/packages/assets/src> Resources/BodyMap/body.json
"""
import json
import re
import sys
from pathlib import Path

DIAGRAMS = {
    "male-front": "male-front.ts",
    "male-back": "male-back.ts",
    "female-front": "female-front.ts",
    "female-back": "female-back.ts",
}

ENTRY = re.compile(r'^\s*\{(.*)\},?\s*$')
FIELD = re.compile(r'(\w+): "([^"]*)"')


def entries(block: str):
    for line in block.splitlines():
        match = ENTRY.match(line)
        if match:
            yield dict(FIELD.findall(match.group(1)))


def section(text: str, name: str) -> str:
    start = text.index(f"const {name}")
    return text[text.index("\n", start):text.index("\n];", start)]


def convert(source: Path) -> dict:
    text = source.read_text(encoding="utf-8")
    view_box = re.search(r'viewBox: "([^"]+)"', text).group(1)
    center_x = float(re.search(r"centerX: ([0-9.]+)", text).group(1))
    outline = [
        {"id": e["id"], "side": e["side"], "d": e["d"]} for e in entries(section(text, "OUTLINE"))
    ]
    muscles = [
        {"id": e.get("id", ""), "group": e["group"], "side": e["side"], "d": e["d"]}
        for e in entries(section(text, "MUSCLES"))
    ]
    allowed = set("MLCZ0123456789.- ,")
    for item in outline + muscles:
        if not set(item["d"]) <= allowed:
            raise SystemExit(f"Neočekivana naredba u putanji {item['id']}")
    return {"viewBox": [float(v) for v in view_box.split()], "centerX": center_x,
            "outline": outline, "muscles": muscles}


def main() -> None:
    source_dir, target = Path(sys.argv[1]), Path(sys.argv[2])
    result = {name: convert(source_dir / file) for name, file in DIAGRAMS.items()}
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, separators=(",", ":")), encoding="utf-8")
    for name, diagram in result.items():
        print(name, len(diagram["outline"]), "obrisa,", len(diagram["muscles"]), "mišića")


if __name__ == "__main__":
    main()
