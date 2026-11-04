#!/usr/bin/env python3
"""Gradi katalog vježbi iz free-exercise-db (Unlicense) za aplikaciju.

Koraci: preuzme fiksiranu verziju baze, odabere vježbe iz selection.txt, primijeni mapping.json,
spoji prijevode iz translations/hr.json te upiše Resources/Catalog/catalog.json i slike.
Za vježbe iz everkinetic.json preuzme i crteže iz Everkinetica (CC BY-SA 4.0), ukloni im bijelu
pozadinu i upiše ih u Resources/Drawings/Drawings.xcassets kao vektorske template slike.
Samo standardna biblioteka Pythona, bez vanjskih ovisnosti.

Pokretanje (iz korijena repozitorija):  python3 Tools/CatalogBuilder/build_catalog.py
"""
import argparse
import json
import re
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

# Crteži vježbi: everkinetic/data, CC BY-SA 4.0. Isto kao gore, commit je fiksiran.
DRAWINGS_COMMIT = "446bb9a3d0c3beb6b84f7c9d77dfc8af707a2ab6"
DRAWINGS_REPO = "everkinetic/data"
DRAWINGS_RAW = f"https://raw.githubusercontent.com/{DRAWINGS_REPO}/{DRAWINGS_COMMIT}"
# Everkinetic naziva položaje "relaxation" (početni) i "tension" (završni).
DRAWING_POSES = (("relaxation", "start"), ("tension", "end"))

ROOT = Path(__file__).resolve().parents[2]
TOOL = Path(__file__).resolve().parent
OUTPUT = ROOT / "Resources" / "Catalog"
CACHE = TOOL / ".cache"
DRAWINGS_OUTPUT = ROOT / "Resources" / "Drawings" / "Drawings.xcassets"


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


def load_drawing_map(path: Path) -> dict[str, str]:
    """Čita everkinetic.json (naš id → Everkinetic id) i ne dopušta isti naš id dvaput."""

    def no_duplicates(pairs):
        keys = [key for key, _ in pairs]
        duplicates = sorted({key for key in keys if keys.count(key) > 1})
        if duplicates:
            raise BuildError(f"Duplicirani id-evi u everkinetic.json: {duplicates}")
        return dict(pairs)

    data = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=no_duplicates)
    return data["exercises"]


def validate_drawing_map(drawing_map: dict[str, str], selection: list[str], everkinetic: dict) -> None:
    """Svaki naš id mora biti u odabiru, a svaki Everkinetic id mora postojati i imati oba crteža."""
    not_selected = sorted(i for i in drawing_map if i not in selection)
    if not_selected:
        raise BuildError(f"everkinetic.json ima vježbe koje nisu u selection.txt: {not_selected}")
    for exercise_id, source_id in drawing_map.items():
        source = everkinetic.get(source_id)
        if source is None:
            raise BuildError(f"{exercise_id}: Everkinetic nema vježbu '{source_id}'")
        expected = {f"svg/{source_id}-{pose}.svg" for pose, _ in DRAWING_POSES}
        if not expected <= set(source.get("svg", [])):
            raise BuildError(f"{exercise_id}: Everkinetic vježba '{source_id}' nema oba crteža")


def drawing_asset_name(source_id: str, pose: str) -> str:
    """Naziv slike u asset catalogu, npr. "Everkinetic-0042-start"."""
    return f"Everkinetic-{source_id}-{pose}"


def drawing_names(source_id: str) -> list[str]:
    """Početni pa završni položaj, redoslijedom kojim ih aplikacija izmjenjuje."""
    return [drawing_asset_name(source_id, pose) for _, pose in DRAWING_POSES]


WHITE = {"#fff", "#ffffff", "white"}


