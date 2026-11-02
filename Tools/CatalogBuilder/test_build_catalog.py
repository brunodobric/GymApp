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


if __name__ == "__main__":
    unittest.main()
