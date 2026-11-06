"""Testovi pretvorbe MoveKit metapodataka u build_catalog.py i dosljednosti javnih datoteka.

Pokretanje: python3 -m unittest discover -s Tools/CatalogBuilder
Testovi ne trebaju MoveKit paket: zapisi ispod su izmišljeni, a provjerava se samo javni katalog.
"""
import json
import unittest
from pathlib import Path

import build_catalog as bc

TOOL = Path(__file__).resolve().parent
ROOT = TOOL.parents[1]
MAPPING = json.loads((TOOL / "mapping.json").read_text(encoding="utf-8"))


def raw(**overrides):
    base = {
        "slug": "test-press", "name": "Test Press", "primaryMuscles": ["Chest"],
        "secondaryMuscles": ["Triceps", "Shoulders"], "equipment": ["Barbell", "Bench"],
        "movementPattern": ["Push"], "difficulty": "beginner",
        "instructions": ["Korak 1."], "commonMistakes": ["Greška 1."],
    }
    base.update(overrides)
    return base


class ConvertTests(unittest.TestCase):
    def test_basic_mapping(self):
        result = bc.convert(raw(), MAPPING, {}, "Testni potisak")
        self.assertEqual(result["id"], "test-press")
        self.assertEqual(result["name"], {"en": "Test Press", "hr": "Testni potisak"})
        self.assertEqual(result["category"], "chest")
        self.assertEqual(result["movement"], "push")
        self.assertEqual(result["mechanic"], "compound")
        self.assertEqual(result["equipment"], "barbell")
        self.assertEqual(result["inputType"], "weightReps")
        self.assertEqual(result["primaryRegions"], ["chest"])
        self.assertEqual(result["video"], "Media/test-press.mp4")
        self.assertEqual(result["poster"], "Media/test-press.jpg")

    def test_public_record_has_no_movekit_texts(self):
        result = bc.convert(raw(), MAPPING, {}, None)
        for key in ("instructions", "commonMistakes", "shortDescription", "longDescription"):
            self.assertNotIn(key, result)
        self.assertEqual(result["name"], {"en": "Test Press"})

    def test_bench_is_ignored_for_equipment(self):
        self.assertEqual(bc.convert(raw(equipment=["Bench", "Dumbbell"]), MAPPING, {}, None)["equipment"], "dumbbell")

    def test_bodyweight_gives_bodyweight_input(self):
        result = bc.convert(raw(equipment=["Bodyweight"]), MAPPING, {}, None)
        self.assertEqual(result["inputType"], "bodyweight")

    def test_back_split_by_name(self):
        pulldown = bc.convert(raw(name="Lat Pulldown", primaryMuscles=["Back"], movementPattern=["Pull"]), MAPPING, {}, None)
        self.assertEqual(pulldown["primaryMuscles"], ["lats"])
        row = bc.convert(raw(name="Cable Row", primaryMuscles=["Back"], movementPattern=["Pull"]), MAPPING, {}, None)
        self.assertEqual(row["primaryMuscles"], ["middle back"])

    def test_cardio_distance_and_duration(self):
        run = bc.convert(raw(name="Treadmill Run", movementPattern=["Cardio"], equipment=["Bodyweight"]), MAPPING, {}, None)
        self.assertEqual(run["category"], "cardio")
        self.assertEqual(run["inputType"], "durationDistance")
        self.assertIsNone(run["mechanic"])
        self.assertIsNone(run["movement"])
        jacks = bc.convert(raw(name="Jumping Jacks", movementPattern=["Cardio"], equipment=["Bodyweight"]), MAPPING, {}, None)
        self.assertEqual(jacks["inputType"], "duration")

    def test_plank_is_duration(self):
        result = bc.convert(raw(name="Front Plank", primaryMuscles=["Core"], equipment=["Bodyweight"], movementPattern=["Core"]), MAPPING, {}, None)
        self.assertEqual(result["inputType"], "duration")

    def test_isolation(self):
        result = bc.convert(raw(movementPattern=["Isolation"]), MAPPING, {}, None)
        self.assertEqual(result["mechanic"], "isolation")

    def test_override_wins(self):
        result = bc.convert(raw(), MAPPING, {"inputType": "bodyweight", "category": "shoulders"}, None)
        self.assertEqual(result["inputType"], "bodyweight")
        self.assertEqual(result["category"], "shoulders")

    def test_secondary_does_not_repeat_primary(self):
        result = bc.convert(raw(secondaryMuscles=["Chest", "Triceps"]), MAPPING, {}, None)
        self.assertEqual(result["secondaryMuscles"], ["triceps"])

    def test_unknown_values_fail(self):
        with self.assertRaises(bc.BuildError):
            bc.convert(raw(primaryMuscles=["Tail"]), MAPPING, {}, None)
        with self.assertRaises(bc.BuildError):
            bc.convert(raw(difficulty="legendary"), MAPPING, {}, None)
        with self.assertRaises(bc.BuildError):
            bc.convert(raw(primaryMuscles=[]), MAPPING, {}, None)


class TextsTests(unittest.TestCase):
    def test_english_only(self):
        self.assertEqual(bc.texts_for(raw(), None), {
            "instructions": {"en": ["Korak 1."]}, "commonMistakes": {"en": ["Greška 1."]},
        })

    def test_with_croatian(self):
        texts = bc.texts_for(raw(), {"instructions": ["Hr korak."]})
        self.assertEqual(texts["instructions"]["hr"], ["Hr korak."])
        self.assertNotIn("hr", texts["commonMistakes"])


class LegacyTests(unittest.TestCase):
    def test_unknown_target_fails(self):
        with self.assertRaises(bc.BuildError):
            bc.check_legacy({"Old": "missing"}, {"present"})
        bc.check_legacy({"Old": "present", "Gone": None}, {"present"})


class PublicFilesTests(unittest.TestCase):
    """Javne datoteke u repozitoriju moraju se slagati s generiranim katalogom."""

    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads((ROOT / "Resources" / "Catalog" / "catalog.json").read_text(encoding="utf-8"))
        cls.ids = {e["id"] for e in cls.catalog["exercises"]}

    def test_catalog_has_no_texts(self):
        for exercise in self.catalog["exercises"]:
            self.assertNotIn("instructions", exercise, exercise["id"])
            self.assertNotIn("commonMistakes", exercise, exercise["id"])

    def test_every_exercise_has_croatian_name(self):
        names = bc.load_json(TOOL / "names-hr.json")
        self.assertEqual(set(names) - {"_opis"}, self.ids)
        for exercise in self.catalog["exercises"]:
            self.assertEqual(exercise["name"].get("hr"), names[exercise["id"]])

    def test_legacy_ids_match(self):
        legacy = {k: v for k, v in bc.load_json(TOOL / "legacy-ids.json").items() if not k.startswith("_")}
        self.assertEqual(self.catalog["legacyIds"], legacy)
        bc.check_legacy(legacy, self.ids)

    def test_overrides_name_existing_exercises(self):
        overrides = {k for k in bc.load_json(TOOL / "overrides.json") if not k.startswith("_")}
        self.assertEqual(overrides - self.ids, set())


if __name__ == "__main__":
    unittest.main()
