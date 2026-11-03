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


def bounds_of(shapes: list) -> list:
    """Granice (x0, y0, x1, y1) svih točaka u putanjama; sve su naredbe apsolutne."""
    xs, ys = [], []
    for shape in shapes:
        numbers = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", shape["d"])]
        xs += numbers[0::2]
        ys += numbers[1::2]
    return [min(xs), min(ys), max(xs), max(ys)]


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
            "bounds": bounds_of(outline), "outline": outline, "muscles": muscles}


def main() -> None:
    source_dir, target = Path(sys.argv[1]), Path(sys.argv[2])
    result = {name: convert(source_dir / file) for name, file in DIAGRAMS.items()}
    # Prednja i stražnja strana istog spola dijele okvir, pa su figure iste veličine.
    margin = 12.0
    for sex in ("male", "female"):
        pair = [result[f"{sex}-front"], result[f"{sex}-back"]]
        x0 = min(d["bounds"][0] for d in pair) - margin
        y0 = min(d["bounds"][1] for d in pair) - margin
        x1 = max(d["bounds"][2] for d in pair) + margin
        y1 = max(d["bounds"][3] for d in pair) + margin
        for diagram in pair:
            diagram["bounds"] = [round(x0, 1), round(y0, 1), round(x1 - x0, 1), round(y1 - y0, 1)]
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, separators=(",", ":")), encoding="utf-8")
    for name, diagram in result.items():
        print(name, len(diagram["outline"]), "obrisa,", len(diagram["muscles"]), "mišića")


if __name__ == "__main__":
    main()
