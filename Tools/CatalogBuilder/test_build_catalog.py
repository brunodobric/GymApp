"""Testovi logike pretvorbe u build_catalog.py. Pokretanje: python3 -m unittest discover -s Tools/CatalogBuilder"""
import json
import unittest
from pathlib import Path

import build_catalog as bc

TOOL = Path(__file__).resolve().parent
MAPPING = json.loads((TOOL / "mapping.json").read_text(encoding="utf-8"))


def raw(**overrides):
    base = {
        "id": "Test_Exercise", "name": "Test Exercise", "force": "push", "level": "beginner",
        "mechanic": "compound", "equipment": "barbell", "primaryMuscles": ["chest"],
        "secondaryMuscles": ["triceps", "shoulders"], "instructions": ["Korak 1."], "category": "strength",
        "images": ["Test_Exercise/0.jpg", "Test_Exercise/1.jpg"],
    }
    base.update(overrides)
    return base


class ConvertTests(unittest.TestCase):
    def test_basic_mapping(self):
        result = bc.convert(raw(), MAPPING, {})
        self.assertEqual(result["category"], "chest")
        self.assertEqual(result["movement"], "push")
        self.assertEqual(result["inputType"], "weightReps")
        self.assertEqual(result["primaryRegions"], ["chest"])
        self.assertEqual(result["secondaryRegions"], ["triceps", "shoulders"])
        self.assertEqual(result["images"], ["Images/Test_Exercise/0.jpg", "Images/Test_Exercise/1.jpg"])

    def test_bodyweight_equipment_gives_bodyweight_input(self):
        result = bc.convert(raw(equipment="body only"), MAPPING, {})
        self.assertEqual(result["equipment"], "bodyweight")
        self.assertEqual(result["inputType"], "bodyweight")

    def test_cardio(self):
        result = bc.convert(raw(category="cardio", primaryMuscles=["quadriceps"], equipment="machine"), MAPPING, {})
        self.assertEqual(result["category"], "cardio")
        self.assertIsNone(result["movement"])
        self.assertEqual(result["inputType"], "durationDistance")

    def test_null_equipment_and_mechanic(self):
        result = bc.convert(raw(equipment=None, mechanic=None), MAPPING, {})
        self.assertEqual(result["equipment"], "other")
        self.assertIsNone(result["mechanic"])

    def test_overrides(self):
        result = bc.convert(raw(id="Plank", primaryMuscles=["abdominals"], equipment="body only"), MAPPING, {})
        self.assertEqual(result["inputType"], "duration")

    def test_expert_level_becomes_advanced(self):
        self.assertEqual(bc.convert(raw(level="expert"), MAPPING, {})["level"], "advanced")

    def test_translation_is_merged(self):
        result = bc.convert(raw(), MAPPING, {"Test_Exercise": {"name": "Testna vježba"}})
        self.assertEqual(result["name"], {"en": "Test Exercise", "hr": "Testna vježba"})
        self.assertNotIn("hr", result["instructions"])

    def test_unknown_values_fail_loudly(self):
        with self.assertRaises(bc.BuildError):
            bc.convert(raw(primaryMuscles=["nepoznat"]), MAPPING, {})
        with self.assertRaises(bc.BuildError):
            bc.convert(raw(equipment="nepoznata"), MAPPING, {})


class SelectionTests(unittest.TestCase):
    def test_selection_has_no_duplicates_and_expected_size(self):
        ids = bc.load_selection(TOOL / "selection.txt")
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue(150 <= len(ids) <= 200)


ROOT = TOOL.parents[1]
DRAWINGS = ROOT / "Resources" / "Drawings" / "Drawings.xcassets"

SAMPLE_SVG = (
    '<svg width="167pt" height="175pt" viewBox="0 0 167 175" xmlns="http://www.w3.org/2000/svg">'
    '<g fill="#FFF"><path d="M0 0h167v175H0z"/></g><g fill="#333"><path d="M1 1h2v2H1z"/></g></svg>'
)


def everkinetic_entry(source_id, poses=("relaxation", "tension")):
    return {"id": source_id, "svg": [f"svg/{source_id}-{pose}.svg" for pose in poses]}


