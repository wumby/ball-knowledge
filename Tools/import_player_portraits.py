#!/usr/bin/env python3
"""Import Basketball Reference player headshots into the offline Xcode catalog.

Run only after confirming the intended use is permitted by the image source.
The roster's stable playerID is Basketball Reference's player key.
"""
import argparse
import concurrent.futures
import json
import pathlib
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
ROSTER = ROOT / "BallKnowledge/Database/nba_historical_rosters.json"
ASSETS = ROOT / "BallKnowledge/Assets.xcassets"
MANIFEST = ROOT / "BallKnowledge/Database/OfflineVisualManifest.json"
REPORT = ROOT / "Tools/player_portrait_import_report.json"
SOURCE = "Basketball Reference headshots"
RIGHTS = "Source permission required before distribution"
PORTRAIT_MODE = "developmentReferencePhotos"


def players():
    data = json.loads(ROSTER.read_text())
    records = (player for team in data["teamSeasons"] for player in team["players"])
    return {player["playerID"].lower(): player["playerName"] for player in records}


def source_url(player_id):
    return f"https://www.basketball-reference.com/req/202106291/images/headshots/{player_id}.jpg"


class RequestPacer:
    """Spaces request starts globally, even when downloads run concurrently."""

    def __init__(self, delay):
        self.delay = delay
        self.next_start = 0.0
        self.lock = threading.Lock()

    def wait(self):
        with self.lock:
            now = time.monotonic()
            wait = max(0.0, self.next_start - now)
            self.next_start = max(now, self.next_start) + self.delay
        if wait:
            time.sleep(wait)


def download(player_id, destination, pacer, retries):
    url = source_url(player_id)
    for attempt in range(retries + 1):
        pacer.wait()
        request = urllib.request.Request(url, headers={"User-Agent": "BallKnowledge asset importer/1.0"})
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                content_type = response.headers.get_content_type()
                if not content_type.startswith("image/"):
                    return None, f"unexpected content type: {content_type}"
                with open(destination, "wb") as output:
                    shutil.copyfileobj(response, output)
            if destination.stat().st_size == 0:
                return None, "empty response"
            return url, None
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return None, "not found"
            message = f"HTTP {error.code}"
        except (urllib.error.URLError, TimeoutError) as error:
            message = str(error.reason if hasattr(error, "reason") else error)
        if attempt < retries:
            time.sleep(1.0 * (attempt + 1))
    return None, message


