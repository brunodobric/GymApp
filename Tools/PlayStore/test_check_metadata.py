import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_metadata  # noqa: E402


def write_valid(base: Path) -> None:
    for language in check_metadata.LANGUAGES:
        folder = base / "metadata" / language
        folder.mkdir(parents=True)
        for name in check_metadata.FIELDS:
            (folder / name).write_text("Apolon", encoding="utf-8")


class CheckMetadataTests(unittest.TestCase):
    def test_valid_metadata_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_valid(Path(tmp))
            self.assertEqual(check_metadata.check(Path(tmp)), [])

    def test_too_long_title_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_valid(Path(tmp))
            (Path(tmp) / "metadata/hr/title.txt").write_text("č" * 31, encoding="utf-8")
            self.assertEqual(len(check_metadata.check(Path(tmp))), 1)

    def test_missing_file_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_valid(Path(tmp))
            (Path(tmp) / "metadata/en-US/release_notes.txt").unlink()
            self.assertIn("nedostaje", check_metadata.check(Path(tmp))[0])

    def test_ranking_word_in_short_description_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_valid(Path(tmp))
            (Path(tmp) / "metadata/en-US/short_description.txt").write_text("The best log", encoding="utf-8")
            self.assertEqual(len(check_metadata.check(Path(tmp))), 1)

    def test_emoji_in_title_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_valid(Path(tmp))
            (Path(tmp) / "metadata/hr/title.txt").write_text("Apolon 💪", encoding="utf-8")
            self.assertEqual(len(check_metadata.check(Path(tmp))), 1)


if __name__ == "__main__":
    unittest.main()
