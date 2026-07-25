#!/usr/bin/env python3
"""Import an approved commercial portrait delivery into the Xcode asset catalog.

The importer deliberately has no name-only matching path.  A delivery item is
accepted only when a reviewed vendor-ID mapping identifies one roster player.
Unresolved items are emitted to a review queue and no app assets are changed.
"""
import argparse
import datetime as dt
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
ROSTER = ROOT / "BallKnowledge/Database/nba_historical_rosters.json"
ASSETS = ROOT / "BallKnowledge/Assets.xcassets"
MANIFEST = ROOT / "BallKnowledge/Database/OfflineVisualManifest.json"
REPORT = ROOT / "Tools/licensed_portrait_import_report.json"
REQUIRED_GRANTS = ("mobileAppDistribution", "offlineBundling", "worldwide", "cropResize")


def load_json(path):
    return json.loads(path.read_text())


def roster_players(path=ROSTER):
    archive = load_json(path)
    result = {}
    for season in archive["teamSeasons"]:
        for player in season["players"]:
            result[player["playerID"].lower()] = player["playerName"]
    return result


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def approved_license(record, today=None):
    """Return a human-readable reason when a license cannot ship portraits."""
    required = ("licenseID", "version", "vendor", "status", "validFrom", "grants")
    missing = [key for key in required if not record.get(key)]
    if missing:
        return "license record missing " + ", ".join(missing)
    if record["status"] != "approved":
        return "license record status is not approved"
    grants = record["grants"]
    absent = [key for key in REQUIRED_GRANTS if grants.get(key) is not True]
    if absent:
        return "license does not grant " + ", ".join(absent)
    try:
        now = today or dt.date.today()
        start = dt.date.fromisoformat(record["validFrom"])
        end = dt.date.fromisoformat(record["validThrough"]) if record.get("validThrough") else None
    except ValueError:
        return "license validity dates must be ISO-8601 dates"
    if start > now or end and end < now:
        return "license is not valid on the import date"
    if grants.get("requiresInAppCredit") and not record.get("requiredCreditLanguage"):
        return "license requires in-app credit but requiredCreditLanguage is missing"
    return None


def reviewed_mapping(mapping, roster):
    """Index only explicit, approved vendor-ID mappings.

    The evidence fields make it possible to audit a manual identity decision;
    they also prevent a same-name player from being automatically accepted.
    """
    indexed, errors = {}, []
    for row in mapping.get("mappings", []):
        vendor_id = str(row.get("vendorPlayerID", "")).strip()
        player_id = str(row.get("playerID", "")).lower().strip()
        if not vendor_id or not player_id:
            errors.append("mapping missing vendorPlayerID or playerID")
        elif row.get("reviewStatus") != "approved":
            continue
        elif player_id not in roster:
            errors.append(f"mapping for {vendor_id} references unknown playerID {player_id}")
        elif vendor_id in indexed or player_id in {value["playerID"] for value in indexed.values()}:
            errors.append(f"duplicate approved mapping for {vendor_id} or {player_id}")
        elif not row.get("reviewedBy") or not row.get("reviewedAt") or not row.get("evidence"):
            errors.append(f"approved mapping for {vendor_id} is missing review evidence")
        else:
            indexed[vendor_id] = {**row, "playerID": player_id}
    return indexed, errors


def candidate_ids(item, roster):
    """Review-only candidates; a name match alone never yields an import."""
    name = " ".join(str(item.get("fullName", "")).casefold().split())
    if not name:
        return []
    return [{"playerID": player_id, "playerName": player_name}
            for player_id, player_name in roster.items()
            if " ".join(player_name.casefold().split()) == name]


def validate_delivery(delivery, mappings, roster):
    accepted, queue, errors = [], [], []
    seen_assets = set()
    for item in delivery.get("assets", []):
        vendor_id = str(item.get("vendorPlayerID", "")).strip()
        asset_id = str(item.get("vendorAssetID", "")).strip()
        filename = str(item.get("file", "")).strip()
        if not vendor_id or not asset_id or not filename:
            errors.append("delivery asset missing vendorPlayerID, vendorAssetID, or file")
            continue
        if asset_id in seen_assets:
            errors.append(f"duplicate vendorAssetID {asset_id}")
            continue
        seen_assets.add(asset_id)
        mapping = mappings.get(vendor_id)
        if not mapping:
            queue.append({"vendorPlayerID": vendor_id, "vendorAssetID": asset_id,
                          "fullName": item.get("fullName", ""), "birthDate": item.get("birthDate", ""),
                          "careerContext": item.get("careerContext", ""),
                          "candidateRosterPlayers": candidate_ids(item, roster),
                          "reason": "no approved vendor-ID mapping"})
            continue
        accepted.append((item, mapping))
    return accepted, queue, errors


