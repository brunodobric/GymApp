#!/usr/bin/env python3
"""Gradi katalog vježbi iz MoveKit paketa (komercijalna licenca, docs/movekit.md).

MoveKit sadržaj ne smije u javni repozitorij, pa build ima dva izlaza:

* javni `Resources/Catalog/catalog.json`: naši podaci o vježbama (id, nazivi, kategorija, vrsta, mišići,
  oprema, vrsta unosa, regije mape mišića). Bez MoveKit tekstova i medija.
* privatna mapa (zadano `<MoveKit paket>/GymApp`): `texts.json` s uputama i čestim greškama te
  `Media/` s pretvorenim klipovima (HEVC) i posterima (JPEG). `scripts/movekit.sh` je kopira u
  `Resources/MoveKit/`, koja je u .gitignore i ulazi u build samo na Macu s paketom.

Ulazi u repozitoriju: mapping.json (pravila), overrides.json (ispravke po vježbi), names-hr.json
(hrvatski nazivi). Hrvatski prijevodi uputa su privatni: `<privatna mapa>/translations-hr.json`.

Pokretanje (iz korijena repozitorija, za medije treba ffmpeg):
    python3 Tools/CatalogBuilder/build_catalog.py --movekit ~/Documents/MoveKit [--media]
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

CATALOG_VERSION = 2
SOURCE = {"name": "MoveKit", "url": "https://movekit.com", "license": "MoveKit License Agreement v1.0"}

ROOT = Path(__file__).resolve().parents[2]
TOOL = Path(__file__).resolve().parent
PUBLIC_OUTPUT = ROOT / "Resources" / "Catalog" / "catalog.json"

# Pretvorba medija: klip 1280 px širine u HEVC bez zvuka, poster 960 px u JPEG.
VIDEO_WIDTH = 1280
VIDEO_CRF = 28
POSTER_WIDTH = 960


class BuildError(Exception):
    pass


def load_json(path: Path, default=None):
    if not path.exists():
        if default is not None:
            return default
        raise BuildError(f"Nema datoteke {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def unique(items: list) -> list:
    result = []
    for item in items:
        if item not in result:
            result.append(item)
    return result


def map_muscles(names: list[str], exercise_name: str, mapping: dict, slug: str) -> list[str]:
    lowered = exercise_name.lower()
    result = []
    for name in names:
        if name not in mapping["muscles"]:
            raise BuildError(f"{slug}: nema mapiranja za mišić '{name}'")
        muscles = mapping["muscles"][name]
        if name == "Back":
            for rule in mapping["backRules"]:
                if any(word in lowered for word in rule["words"]):
                    muscles = rule["muscles"]
                    break
        result.extend(muscles)
    return unique(result)


def map_equipment(names: list[str], mapping: dict, slug: str) -> str:
    candidates = [n for n in names if n not in mapping["equipmentIgnore"]] or names
    if not candidates:
        return "other"
    first = candidates[0]
    if first not in mapping["equipment"]:
        raise BuildError(f"{slug}: nema mapiranja za opremu '{first}'")
    return mapping["equipment"][first]


def infer_input_type(raw: dict, equipment: str, mapping: dict) -> str:
    name = raw["name"].lower()
    patterns = set(raw["movementPattern"])
    if "Cardio" in patterns:
        if any(word in name for word in mapping["distanceCardioWords"]):
            return "durationDistance"
        return "duration"
    if patterns & {"Mobility", "Stretch"}:
        return "duration"
    if any(word in name for word in mapping["durationWords"]):
        return "duration"
    if "assisted" in name and ("pull" in name or "dip" in name or "chin" in name):
        return "assisted"
    if "weighted" in name and ("pull" in name or "dip" in name or "chin" in name):
        return "weightedBodyweight"
    if equipment == "bodyweight":
        return "bodyweight"
    return "weightReps"


def infer_kind(slug: str, patterns: list[str], category: str, mapping: dict) -> str:
    """Vrsta vježbe (snaga, kardio, zagrijavanje, istezanje) iz obrazaca pokreta. Kardio prati kategoriju."""
    if category == "cardio":
        return "cardio"
    rules = mapping["kinds"]
    if set(patterns) & set(rules["stretchingPatterns"]) or any(w in slug for w in rules["stretchingWords"]):
        return "stretching"
    if set(patterns) & set(rules["warmUpPatterns"]):
        return "warmUp"
    return "strength"


def regions_for(muscles: list[str], mapping: dict, slug: str) -> list[str]:
    regions = []
    for muscle in muscles:
        if muscle not in mapping["regions"]:
            raise BuildError(f"{slug}: nema regije za mišić '{muscle}'")
        regions.append(mapping["regions"][muscle])
    return unique(regions)


def convert(raw: dict, mapping: dict, override: dict, hr_name: str | None) -> dict:
    """Pretvara jedan zapis iz metadata.json u javni zapis kataloga. Čista funkcija, pokrivena testovima."""
    slug = raw["slug"]
    if not raw["primaryMuscles"] and "primaryMuscles" not in override:
        raise BuildError(f"{slug}: nema glavnog mišića")
    primary = override.get("primaryMuscles") or map_muscles(raw["primaryMuscles"], raw["name"], mapping, slug)
    secondary = override.get("secondaryMuscles")
    if secondary is None:
        secondary = map_muscles(raw["secondaryMuscles"], raw["name"], mapping, slug)
    secondary = [m for m in secondary if m not in primary]

    patterns = raw["movementPattern"]
    is_cardio = "Cardio" in patterns
    category = override.get("category") or ("cardio" if is_cardio else mapping["category"][primary[0]])
    kind = override.get("kind") or infer_kind(slug, patterns, category, mapping)

    movement = None
    if not is_cardio:
        movement = next((mapping["movement"][p] for p in patterns if p in mapping["movement"]), None)
    movement = override.get("movement", movement)

    if "Isolation" in patterns:
        mechanic = "isolation"
    elif set(patterns) & set(mapping["noMechanic"]):
        mechanic = None
    else:
        mechanic = "compound"

    equipment = override.get("equipment") or map_equipment(raw["equipment"], mapping, slug)
    input_type = override.get("inputType") or infer_input_type(raw, equipment, mapping)

    level = mapping["levels"].get(raw["difficulty"])
    if level is None:
        raise BuildError(f"{slug}: nepoznata razina '{raw['difficulty']}'")

    names = {"en": raw["name"]}
    if hr_name:
        names["hr"] = hr_name

    return {
        "id": slug,
        "name": names,
        "category": category,
        "kind": kind,
        "primaryMuscles": primary,
        "secondaryMuscles": secondary,
        "equipment": equipment,
        "level": level,
        "mechanic": mechanic,
        "movement": movement,
        "inputType": input_type,
        "primaryRegions": regions_for(primary, mapping, slug),
        "secondaryRegions": regions_for(secondary, mapping, slug),
        "video": f"Media/{slug}.mp4",
        "poster": f"Media/{slug}.jpg",
    }


def texts_for(raw: dict, hr: dict | None) -> dict:
    """Privatni tekstovi jedne vježbe: upute i česte greške, engleski i (ako postoji) hrvatski."""
    instructions = {"en": raw["instructions"]}
    mistakes = {"en": raw["commonMistakes"]}
    if hr:
        if hr.get("instructions"):
            instructions["hr"] = hr["instructions"]
        if hr.get("commonMistakes"):
            mistakes["hr"] = hr["commonMistakes"]
    return {"instructions": instructions, "commonMistakes": mistakes}


def find_media(package: Path, relative: str) -> Path:
    """Datoteka iz paketa: MoveKit isporučuje klipove i postere u zasebnim mapama."""
    name = Path(relative).name
    matches = sorted(package.glob(f"*/{relative}")) + sorted(package.glob(f"*/{name}"))
    if not matches:
        raise BuildError(f"Nema datoteke {relative} u {package}")
    return matches[0]


def convert_media(source_video: Path, source_poster: Path, out: Path, slug: str) -> None:
    """Klip u HEVC 1280 px bez zvuka i poster u JPEG 960 px. Gotova datoteka novija od izvora se preskače,
    a pretvorba ide u privremenu datoteku, pa prekinuto pokretanje ne ostavlja napola zapisan klip."""
    jobs = (
        (source_video, out / f"{slug}.mp4",
         ["-an", "-vf", f"scale={VIDEO_WIDTH}:-2", "-c:v", "libx265", "-crf", str(VIDEO_CRF), "-preset", "medium",
          "-tag:v", "hvc1", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-x265-params", "log-level=error"]),
        (source_poster, out / f"{slug}.jpg", ["-vf", f"scale={POSTER_WIDTH}:-2", "-q:v", "4"]),
    )
    for source, target, options in jobs:
        if target.exists() and target.stat().st_size > 0 and target.stat().st_mtime >= source.stat().st_mtime:
            continue
        temporary = target.with_name(f".tmp-{target.name}")
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(source), *options, str(temporary)], check=True)
        temporary.replace(target)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--movekit", type=Path, required=True, help="mapa s raspakiranim MoveKit paketom")
    parser.add_argument("--private-out", type=Path, help="privatni izlaz (zadano <movekit>/GymApp)")
    parser.add_argument("--media", action="store_true", help="pretvori klipove i postere (treba ffmpeg)")
    parser.add_argument("--no-public", action="store_true", help="ne piši Resources/Catalog/catalog.json")
    args = parser.parse_args()

    package = args.movekit.expanduser()
    private = (args.private_out or package / "GymApp").expanduser()
    metadata_files = sorted(package.glob("*/metadata.json"))
    if not metadata_files:
        raise BuildError(f"Nema metadata.json u {package}")
    metadata = load_json(metadata_files[0])

    mapping = load_json(TOOL / "mapping.json")
    overrides = load_json(TOOL / "overrides.json", {})
    hr_names = load_json(TOOL / "names-hr.json", {})
    hr_texts = load_json(private / "translations-hr.json", {})

    slugs = {raw["slug"] for raw in metadata}
    for table, label in ((overrides, "overrides.json"), (hr_names, "names-hr.json"), (hr_texts, "translations-hr.json")):
        unknown = sorted(k for k in table if not k.startswith("_") and k not in slugs)
        if unknown:
            raise BuildError(f"{label}: nepoznate vježbe {unknown}")

    exercises = [convert(raw, mapping, overrides.get(raw["slug"], {}), hr_names.get(raw["slug"])) for raw in metadata]
    exercises.sort(key=lambda e: e["name"]["en"].lower())

    if not args.no_public:
        catalog = {
            "version": CATALOG_VERSION,
            "source": SOURCE,
            "exercises": exercises,
        }
        PUBLIC_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        PUBLIC_OUTPUT.write_text(json.dumps(catalog, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    private.mkdir(parents=True, exist_ok=True)
    texts = {raw["slug"]: texts_for(raw, hr_texts.get(raw["slug"])) for raw in metadata}
    (private / "texts.json").write_text(json.dumps(texts, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    if args.media:
        if shutil.which("ffmpeg") is None:
            raise BuildError("Za --media treba ffmpeg (brew install ffmpeg).")
        media = private / "Media"
        media.mkdir(parents=True, exist_ok=True)
        jobs = [
            (find_media(package, raw["videoFile"]), find_media(package, raw["posterFile"]), media, raw["slug"])
            for raw in metadata
        ]
        print(f"Pretvaram {len(jobs)} klipova i postera …")
        with ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(lambda job: convert_media(*job), jobs))

    named = sum(1 for e in exercises if "hr" in e["name"])
    print(f"Gotovo: {len(exercises)} vježbi, {named} s hrvatskim nazivom, {len(hr_texts)} s hrvatskim uputama.")
    print(f"Privatni izlaz: {private}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BuildError as error:
        print(f"GREŠKA: {error}", file=sys.stderr)
        sys.exit(1)