class DrawingMapTests(unittest.TestCase):
    def test_every_mapped_exercise_is_selected_and_has_drawings_in_repo(self):
        drawing_map = bc.load_drawing_map(TOOL / "everkinetic.json")
        selection = bc.load_selection(TOOL / "selection.txt")
        self.assertGreaterEqual(len(drawing_map), 80)
        # Svaki Everkinetic id iz tablice postoji u Everkineticu: builder ga je preuzeo i upisao u asset catalog.
        everkinetic = {source_id: everkinetic_entry(source_id) for source_id in drawing_map.values()}
        bc.validate_drawing_map(drawing_map, selection, everkinetic)
        for source_id in set(drawing_map.values()):
            for name in bc.drawing_names(source_id):
                self.assertTrue((DRAWINGS / f"{name}.imageset" / f"{name}.svg").exists(), name)
                self.assertTrue((DRAWINGS / f"{name}.imageset" / "Contents.json").exists(), name)

    def test_catalog_lists_drawings_only_for_mapped_exercises(self):
        drawing_map = bc.load_drawing_map(TOOL / "everkinetic.json")
        catalog = json.loads((ROOT / "Resources" / "Catalog" / "catalog.json").read_text(encoding="utf-8"))
        for exercise in catalog["exercises"]:
            source_id = drawing_map.get(exercise["id"])
            if source_id:
                self.assertEqual(exercise["drawings"], bc.drawing_names(source_id))
            else:
                self.assertNotIn("drawings", exercise)
                self.assertTrue(exercise["images"], exercise["id"])
        self.assertEqual(catalog["drawingsSource"]["license"], "CC BY-SA 4.0")

    def test_no_stale_drawings_in_asset_catalog(self):
        drawing_map = bc.load_drawing_map(TOOL / "everkinetic.json")
        wanted = {name for source_id in drawing_map.values() for name in bc.drawing_names(source_id)}
        present = {folder.stem for folder in DRAWINGS.glob("*.imageset")}
        self.assertEqual(present, wanted)

    def test_duplicate_catalog_id_fails(self):
        import tempfile

        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "everkinetic.json"
            path.write_text('{"exercises": {"Pushups": "0077", "Pushups": "0075"}}', encoding="utf-8")
            with self.assertRaises(bc.BuildError):
                bc.load_drawing_map(path)

    def test_validation_fails_for_unknown_or_incomplete_source(self):
        selection = ["Pushups", "Barbell_Squat"]
        with self.assertRaises(bc.BuildError):
            bc.validate_drawing_map({"Pushups": "9999"}, selection, {"0077": everkinetic_entry("0077")})
        with self.assertRaises(bc.BuildError):
            bc.validate_drawing_map({"Pushups": "0077"}, selection, {"0077": everkinetic_entry("0077", ("tension",))})
        with self.assertRaises(bc.BuildError):
            bc.validate_drawing_map({"Nije_Odabrana": "0077"}, selection, {"0077": everkinetic_entry("0077")})
        bc.validate_drawing_map({"Pushups": "0077"}, selection, {"0077": everkinetic_entry("0077")})

    def test_clean_svg_removes_white_background(self):
        cleaned = bc.clean_svg(SAMPLE_SVG)
        self.assertNotIn("#FFF", cleaned)
        self.assertNotIn("M0 0h167v175H0z", cleaned)
        self.assertIn('<g fill="#000"><path d="M1 1h2v2H1z"/></g>', cleaned)
        self.assertIn('width="167" height="175" viewBox="0 0 167 175"', cleaned)

    def test_clean_svg_handles_lowercase_white_and_rejects_broken_input(self):
        cleaned = bc.clean_svg(SAMPLE_SVG.replace("#FFF", "#fff").replace("#333", "#2e2e2c"))
        self.assertEqual(cleaned.count("<g "), 1)
        self.assertIn('fill="#000"', cleaned)
        with self.assertRaises(bc.BuildError):
            bc.clean_svg("<svg></svg>")
        with self.assertRaises(bc.BuildError):
            bc.clean_svg('<svg viewBox="0 0 1 1"><g fill="#FFF"><path d="M0 0"/></g></svg>')

    def test_committed_drawings_are_cleaned_template_vectors(self):
        for folder in list(DRAWINGS.glob("*.imageset"))[:20]:
            svg = (folder / f"{folder.stem}.svg").read_text(encoding="utf-8")
            self.assertNotIn('fill="#FFF"', svg)
            self.assertNotIn('fill="#fff"', svg)
            contents = json.loads((folder / "Contents.json").read_text(encoding="utf-8"))
            self.assertEqual(contents["properties"]["template-rendering-intent"], "template")
            self.assertTrue(contents["properties"]["preserves-vector-representation"])


if __name__ == "__main__":
    unittest.main()