def clean_svg(svg: str) -> str:
    """Izmjena crteža: uklanja bijelu pozadinu, linije boji crnom (aplikacija ih boji bojom teme)
    i postavlja veličinu prema viewBoxu. Everkinetic SVG ima jednu bijelu i jednu tamnu grupu."""

    view_box = re.search(r'viewBox="([^"]+)"', svg)
    if not view_box:
        raise BuildError("SVG nema viewBox")
    _, _, width, height = view_box.group(1).split()
    groups = re.findall(r'<g fill="([^"]+)">(.*?)</g>', svg, flags=re.S)
    if not groups:
        raise BuildError("SVG nema grupe s ispunom")
    lines = [body for fill, body in groups if fill.lower() not in WHITE]
    if not lines:
        raise BuildError("SVG ima samo bijele grupe")
    return (
        f'<svg width="{width}" height="{height}" viewBox="{view_box.group(1)}" xmlns="http://www.w3.org/2000/svg">'
        + "".join(f'<g fill="#000">{body}</g>' for body in lines)
        + "</svg>\n"
    )


def imageset_contents(filename: str) -> dict:
    """Contents.json za vektorsku template sliku: iOS je crta kao vektor i boji bojom prednjeg plana."""
    return {
        "images": [{"filename": filename, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
    }


def write_drawings(drawing_map: dict[str, str], source_dir: Path, output: Path) -> None:
    """Upisuje izmijenjene crteže u asset catalog i briše one koji više nisu mapirani."""
    output.mkdir(parents=True, exist_ok=True)
    (output / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8"
    )
    wanted = set()
    for source_id in sorted(set(drawing_map.values())):
        for source_pose, pose in DRAWING_POSES:
            name = drawing_asset_name(source_id, pose)
            wanted.add(name)
            folder = output / f"{name}.imageset"
            folder.mkdir(exist_ok=True)
            svg = (source_dir / f"{source_id}-{source_pose}.svg").read_text(encoding="utf-8")
            (folder / f"{name}.svg").write_text(clean_svg(svg), encoding="utf-8")
            (folder / "Contents.json").write_text(
                json.dumps(imageset_contents(f"{name}.svg"), indent=2) + "\n", encoding="utf-8"
            )
    for folder in output.glob("*.imageset"):
        if folder.stem not in wanted:
            for file in folder.iterdir():
                file.unlink()
            folder.rmdir()


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

    drawing_map = load_drawing_map(TOOL / "everkinetic.json")
    drawings_cache = CACHE / f"everkinetic-{DRAWINGS_COMMIT}"
    if not args.source:
        print("Preuzimam Everkinetic exercises.json …")
        download(f"{DRAWINGS_RAW}/dist/exercises.json", drawings_cache / "exercises.json")
        everkinetic = {item["id"]: item for item in json.loads((drawings_cache / "exercises.json").read_text(encoding="utf-8"))}
        validate_drawing_map(drawing_map, selection, everkinetic)
    for exercise in exercises:
        source_id = drawing_map.get(exercise["id"])
        if source_id:
            exercise["drawings"] = drawing_names(source_id)
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

    # Crteži se preuzimaju i pišu samo uz pravi izvor (bez --source), da testni build ne dira asset catalog.
    if not args.no_images and not args.source:
        drawing_jobs = []
        for source_id in sorted(set(drawing_map.values())):
            for source_pose, _ in DRAWING_POSES:
                name = f"{source_id}-{source_pose}.svg"
                drawing_jobs.append((f"{DRAWINGS_RAW}/dist/svg/{name}", drawings_cache / "svg" / name))
        print(f"Preuzimam {len(drawing_jobs)} crteža …")
        with ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda job: download(*job), drawing_jobs))
        write_drawings(drawing_map, drawings_cache / "svg", DRAWINGS_OUTPUT)

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
        "drawingsSource": {
            "name": "Everkinetic", "repository": DRAWINGS_REPO, "commit": DRAWINGS_COMMIT, "license": "CC BY-SA 4.0",
        },
        "exercises": exercises,
    }
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "catalog.json").write_text(
        json.dumps(catalog, ensure_ascii=False, indent=1, sort_keys=False) + "\n", encoding="utf-8"
    )

    translated = sum(1 for e in exercises if "hr" in e["name"])
    with_steps = sum(1 for e in exercises if "hr" in e["instructions"])
    drawn = sum(1 for e in exercises if "drawings" in e)
    print(
        f"Gotovo: {len(exercises)} vježbi, {translated} s hrvatskim nazivom, {with_steps} s hrvatskim uputama, "
        f"{drawn} s crtežima."
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BuildError as error:
        print(f"GREŠKA: {error}", file=sys.stderr)
        sys.exit(1)
