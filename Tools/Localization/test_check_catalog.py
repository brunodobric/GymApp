"""Testovi provjere String Cataloga."""

import unittest

from check_catalog import check, specifiers


def unit(value, state="translated"):
    return {"stringUnit": {"state": state, "value": value}}


def catalog(strings):
    return {"sourceLanguage": "hr", "strings": strings, "version": "1.0"}


class SpecifierTests(unittest.TestCase):
    def test_vrste_bez_pozicije(self):
        self.assertEqual(specifiers("%1$@ i %2$lld"), ["@", "int"])
        self.assertEqual(specifiers("%lld od %lld"), ["int", "int"])
        self.assertEqual(specifiers("100%% gotovo"), [])
        self.assertEqual(specifiers("%.1f kg"), ["double"])


class CheckTests(unittest.TestCase):
    def test_preveden_kljuc_prolazi(self):
        missing, errors, stale = check(catalog({"Spremi": {"localizations": {"en": unit("Save")}}}))
        self.assertEqual((missing, errors, stale), ([], [], []))

    def test_fraze_za_precace(self):
        def phrases(state):
            return {"stringSet": {"state": state, "values": ["Start ${applicationName}", "Go ${applicationName}"]}}

        key = "Kreni u ${applicationName}"
        missing, errors, _ = check(catalog({key: {"localizations": {"en": phrases("translated")}}}))
        self.assertEqual((missing, errors), ([], []))
        _, errors, _ = check(catalog({key: {"localizations": {"en": phrases("needs_review")}}}))
        self.assertEqual(len(errors), 2)
        missing, _, _ = check(catalog({key: {"localizations": {"en": {"stringSet": {"state": "translated", "values": []}}}}}))
        self.assertEqual(missing, [key])

    def test_kljuc_bez_engleskog(self):
        missing, _, _ = check(catalog({"Spremi": {}}))
        self.assertEqual(missing, ["Spremi"])

    def test_nepreveden_unit_je_greska(self):
        _, errors, _ = check(catalog({"Spremi": {"localizations": {"en": unit("Save", state="new")}}}))
        self.assertEqual(len(errors), 1)

    def test_razliciti_argumenti(self):
        _, errors, _ = check(catalog({"%lld serija": {"localizations": {"en": unit("%@ sets")}}}))
        self.assertEqual(len(errors), 1)

    def test_mnozina_one_smije_bez_broja(self):
        entry = {"localizations": {"en": {"variations": {"plural": {
            "one": unit("One set"), "other": unit("%lld sets")}}}}}
        missing, errors, _ = check(catalog({"%lld serija": entry}))
        self.assertEqual((missing, errors), ([], []))

    def test_mnozina_other_mora_imati_broj(self):
        entry = {"localizations": {"en": {"variations": {"plural": {
            "one": unit("One set"), "other": unit("Sets")}}}}}
        _, errors, _ = check(catalog({"%lld serija": entry}))
        self.assertEqual(len(errors), 1)

    def test_zastarjeli_i_neprevodivi(self):
        missing, errors, stale = check(catalog({
            "Staro": {"extractionState": "stale"},
            "Apolon": {"shouldTranslate": False},
        }))
        self.assertEqual((missing, errors, stale), ([], [], ["Staro"]))


if __name__ == "__main__":
    unittest.main()