def write_imageset(player_id, source_path):
    asset_name = f"player_{player_id}"
    image_set = ASSETS / f"{asset_name}.imageset"
    image_set.mkdir(parents=True, exist_ok=True)
    temporary_output = image_set / "portrait.importing.jpg"
    output = image_set / "portrait.jpg"
    temporary_output.unlink(missing_ok=True)
    result = subprocess.run(
        ["sips", "--cropToHeightWidth", "120", "120", str(source_path), "--out", str(temporary_output)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if result.returncode != 0 or not temporary_output.exists():
        temporary_output.unlink(missing_ok=True)
        if not output.exists() and not (image_set / "Contents.json").exists():
            image_set.rmdir()
        return None
    temporary_output.replace(output)
    (image_set / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "portrait.jpg", "idiom": "universal", "scale": "1x"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")
    return asset_name


def valid_existing_asset(player_id):
    image_set = ASSETS / f"player_{player_id}.imageset"
    portrait = image_set / "portrait.jpg"
    return (image_set / "Contents.json").exists() and portrait.exists() and portrait.stat().st_size > 0


def import_one(player_id, player_name, temp_dir, pacer, retries):
    temporary_path = temp_dir / f"{player_id}.jpg"
    url, error = download(player_id, temporary_path, pacer, retries)
    if not url:
        return player_id, player_name, None, error
    asset_name = write_imageset(player_id, temporary_path)
    if not asset_name:
        return player_id, player_name, None, "unreadable image"
    return player_id, player_name, asset_name, None


def manifest_entry(player_id, player_name, asset_name):
    return {
        "assetName": asset_name,
        "playerID": player_id,
        "playerName": player_name,
        "source": SOURCE,
        "sourceURL": source_url(player_id),
        "rights": RIGHTS,
    }


def write_report(path, report):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, help="Import only this many missing portraits")
    parser.add_argument("--player-ids", help="Comma-separated stable player IDs to prioritize")
    parser.add_argument("--delay", type=float, default=0.10, help="Minimum seconds between all request starts")
    parser.add_argument("--workers", type=int, default=4, help="Concurrent download workers")
    parser.add_argument("--retries", type=int, default=2, help="Retries for transient download failures")
    parser.add_argument("--report", type=pathlib.Path, default=REPORT, help="JSON summary output path")
    args = parser.parse_args()
    if args.delay < 0 or args.workers < 1 or args.retries < 0:
        parser.error("delay must be nonnegative, workers must be positive, and retries must be nonnegative")

    roster_players = players()
    manifest = json.loads(MANIFEST.read_text())
    existing_entries = manifest.get("portraits", [])
    known = {entry["playerID"].lower() for entry in existing_entries}
    requested = {item.strip().lower() for item in args.player_ids.split(",")} if args.player_ids else None
    candidates = [(player_id, player_name) for player_id, player_name in sorted(roster_players.items())
                  if player_id not in known and (requested is None or player_id in requested)]
    if args.limit is not None:
        candidates = candidates[:args.limit]

    imported = []
    already_present = []
    failures = []
    for player_id, player_name in candidates[:]:
        if valid_existing_asset(player_id):
            imported.append(manifest_entry(player_id, player_name, f"player_{player_id}"))
            already_present.append(player_id)
    candidates = [(player_id, player_name) for player_id, player_name in candidates if player_id not in set(already_present)]

    pacer = RequestPacer(args.delay)
    with tempfile.TemporaryDirectory() as directory:
        temp_dir = pathlib.Path(directory)
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
            futures = [executor.submit(import_one, player_id, player_name, temp_dir, pacer, args.retries)
                       for player_id, player_name in candidates]
            for index, future in enumerate(concurrent.futures.as_completed(futures), 1):
                player_id, player_name, asset_name, error = future.result()
                if asset_name:
                    imported.append(manifest_entry(player_id, player_name, asset_name))
                    print(f"[{index}/{len(candidates)}] imported: {player_name}")
                else:
                    failures.append({"playerID": player_id, "playerName": player_name, "reason": error})
                    print(f"[{index}/{len(candidates)}] skipped: {player_id} ({error})")
                if index % 50 == 0:
                    manifest["portraits"] = sorted(existing_entries + imported, key=lambda entry: entry["playerID"])
                    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")

    manifest["portraits"] = sorted(existing_entries + imported, key=lambda entry: entry["playerID"])
    manifest["schemaVersion"] = max(6, manifest.get("schemaVersion", 1))
    # This importer is intentionally only for local development/testing. It
    # must never identify Basketball Reference images as commercial assets.
    manifest["portraitMode"] = PORTRAIT_MODE
    manifest.pop("portraitLicenses", None)
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
    covered = {entry["playerID"].lower() for entry in manifest["portraits"]} & set(roster_players)
    report = {
        "totalRosterPlayers": len(roster_players),
        "coveredRosterPlayers": len(covered),
        "coveragePercent": round(100 * len(covered) / len(roster_players), 2),
        "addedThisRun": len(imported),
        "alreadyPresentAssetSets": len(already_present),
        "unavailableOrFailed": sorted(failures, key=lambda entry: entry["playerID"]),
    }
    write_report(args.report, report)
    print(f"Coverage: {len(covered)}/{len(roster_players)} ({report['coveragePercent']}%).")
    print(f"Added {len(imported)} manifest entries; {len(failures)} unavailable or failed. Report: {args.report}")


if __name__ == "__main__":
    main()
