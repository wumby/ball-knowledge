#!/usr/bin/env python3
"""Fail fast when an archived team-season cannot select exactly one logo era."""
import json
import pathlib
import hashlib
import datetime as dt
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "BallKnowledge/Database/OfflineVisualManifest.json"
ARCHIVE = ROOT / "BallKnowledge/Database/nba_historical_rosters.json"
TEAM_LOGO_AUDIT = ROOT / "BallKnowledge/Database/TeamLogoSeasonAudit.json"
PORTRAIT_COVERAGE_REPORT = ROOT / "Tools/team_season_portrait_coverage_report.json"
ASSETS = ROOT / "BallKnowledge/Assets.xcassets"
ALLOWED_COMMONS_LICENSE_PREFIXES = ("CC0", "CC BY", "Public domain")

def fail(message):
    print(f"error: {message}", file=sys.stderr)
    return 1

def allowed_commons_license(license_name):
    value = license_name.strip()
    return value.startswith(ALLOWED_COMMONS_LICENSE_PREFIXES) and "NC" not in value.upper() and "ND" not in value.upper()

def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

def main():
    manifest = json.loads(MANIFEST.read_text())
    if manifest.get("schemaVersion", 0) < 4:
        return fail("visual manifest schemaVersion must be at least 4")
    archive = json.loads(ARCHIVE.read_text())
    roster_players = {
        player["playerID"].lower()
        for team_season in archive.get("teamSeasons", archive)
        for player in team_season["players"]
    }
    portrait_mode = manifest.get("portraitMode", "licensedPhotos")
    asset_names = set()
    portrait_ids = set()
    for section in ("portraits", "teamLogos"):
        for entry in manifest.get(section, []):
            name = entry.get("assetName")
            if not name or name in asset_names:
                return fail(f"missing or duplicate assetName in {section}: {name}")
            asset_names.add(name)
            image_set = ASSETS / f"{name}.imageset"
            contents = image_set / "Contents.json"
            if not contents.exists() or not any(image_set.glob("*.png")) and not any(image_set.glob("*.jpg")) and not any(image_set.glob("*.jpeg")):
                return fail(f"asset set is missing or empty for {name}")
            image_files = list(image_set.glob("*.png")) + list(image_set.glob("*.jpg")) + list(image_set.glob("*.jpeg"))
            for image_file in image_files:
                if subprocess.run(["sips", "-g", "pixelWidth", str(image_file)], capture_output=True, text=True, check=False).returncode != 0:
                    return fail(f"asset image is unreadable for {name}: {image_file.name}")
            if not entry.get("source") or not entry.get("rights"):
                return fail(f"{name} is missing source or rights metadata")
            if section == "portraits" and (not name.startswith("player_") or not entry.get("playerID")):
                return fail(f"portrait {name} must use player_<playerID> and include playerID")
            if section == "portraits":
                player_id = entry["playerID"].lower()
                if player_id in portrait_ids:
                    return fail(f"duplicate portrait playerID: {entry['playerID']}")
                if player_id not in roster_players:
                    return fail(f"portrait {name} references a player absent from the roster")
                if name != f"player_{player_id}":
                    return fail(f"portrait {name} does not match playerID {entry['playerID']}")
                if portrait_mode == "licensedPhotos":
                    required = ("vendorAssetID", "vendorPlayerID", "licenseID", "licenseVersion", "mappingReviewStatus", "mappingReviewedBy", "mappingReviewedAt", "mappingEvidence", "sourceSHA256")
                    if any(not entry.get(key) for key in required):
                        return fail(f"portrait {name} has incomplete licensed-delivery metadata")
                    if entry["mappingReviewStatus"] != "approved":
                        return fail(f"portrait {name} does not have an approved identity mapping")
                    if entry["rights"] != "Approved commercial license":
                        return fail(f"portrait {name} does not have approved commercial rights")
                    portrait_files = list(image_set.glob("*.png")) + list(image_set.glob("*.jpg")) + list(image_set.glob("*.jpeg"))
                    if len(portrait_files) != 1 or sha256(portrait_files[0]) != entry["sourceSHA256"]:
                        return fail(f"portrait {name} checksum does not match its manifest")
                if portrait_mode == "licensedPhotos" and entry.get("source") == "Wikimedia Commons":
                    required = ("sourceURL", "wikidataItemID", "license", "licenseURL", "creator", "attribution")
                    if any(not entry.get(key) for key in required):
                        return fail(f"Commons portrait {name} has incomplete attribution metadata")
                    if not entry["wikidataItemID"].startswith("Q"):
                        return fail(f"Commons portrait {name} has an invalid Wikidata item ID")
                    if not allowed_commons_license(entry["license"]):
                        return fail(f"Commons portrait {name} has a disallowed license: {entry['license']}")
                portrait_ids.add(player_id)

    if portrait_mode == "generatedAvatars":
        if portrait_ids:
            return fail("generated-avatar catalog must not bundle third-party portrait records")
        if any(ASSETS.glob("player_*.imageset")):
            return fail("generated-avatar catalog must not bundle player image assets")
    elif portrait_mode == "licensedPhotos":
        if portrait_ids != roster_players:
            return fail(f"licensed portrait coverage is {len(portrait_ids)}/{len(roster_players)}")
        licenses = {item.get("licenseID"): item for item in manifest.get("portraitLicenses", [])}
        if not licenses:
            return fail("portrait license records are missing")
        vendor_asset_ids = set()
        vendor_player_ids = set()
        for entry in manifest.get("portraits", []):
            license_record = licenses.get(entry["licenseID"])
            if not license_record or license_record.get("version") != entry["licenseVersion"] or license_record.get("status") != "approved":
                return fail(f"portrait {entry['assetName']} has no matching approved license record")
            grants = license_record.get("grants", {})
            required_grants = ("mobileAppDistribution", "offlineBundling", "worldwide", "cropResize")
            if any(grants.get(grant) is not True for grant in required_grants):
                return fail(f"portrait {entry['assetName']} license lacks required distribution rights")
            try:
                start = dt.date.fromisoformat(license_record["validFrom"])
                end = dt.date.fromisoformat(license_record["validThrough"]) if license_record.get("validThrough") else None
            except (KeyError, ValueError):
                return fail(f"portrait {entry['assetName']} license has invalid validity dates")
            if start > dt.date.today() or end and end < dt.date.today():
                return fail(f"portrait {entry['assetName']} license is not currently valid")
            if entry["vendorAssetID"] in vendor_asset_ids or entry["vendorPlayerID"] in vendor_player_ids:
                return fail(f"portrait {entry['assetName']} duplicates a vendor asset or player ID")
            vendor_asset_ids.add(entry["vendorAssetID"])
            vendor_player_ids.add(entry["vendorPlayerID"])
            if grants.get("requiresInAppCredit") and (not entry.get("creator") or not entry.get("credit") or not license_record.get("requiredCreditLanguage")):
                return fail(f"portrait {entry['assetName']} is missing required credit metadata")
    elif portrait_mode == "developmentReferencePhotos":
        # Development/test-only source mode. This is deliberately separate
        # from the commercial release gate above.
        if not portrait_ids:
            return fail("development reference-photo catalog has no portraits")
        for entry in manifest.get("portraits", []):
            if entry.get("source") != "Basketball Reference headshots" or entry.get("rights") != "Source permission required before distribution" or not entry.get("sourceURL"):
                return fail(f"development portrait {entry['assetName']} does not declare its non-commercial source status")
    else:
        return fail(f"unknown portraitMode: {portrait_mode}")

    coverage_rows = manifest.get("teamSeasonPortraitCoverage", [])
    coverage_by_key = {(row.get("team"), row.get("season")): row for row in coverage_rows}
    archive_team_seasons = archive.get("teamSeasons", archive)
    if len(coverage_by_key) != len(archive_team_seasons):
        return fail(f"portrait coverage contains {len(coverage_by_key)} rows; archive contains {len(archive_team_seasons)}")
    for team_season in archive_team_seasons:
        key = (team_season["team"], team_season["season"])
        row = coverage_by_key.get(key)
        if not row:
            return fail(f"portrait coverage is missing {key[0]} {key[1]}")
        player_ids = {player["playerID"].lower() for player in team_season["players"]}
        available = len(player_ids & portrait_ids)
        missing = len(player_ids) - available
        if (row.get("rosterCount"), row.get("availableHeadshots"), row.get("missingHeadshots"), row.get("suppressDraftPortraits")) != (len(player_ids), available, missing, missing > len(player_ids) / 2):
            return fail(f"portrait coverage is stale or invalid for {key[0]} {key[1]}")
    if not PORTRAIT_COVERAGE_REPORT.exists():
        return fail("team-season portrait coverage report is missing")
    report = json.loads(PORTRAIT_COVERAGE_REPORT.read_text())
    if report.get("teamSeasons") != coverage_rows:
        return fail("team-season portrait coverage report does not match the manifest")

    eras_by_team = {}
    for era in manifest.get("teamLogos", []):
        required = ("team", "firstSeason", "lastSeason", "assetName", "source", "rights")
        if any(era.get(key) is None or era.get(key) == "" for key in required):
            return fail(f"incomplete team-logo era: {era.get('assetName', '<unnamed>')}")
        first, last = era["firstSeason"], era["lastSeason"]
        if not isinstance(first, int) or not isinstance(last, int) or first > last:
            return fail(f"invalid season range for {era['assetName']}")
        if not era.get("sourceSHA256"):
            return fail(f"{era['assetName']} is missing sourceSHA256")
        pngs = list((ASSETS / f"{era['assetName']}.imageset").glob("*.png"))
        if len(pngs) != 1:
            return fail(f"{era['assetName']} must contain exactly one normalized PNG")
        properties = subprocess.run(
            ["sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", str(pngs[0])],
            capture_output=True, text=True, check=False,
        ).stdout
        if "pixelWidth: 512" not in properties or "pixelHeight: 512" not in properties or "hasAlpha: yes" not in properties:
            return fail(f"{era['assetName']} must be a 512x512 PNG with alpha")
        eras_by_team.setdefault(era["team"], []).append(era)
    for team, eras in eras_by_team.items():
        eras.sort(key=lambda item: item["firstSeason"])
        for previous, current in zip(eras, eras[1:]):
            if current["firstSeason"] <= previous["lastSeason"]:
                return fail(f"overlapping logo eras for {team}: {previous['assetName']} and {current['assetName']}")

    if not TEAM_LOGO_AUDIT.exists():
        return fail("team-logo season audit is missing")
    expected_rows = json.loads(TEAM_LOGO_AUDIT.read_text()).get("teamSeasons", [])
    expected_by_team_season = {(row["team"], int(row["season"])): row for row in expected_rows}

    team_seasons = archive.get("teamSeasons", archive)
    for row in team_seasons:
        team, year = row["team"], int(row["season"][:4])
        matches = [era for era in eras_by_team.get(team, []) if era["firstSeason"] <= year <= era["lastSeason"]]
        if len(matches) != 1:
            return fail(f"{team} {row['season']} resolves to {len(matches)} logo eras")
        expected = expected_by_team_season.get((team, year))
        if not expected:
            return fail(f"{team} {row['season']} is absent from the team-logo audit")
        actual = matches[0]
        if actual["assetName"] != expected["assetName"] or actual["sourceSHA256"] != expected["sourceSHA256"]:
            return fail(f"{team} {row['season']} selects {actual['assetName']}, expected {expected['assetName']}")
    if len(expected_by_team_season) != len(team_seasons):
        return fail(f"team-logo audit contains {len(expected_by_team_season)} rows; archive contains {len(team_seasons)}")

    # Regression boundaries that previously disappeared inside broad hand-made eras.
    for team, before, after in (("LAL", 2000, 2001), ("WAS", 2006, 2007), ("WAS", 2010, 2011), ("WAS", 2014, 2015)):
        left = expected_by_team_season[(team, before)]["assetName"]
        right = expected_by_team_season[(team, after)]["assetName"]
        if left == right:
            return fail(f"regression boundary missing for {team} {before}/{after}")
    print(f"Offline visual manifest valid ({len(asset_names)} assets; {len(team_seasons)} exact team-seasons audited).")
    return 0

if __name__ == "__main__":
    sys.exit(main())
