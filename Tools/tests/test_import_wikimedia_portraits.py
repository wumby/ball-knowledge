import importlib.util
import pathlib
import unittest
import urllib.error
from unittest.mock import patch


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "import_wikimedia_portraits.py"
SPEC = importlib.util.spec_from_file_location("wikimedia_importer", SCRIPT)
IMPORTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(IMPORTER)


class WikimediaImporterTests(unittest.TestCase):
    def metadata(self, **overrides):
        value = {"downloadURL": "https://upload.wikimedia.org/example.jpg", "mime": "image/jpeg",
                 "sourceURL": "https://commons.wikimedia.org/wiki/File:Example.jpg", "license": "CC BY-SA 4.0",
                 "licenseURL": "https://creativecommons.org/licenses/by-sa/4.0/", "creator": "Example photographer", "credit": ""}
        value.update(overrides)
        return value

    def test_exact_p2685_resolution_and_missing_p18(self):
        response = {"results": {"bindings": [{"brId": {"value": "jamesle01"}, "item": {"value": "http://www.wikidata.org/entity/Q36159"}, "image": {"value": "http://commons.wikimedia.org/wiki/Special:FilePath/LeBron_James.jpg"}}]}}
        with patch.object(IMPORTER, "api_json", return_value=response):
            matches, duplicates = IMPORTER.wikidata_matches(["jamesle01", "nobody01"])
        self.assertEqual(matches["jamesle01"]["wikidataItemID"], "Q36159")
        self.assertIn("File:LeBron James.jpg", matches["jamesle01"]["imageTitle"])
        self.assertNotIn("nobody01", matches)
        self.assertEqual(duplicates, set())

    def test_duplicate_p2685_records_are_rejected(self):
        bindings = [{"brId": {"value": "jamesle01"}, "item": {"value": "http://www.wikidata.org/entity/Q1"}, "image": {"value": f"http://commons.wikimedia.org/wiki/Special:FilePath/{name}.jpg"}} for name in ("One", "Two")]
        with patch.object(IMPORTER, "api_json", return_value={"results": {"bindings": bindings}}):
            matches, duplicates = IMPORTER.wikidata_matches(["jamesle01"])
        self.assertEqual(matches, {})
        self.assertEqual(duplicates, {"jamesle01"})

    def test_nc_nd_and_incomplete_attribution_are_rejected(self):
        self.assertFalse(IMPORTER.allowed_license("CC BY-NC 4.0"))
        self.assertFalse(IMPORTER.allowed_license("CC BY-ND 4.0"))
        self.assertEqual(IMPORTER.valid_metadata(self.metadata(creator="")), "incomplete Commons attribution metadata")
        self.assertIsNone(IMPORTER.valid_metadata(self.metadata(license="Public domain")))

    def test_failed_image_response_is_reported(self):
        with patch("urllib.request.urlopen", side_effect=urllib.error.URLError("offline")):
            with self.assertRaises(urllib.error.URLError):
                IMPORTER.download("https://upload.wikimedia.org/example.jpg", pathlib.Path("/tmp/no-write.jpg"))


if __name__ == "__main__":
    unittest.main()
