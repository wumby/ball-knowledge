#!/usr/bin/env python3
"""Import license-safe Wikimedia Commons portraits linked by Wikidata P2685.

This importer intentionally has no name-search path. A Basketball Reference
player ID must exactly match Wikidata's P2685 value and the item must expose a
Commons P18 image before a file is considered. Runs are resumable: existing
manifest entries are never replaced and every skipped candidate is reported.
"""
import argparse
import html
import json
import pathlib
import re
import shutil
import subprocess
import tempfile
import time
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
ROSTER = ROOT / "BallKnowledge/Database/nba_historical_rosters.json"
ASSETS = ROOT / "BallKnowledge/Assets.xcassets"
MANIFEST = ROOT / "BallKnowledge/Database/OfflineVisualManifest.json"
REPORT = ROOT / "Tools/wikimedia_portrait_import_report.json"
USER_AGENT = "BallKnowledge Wikimedia portrait importer/1.0 (offline asset ingestion)"
SOURCE = "Wikimedia Commons"
ALLOWED_LICENSE_PREFIXES = ("CC0", "CC BY", "Public domain")


def roster_players():
    archive = json.loads(ROSTER.read_text())
    return {
        player["playerID"].lower(): player["playerName"]
        for season in archive["teamSeasons"] for player in season["players"]
    }


def api_json(url, retries=2):
    for attempt in range(retries + 1):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except Exception:
            if attempt == retries:
                raise
            time.sleep(attempt + 1)


def wikidata_matches(player_ids):
    """Return exact P2685 -> {itemID, imageTitle}; no name matching occurs."""
    if not player_ids:
        return {}, set()
    # Wikidata's P2685 stores Basketball Reference's canonical path (for
    # example, `j/jamesle01`); the roster intentionally stores its stable
    # final path segment (`jamesle01`). This is a deterministic ID transform,
    # not a human-name lookup.
    values = " ".join(json.dumps(f"{player_id[0]}/{player_id}") for player_id in player_ids)
    query = """SELECT ?item ?brId ?image WHERE {
      VALUES ?brId { %s }
      ?item wdt:P2685 ?brId; wdt:P18 ?image.
    }""" % values
    url = "https://query.wikidata.org/sparql?" + urllib.parse.urlencode({"format": "json", "query": query})
    bindings = api_json(url).get("results", {}).get("bindings", [])
    matches = {}
    duplicates = set()
    for row in bindings:
        player_id = row["brId"]["value"].rsplit("/", 1)[-1].lower()
        item_id = row["item"]["value"].rsplit("/", 1)[-1]
        image_title = urllib.parse.unquote(row["image"]["value"].rsplit("/", 1)[-1]).replace("_", " ")
        candidate = {"wikidataItemID": item_id, "imageTitle": f"File:{image_title}"}
        if player_id in matches and matches[player_id] != candidate:
            duplicates.add(player_id)
        else:
            matches[player_id] = candidate
    for player_id in duplicates:
        matches.pop(player_id, None)
    return matches, duplicates


def clean_metadata(value):
    plain = re.sub(r"<[^>]*>", " ", value or "")
    return " ".join(html.unescape(plain).replace("\n", " ").split())


def allowed_license(license_name):
    value = clean_metadata(license_name)
    return value.startswith(ALLOWED_LICENSE_PREFIXES) and "NC" not in value.upper() and "ND" not in value.upper()


def commons_metadata(image_title):
    params = {"action": "query", "format": "json", "prop": "imageinfo", "titles": image_title,
              "iiprop": "url|mime|extmetadata"}
    response = api_json("https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params))
    pages = response.get("query", {}).get("pages", {})
    page = next(iter(pages.values()), {})
    info = (page.get("imageinfo") or [{}])[0]
    meta = info.get("extmetadata") or {}
    value = lambda key: clean_metadata(meta.get(key, {}).get("value", ""))
    file_page = "https://commons.wikimedia.org/wiki/" + urllib.parse.quote(page.get("title", image_title).replace(" ", "_"))
    return {
        "downloadURL": info.get("url"), "mime": info.get("mime", ""), "sourceURL": file_page,
        "license": value("LicenseShortName"), "licenseURL": value("LicenseUrl"),
        "creator": value("Artist"), "credit": value("Credit"),
    }


def valid_metadata(metadata):
    required = ("downloadURL", "sourceURL", "license", "licenseURL", "creator")
    if any(not metadata.get(key) for key in required):
        return "incomplete Commons attribution metadata"
    if not metadata["mime"].startswith("image/"):
        return f"unsupported MIME type: {metadata['mime'] or 'missing'}"
    if not allowed_license(metadata["license"]):
        return f"disallowed license: {metadata['license']}"
    return None


def download(url, destination):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=45) as response, open(destination, "wb") as output:
        shutil.copyfileobj(response, output)
    if not destination.exists() or destination.stat().st_size == 0:
        raise ValueError("empty image response")


