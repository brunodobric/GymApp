#!/usr/bin/env python3
"""Gradi katalog vježbi iz free-exercise-db (Unlicense) za aplikaciju.

Koraci: preuzme fiksiranu verziju baze, odabere vježbe iz selection.txt, primijeni mapping.json,
spoji prijevode iz translations/hr.json te upiše Resources/Catalog/catalog.json i slike.
Samo standardna biblioteka Pythona, bez vanjskih ovisnosti.

Pokretanje (iz korijena repozitorija):  python3 Tools/CatalogBuilder/build_catalog.py
"""
import argparse
import json
import sys
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

# Fiksirana verzija izvora: promjena ove vrijednosti je namjerna odluka o ažuriranju kataloga.
SOURCE_COMMIT = "f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5"
SOURCE_REPO = "yuhonas/free-exercise-db"
RAW = f"https://raw.githubusercontent.com/{SOURCE_REPO}/{SOURCE_COMMIT}"
CATALOG_VERSION = 1

ROOT = Path(__file__).resolve().parents[2]
TOOL = Path(__file__).resolve().parent
OUTPUT = ROOT / "Resources" / "Catalog"
CACHE = TOOL / ".cache"


class BuildError(Exception):
    pass


def load_selection(path: Path) -> list[str]:
    ids = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            ids.append(line)
    duplicates = {i for i in ids if ids.count(i) > 1}
    if duplicates:
        raise BuildError(f"Duplicirani id-evi u selection.txt: {sorted(duplicates)}")
    return ids


def lookup(table: dict, value, what: str, exercise_id: str):
    key = "null" if value is None else value
    if key not in table:
        raise BuildError(f"{exercise_id}: nema mapiranja za {what} '{value}' u mapping.json")
    return table[key]


def regions_for(muscles: list[str], mapping: dict, exercise_id: str) -> list[str]:
    regions = []
    for muscle in muscles:
        if muscle not in mapping["muscles"]:
            raise BuildError(f"{exercise_id}: nema mapiranja za mišić '{muscle}'")
        region = mapping["muscles"][muscle]["region"]
        if region not in regions:
            regions.append(region)
    return regions


def convert(raw: dict, mapping: dict, hr: dict) -> dict:
    """Pretvara jedan zapis iz izvora u zapis kataloga. Čista funkcija, pokrivena testovima."""
    exercise_id = raw["id"]
    primary = raw["primaryMuscles"]
    secondary = raw["secondaryMuscles"]
    if not primary:
        raise BuildError(f"{exercise_id}: nema primarnog mišića")
    lead = mapping["muscles"].get(primary[0])
    if lead is None:
        raise BuildError(f"{exercise_id}: nema mapiranja za mišić '{primary[0]}'")

    is_cardio = raw["category"] == "cardio"
    category = "cardio" if is_cardio else lead["category"]
    category = mapping["categoryOverrides"].get(exercise_id, category)
    movement = None if is_cardio else lead["movement"]

    equipment = mapping["equipmentOverrides"].get(exercise_id) or lookup(
        mapping["equipment"], raw["equipment"], "opremu", exercise_id
    )

    if exercise_id in mapping["inputTypeOverrides"]:
        input_type = mapping["inputTypeOverrides"][exercise_id]
    elif is_cardio:
        input_type = mapping["cardioInputType"]
    elif equipment == "bodyweight":
        input_type = "bodyweight"
    else:
        input_type = "weightReps"

    names = {"en": raw["name"]}
    instructions = {"en": raw["instructions"]}
    translation = hr.get(exercise_id)
    if translation:
        names["hr"] = translation["name"]
        if translation.get("instructions"):
            instructions["hr"] = translation["instructions"]

    return {
        "id": exercise_id,
        "name": names,
        "instructions": instructions,
        "category": category,
        "primaryMuscles": primary,
        "secondaryMuscles": secondary,
        "equipment": equipment,
        "level": lookup(mapping["levels"], raw["level"], "razinu", exercise_id),
        "mechanic": lookup(mapping["mechanics"], raw["mechanic"], "mehaniku", exercise_id),
        "movement": movement,
        "inputType": input_type,
        "primaryRegions": regions_for(primary, mapping, exercise_id),
        "secondaryRegions": regions_for(secondary, mapping, exercise_id),
        "images": [f"Images/{exercise_id}/{Path(image).name}" for image in raw.get("images", [])],
    }


def download(url: str, destination: Path) -> None:
    if destination.exists():
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "gymapp-catalog-builder"})
    with urllib.request.urlopen(request, timeout=60) as response:
        destination.write_bytes(response.read())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="lokalni exercises.json umjesto preuzimanja (za testove)")
    parser.add_argument("--no-images", action="store_true", help="preskoči preuzimanje slika")
    args = parser.parse_args()

    selection = load_selection(TOOL / "selection.txt")
    mapping = json.loads((TOOL / "mapping.json").read_text(encoding="utf-8"))
    hr_path = TOOL / "translations" / "hr.json"
    hr = json.loads(hr_path.read_text(encoding="utf-8")) if hr_path.exists() else {}

    source_file = args.source or CACHE / SOURCE_COMMIT / "exercises.json"
    if not args.source:
        print("Preuzimam exercises.json …")
        download(f"{RAW}/dist/exercises.json", source_file)
    database = {item["id"]: item for item in json.loads(source_file.read_text(encoding="utf-8"))}

    missing = [i for i in selection if i not in database]
    if missing:
        raise BuildError(f"Nema u izvoru: {missing}")
    unknown_translations = [i for i in hr if i not in selection]
    if unknown_translations:
        raise BuildError(f"Prijevodi za vježbe koje nisu odabrane: {unknown_translations}")

    exercises = [convert(database[i], mapping, hr) for i in selection]

    for exercise in exercises:
        if not exercise["instructions"]["en"]:
            raise BuildError(f"{exercise['id']}: nema uputa, izbaciti iz selection.txt")
        if not exercise["images"]:
            raise BuildError(f"{exercise['id']}: nema slika, izbaciti iz selection.txt")

    if not args.no_images:
        jobs = []
        for raw_id in selection:
            for image in database[raw_id].get("images", []):
                quoted = urllib.parse.quote(image)
                jobs.append((f"{RAW}/exercises/{quoted}", OUTPUT / "Images" / raw_id / Path(image).name))
        print(f"Preuzimam {len(jobs)} slika …")
        with ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda job: download(*job), jobs))

    # Mape slika vježbi koje više nisu u odabiru brišu se, da build uvijek odgovara selection.txt.
    images_root = OUTPUT / "Images"
    if images_root.exists():
        for folder in images_root.iterdir():
            if folder.is_dir() and folder.name not in selection:
                for file in folder.iterdir():
                    file.unlink()
                folder.rmdir()

    catalog = {
        "version": CATALOG_VERSION,
        "source": {"name": "free-exercise-db", "repository": SOURCE_REPO, "commit": SOURCE_COMMIT, "license": "Unlicense"},
        "exercises": exercises,
    }
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "catalog.json").write_text(
        json.dumps(catalog, ensure_ascii=False, indent=1, sort_keys=False) + "\n", encoding="utf-8"
    )

    translated = sum(1 for e in exercises if "hr" in e["name"])
    with_steps = sum(1 for e in exercises if "hr" in e["instructions"])
    print(
        f"Gotovo: {len(exercises)} vježbi, {translated} s hrvatskim nazivom, {with_steps} s hrvatskim uputama."
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BuildError as error:
        print(f"GREŠKA: {error}", file=sys.stderr)
        sys.exit(1)
