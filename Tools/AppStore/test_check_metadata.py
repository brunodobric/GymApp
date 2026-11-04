"""Testovi za check_metadata.py. Pokretanje: python3 -m unittest discover -s Tools/AppStore"""

import tempfile
import unittest
from pathlib import Path

import check_metadata as checker

VALID = {
    "name.txt": "Apolon: dnevnik treninga",
    "subtitle.txt": "Serije, odmor i napredak",
    "promotional_text.txt": "Kratko.",
    "description.txt": "Opis.",
    "keywords.txt": "teretana,snaga",
    "release_notes.txt": "Prvo izdanje.",
    "support_url.txt": "https://example.com/podrska/",
    "privacy_url.txt": "https://example.com/privacy/",
}


class CheckMetadataTests(unittest.TestCase):

    def make(self, overrides=None, missing=()):
        directory = Path(tempfile.mkdtemp())
        for language in checker.LANGUAGES:
            folder = directory / "metadata" / language
            folder.mkdir(parents=True)
            for name, text in {**VALID, **(overrides or {})}.items():
                if name not in missing:
                    (folder / name).write_text(text + "\n", encoding="utf-8")
        (directory / "review_notes.txt").write_text("Notes.", encoding="utf-8")
        return directory

    def test_valid(self):
        self.assertEqual(checker.check(self.make()), [])

    def test_repository_metadata_is_valid(self):
        self.assertEqual(checker.check(checker.DEFAULT_DIR), [])

    def test_too_long_name(self):
        errors = checker.check(self.make({"name.txt": "x" * 31}))
        self.assertTrue(any("name.txt: 31 znakova" in error for error in errors))

    def test_keywords_count_bytes(self):
        # 50 znakova "ž" je 100 bajtova (u redu), 51 je previše.
        self.assertEqual(checker.check(self.make({"keywords.txt": "ž" * 50})), [])
        errors = checker.check(self.make({"keywords.txt": "ž" * 51}))
        self.assertTrue(any("102 bajtova" in error for error in errors))

    def test_keyword_rules(self):
        errors = checker.check(self.make({"keywords.txt": "snaga, teretana,snaga,odmor"}))
        joined = "\n".join(errors)
        self.assertIn("bez razmaka", joined)
        self.assertIn("ponavlja se snaga", joined)
        self.assertIn("odmor je već u nazivu", joined)

    def test_missing_file_and_bad_url(self):
        errors = checker.check(self.make({"support_url.txt": "http://example.com"}, missing=("subtitle.txt",)))
        joined = "\n".join(errors)
        self.assertIn("subtitle.txt: datoteka nedostaje", joined)
        self.assertIn("https://", joined)

    def test_unknown_file(self):
        directory = self.make()
        (directory / "metadata" / "hr" / "naslov.txt").write_text("x", encoding="utf-8")
        self.assertIn("hr/naslov.txt: nepoznata datoteka", checker.check(directory))


if __name__ == "__main__":
    unittest.main()