def write_imageset(player_id, source_path):
    image_set = ASSETS / f"player_{player_id}.imageset"
    image_set.mkdir(parents=True, exist_ok=True)
    output = image_set / "portrait.jpg"
    temporary = image_set / "portrait.importing.jpg"
    temporary.unlink(missing_ok=True)
    result = subprocess.run(["sips", "--cropToHeightWidth", "120", "120", str(source_path), "--out", str(temporary)],
                            capture_output=True, text=True, check=False)
    if result.returncode or not temporary.exists() or temporary.stat().st_size == 0:
        temporary.unlink(missing_ok=True)
        return None
    temporary.replace(output)
    (image_set / "Contents.json").write_text(json.dumps({"images": [{"filename": "portrait.jpg", "idiom": "universal", "scale": "1x"}], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    return f"player_{player_id}"


def manifest_entry(player_id, player_name, match, metadata):
    attribution = f"{metadata['creator']} — {metadata['license']}"
    if metadata["credit"]:
        attribution += f" ({metadata['credit']})"
    return {"assetName": f"player_{player_id}", "playerID": player_id, "playerName": player_name,
            "source": SOURCE, "sourceURL": metadata["sourceURL"], "rights": metadata["license"],
            "wikidataItemID": match["wikidataItemID"], "license": metadata["license"],
            "licenseURL": metadata["licenseURL"], "creator": metadata["creator"], "attribution": attribution}


def persist_manifest(manifest, existing_entries, imported):
    """Checkpoint imports so an interrupted full pass remains safely resumable."""
    manifest["schemaVersion"] = max(3, manifest.get("schemaVersion", 1))
    manifest["portraits"] = sorted(existing_entries + imported, key=lambda item: item["playerID"])
    temporary = MANIFEST.with_suffix(".importing.json")
    temporary.write_text(json.dumps(manifest, indent=2) + "\n")
    temporary.replace(MANIFEST)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, help="Process at most this many unresolved roster IDs")
    parser.add_argument("--player-ids", help="Comma-separated stable Basketball Reference IDs")
    parser.add_argument("--batch-size", type=int, default=100)
    parser.add_argument("--report", type=pathlib.Path, default=REPORT)
    args = parser.parse_args()
    if args.limit is not None and args.limit < 0 or args.batch_size < 1:
        parser.error("limit must be nonnegative and batch-size must be positive")
    roster = roster_players()
    manifest = json.loads(MANIFEST.read_text())
    existing_entries = manifest.get("portraits", [])
    known = {entry["playerID"].lower() for entry in manifest.get("portraits", [])}
    requested = {value.strip().lower() for value in args.player_ids.split(",")} if args.player_ids else None
    candidates = [player_id for player_id in sorted(roster) if player_id not in known and (requested is None or player_id in requested)]
    if args.limit is not None:
        candidates = candidates[:args.limit]
    matches, duplicates = {}, set()
    for start in range(0, len(candidates), args.batch_size):
        batch = candidates[start:start + args.batch_size]
        try:
            found, repeated = wikidata_matches(batch)
            matches.update(found); duplicates.update(repeated)
        except Exception as error:
            for player_id in batch:
                matches[player_id] = {"error": f"Wikidata API error: {error}"}
    imported, outcomes = [], []
    with tempfile.TemporaryDirectory() as directory:
        temp_dir = pathlib.Path(directory)
        for index, player_id in enumerate(candidates, 1):
            outcome = {"playerID": player_id, "playerName": roster[player_id]}
            match = matches.get(player_id)
            if player_id in duplicates:
                outcome["outcome"] = "skipped"; outcome["reason"] = "multiple Wikidata P2685/P18 matches"
            elif not match:
                outcome["outcome"] = "skipped"; outcome["reason"] = "no exact Wikidata P2685 match with P18 image"
            elif match.get("error"):
                outcome["outcome"] = "failed"; outcome["reason"] = match["error"]
            else:
                try:
                    metadata = commons_metadata(match["imageTitle"])
                    reason = valid_metadata(metadata)
                    if reason:
                        outcome["outcome"] = "skipped"; outcome["reason"] = reason
                    else:
                        path = temp_dir / f"{player_id}.image"
                        download(metadata["downloadURL"], path)
                        if not write_imageset(player_id, path):
                            raise ValueError("unreadable image")
                        imported.append(manifest_entry(player_id, roster[player_id], match, metadata))
                        persist_manifest(manifest, existing_entries, imported)
                        outcome["outcome"] = "imported"
                except Exception as error:
                    outcome["outcome"] = "failed"; outcome["reason"] = str(error)
            outcomes.append(outcome)
            print(f"[{index}/{len(candidates)}] {outcome['outcome']}: {player_id}" + (f" ({outcome.get('reason')})" if outcome.get("reason") else ""))
    persist_manifest(manifest, existing_entries, imported)
    covered = {entry["playerID"].lower() for entry in manifest["portraits"]} & set(roster)
    report = {"totalRosterPlayers": len(roster), "coveredRosterPlayers": len(covered),
              "coveragePercent": round(100 * len(covered) / len(roster), 2), "addedThisRun": len(imported),
              "outcomes": outcomes, "remainingGaps": [{"playerID": player_id, "playerName": roster[player_id]} for player_id in sorted(set(roster) - covered)]}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Coverage: {len(covered)}/{len(roster)} ({report['coveragePercent']}%). Added {len(imported)}. Report: {args.report}")


if __name__ == "__main__":
    main()
