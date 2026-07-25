import importlib.util
import pathlib
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "import_licensed_portraits.py"
SPEC = importlib.util.spec_from_file_location("licensed_importer", SCRIPT)
IMPORTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(IMPORTER)


class LicensedPortraitImporterTests(unittest.TestCase):
    def license(self, **overrides):
        record = {"licenseID": "L-1", "version": "1", "vendor": "Vendor", "status": "approved", "validFrom": "2025-01-01", "validThrough": "2027-01-01", "grants": {key: True for key in IMPORTER.REQUIRED_GRANTS}}
        record["grants"]["requiresInAppCredit"] = False
        record.update(overrides)
        return record

    def test_license_requires_all_offline_distribution_grants(self):
        license = self.license()
        license["grants"]["offlineBundling"] = False
        self.assertIn("offlineBundling", IMPORTER.approved_license(license))

    def test_unapproved_or_unevidenced_mapping_is_not_automatic(self):
        roster = {"smithjo01": "John Smith", "smithjo02": "John Smith"}
        mapping, errors = IMPORTER.reviewed_mapping({"mappings": [{"vendorPlayerID": "v1", "playerID": "smithjo01", "reviewStatus": "pending"}]}, roster)
        self.assertEqual(mapping, {})
        self.assertEqual(errors, [])
        accepted, queue, errors = IMPORTER.validate_delivery({"assets": [{"vendorPlayerID": "v1", "vendorAssetID": "a1", "file": "a.jpg", "fullName": "John Smith"}]}, mapping, roster)
        self.assertEqual(accepted, [])
        self.assertEqual(len(queue[0]["candidateRosterPlayers"]), 2)
        self.assertEqual(errors, [])

    def test_duplicate_asset_and_duplicate_player_mappings_are_rejected(self):
        roster = {"jamesle01": "LeBron James"}
        mappings, errors = IMPORTER.reviewed_mapping({"mappings": [
            {"vendorPlayerID": "v1", "playerID": "jamesle01", "reviewStatus": "approved", "reviewedBy": "a", "reviewedAt": "now", "evidence": "id"},
            {"vendorPlayerID": "v2", "playerID": "jamesle01", "reviewStatus": "approved", "reviewedBy": "a", "reviewedAt": "now", "evidence": "id"},
        ]}, roster)
        self.assertIn("duplicate approved mapping", errors[0])
        accepted, queue, errors = IMPORTER.validate_delivery({"assets": [
            {"vendorPlayerID": "v1", "vendorAssetID": "a", "file": "one.jpg"},
            {"vendorPlayerID": "v1", "vendorAssetID": "a", "file": "two.jpg"},
        ]}, mappings, roster)
        self.assertEqual(len(accepted), 1)
        self.assertEqual(queue, [])
        self.assertIn("duplicate vendorAssetID", errors[0])

    def test_credit_language_is_required_when_license_requires_credit(self):
        record = self.license()
        record["grants"]["requiresInAppCredit"] = True
        self.assertIn("requiredCreditLanguage", IMPORTER.approved_license(record))

    def test_invalid_image_is_rejected_before_an_asset_is_written(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(IMPORTER.subprocess, "run") as run:
            run.return_value.returncode = 1
            source = pathlib.Path(directory) / "invalid.jpg"
            destination = pathlib.Path(directory) / "portrait.jpg"
            with self.assertRaisesRegex(ValueError, "unreadable image"):
                IMPORTER.render_asset(source, destination)
            self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()