def render_asset(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.stem + ".importing.jpg")
    result = subprocess.run(["sips", "--cropToHeightWidth", "512", "512", str(source), "--out", str(temporary)],
                            capture_output=True, text=True, check=False)
    if result.returncode or not temporary.exists() or temporary.stat().st_size == 0:
        temporary.unlink(missing_ok=True)
        raise ValueError("unreadable image")
    properties = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(temporary)],
                                capture_output=True, text=True, check=False).stdout
    if "pixelWidth: 512" not in properties or "pixelHeight: 512" not in properties:
        temporary.unlink(missing_ok=True)
        raise ValueError("normalized image is not 512x512")
    temporary.replace(destination)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("delivery", type=pathlib.Path, help="Vendor delivery JSON")
    parser.add_argument("license", type=pathlib.Path, help="Executed-license record JSON")
    parser.add_argument("mapping", type=pathlib.Path, help="Reviewed vendor-ID mapping JSON")
    parser.add_argument("--delivery-dir", type=pathlib.Path, required=True, help="Directory containing delivery image files")
    parser.add_argument("--allow-partial", action="store_true", help="For an approved sample only; never use for a release")
    parser.add_argument("--report", type=pathlib.Path, default=REPORT)
    args = parser.parse_args()

    roster = roster_players()
    license_record, delivery, mapping = load_json(args.license), load_json(args.delivery), load_json(args.mapping)
    license_error = approved_license(license_record)
    mappings, mapping_errors = reviewed_mapping(mapping, roster)
    accepted, queue, errors = validate_delivery(delivery, mappings, roster)
    errors = ([license_error] if license_error else []) + mapping_errors + errors
    mapped_ids = [item_mapping[1]["playerID"] for item_mapping in accepted]
    duplicate_ids = sorted({player_id for player_id in mapped_ids if mapped_ids.count(player_id) > 1})
    if duplicate_ids:
        errors.append("multiple delivered files map to " + ", ".join(duplicate_ids))
    missing = sorted(set(roster) - set(mapped_ids))
    if queue:
        errors.append(f"{len(queue)} assets require manual identity review")
    if not args.allow_partial and missing:
        errors.append(f"delivery does not cover all roster IDs ({len(missing)} missing)")

    report = {"generatedAt": dt.datetime.now(dt.timezone.utc).isoformat(), "vendor": delivery.get("vendor"),
              "licenseID": license_record.get("licenseID"), "licenseVersion": license_record.get("version"),
              "totalRosterPlayers": len(roster), "acceptedMappings": len(accepted),
              "unresolvedRosterIDs": missing, "manualReviewQueue": queue, "errors": errors}
    if errors:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n")
        print("Import rejected; see " + str(args.report), file=sys.stderr)
        return 1

    staged = []
    with tempfile.TemporaryDirectory() as directory:
        stage = pathlib.Path(directory)
        try:
            for item, match in accepted:
                source = args.delivery_dir / item["file"]
                if not source.is_file():
                    raise ValueError(f"delivery file missing: {item['file']}")
                player_id = match["playerID"]
                portrait = stage / f"player_{player_id}.imageset" / "portrait.jpg"
                render_asset(source, portrait)
                (portrait.parent / "Contents.json").write_text(json.dumps({"images": [{"filename": "portrait.jpg", "idiom": "universal", "scale": "1x"}], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
                staged.append((item, match, portrait))
            manifest = load_json(MANIFEST)
            entries = []
            for item, match, portrait in staged:
                player_id = match["playerID"]
                entries.append({"assetName": f"player_{player_id}", "playerID": player_id, "playerName": roster[player_id],
                                "source": license_record["vendor"], "sourceURL": item.get("sourceURL") or delivery.get("deliveryReference", ""),
                                "vendorAssetID": item["vendorAssetID"], "vendorPlayerID": item["vendorPlayerID"],
                                "licenseID": license_record["licenseID"], "licenseVersion": license_record["version"],
                                "rights": "Approved commercial license", "mappingReviewStatus": "approved",
                                "mappingReviewedBy": match["reviewedBy"], "mappingReviewedAt": match["reviewedAt"],
                                "mappingEvidence": match["evidence"], "creator": item.get("creator", ""),
                                "credit": item.get("credit", ""), "sourceSHA256": sha256(portrait)})
            for _, match, portrait in staged:
                target = ASSETS / portrait.parent.name
                shutil.rmtree(target, ignore_errors=True)
                shutil.copytree(portrait.parent, target)
            manifest["schemaVersion"] = 4
            manifest["portraitLicenses"] = [license_record]
            manifest["portraits"] = sorted(entries, key=lambda entry: entry["playerID"])
            MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
        except Exception as error:
            errors.append(str(error))
    report["errors"] = errors
    report["coveredRosterPlayers"] = len(entries) if not errors else 0
    report["coverage"] = f"{len(entries)}/{len(roster)}" if not errors else "0/" + str(len(roster))
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    if errors:
        print("Import failed; see " + str(args.report), file=sys.stderr)
        return 1
    print(f"Licensed portrait coverage: {len(entries)}/{len(roster)}. Report: {args.report}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
