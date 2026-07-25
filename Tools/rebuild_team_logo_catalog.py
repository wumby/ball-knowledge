#!/usr/bin/env python3
"""Derive the team-logo catalog from the Basketball Reference season archive.

The archive records a logo URL for every team-season through 2022-23.  This
tool fetches those source images, groups only consecutive identical bytes, and
normalizes one PNG per resulting era.  It also writes a checked-in audit file
used by ``validate_offline_visuals.py`` so validation never depends on the
network.
"""
import concurrent.futures
import hashlib
import json
import pathlib
import subprocess
import tempfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
ASSETS = ROOT / "BallKnowledge/Assets.xcassets"
MANIFEST = ROOT / "BallKnowledge/Database/OfflineVisualManifest.json"
ROSTERS = ROOT / "BallKnowledge/Database/nba_historical_rosters.json"
AUDIT = ROOT / "BallKnowledge/Database/TeamLogoSeasonAudit.json"
ARCHIVE_ENDPOINT = "https://cdn.ssref.net/req/202301032/tlogo/bbr/{team}-{end_year}.png"
NBA_LOGO_ENDPOINT = "https://cdn.nba.com/logos/nba/{team_id}/global/L/logo.svg"
SOURCE = "Basketball Reference historical team-logo archive"
RIGHTS = "Team marks; used for historical reference. Permission required before distribution."


def fetch(row):
    team, season = row["team"], int(row["season"][:4])
    end_year = season + 1
    url = ARCHIVE_ENDPOINT.format(team=team, end_year=end_year)
    with urllib.request.urlopen(url, timeout=45) as response:
        data = response.read()
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError(f"{team} {row['season']} did not return a PNG")
    return {"team": team, "season": season, "url": url, "data": data,
            "sourceSHA256": hashlib.sha256(data).hexdigest()}


def fetch_current_logo(team, team_id):
    """Rasterize the official NBA SVG once so the app remains entirely offline."""
    url = NBA_LOGO_ENDPOINT.format(team_id=team_id)
    with urllib.request.urlopen(url, timeout=45) as response:
        svg = response.read()
    with tempfile.TemporaryDirectory() as temp:
        source = pathlib.Path(temp) / "logo.svg"
        raster = pathlib.Path(temp) / "logo.png"
        source.write_bytes(svg)
        subprocess.run(["sips", "-s", "format", "png", str(source), "--out", str(raster)], check=True,
                       stdout=subprocess.DEVNULL)
        png = raster.read_bytes()
    return {"url": url, "data": png, "sourceSHA256": hashlib.sha256(png).hexdigest()}


def eras(seasons):
    result = []
    # Archive rows are ordered by season across the league, so group by team
    # before examining consecutive seasons.
    for image in sorted(seasons, key=lambda item: (item["team"], item["season"])):
        if (not result or result[-1]["team"] != image["team"] or
                result[-1]["sourceSHA256"] != image["sourceSHA256"] or
                result[-1]["lastSeason"] + 1 != image["season"]):
            result.append({**image, "firstSeason": image["season"], "lastSeason": image["season"]})
        else:
            result[-1]["lastSeason"] = image["season"]
    return result


def main():
    data = json.loads(ROSTERS.read_text())
    rows = data.get("teamSeasons", data)
    historical = [row for row in rows if int(row["season"][:4]) <= 2022]
    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as pool:
        source_rows = list(pool.map(fetch, historical))
    by_key = {(row["team"], row["season"]): row for row in source_rows}

    # The archive ends in 2022-23.  Its final source image remains the official
    # mark for every active team unless a post-archive rebrand intervened.  The
    # explicit overrides below use the already-approved official logo asset
    # supplied with this project and make the boundary auditable.
    current_overrides = {
        "LAC": (2025, "1610612746"), "ORL": (2024, "1610612753"),
        "PHO": (2023, "1610612756"), "UTA": (2024, "1610612762"),
    }
    official_images = {team: fetch_current_logo(team, team_id) for team, (_, team_id) in current_overrides.items()}
    future = []
    for row in rows:
        season = int(row["season"][:4])
        if season < 2023:
            continue
        team = row["team"]
        base = by_key[(team, 2022)]
        rebrand = current_overrides.get(team)
        image = official_images[team] if rebrand and season >= rebrand[0] else base
        future.append({"team": team, "season": season, "url": image["url"], "data": image["data"],
                       "sourceSHA256": image["sourceSHA256"], "official": True})
    all_rows = source_rows + future
    derived = eras(all_rows)
    for era in derived:
        era["assetName"] = f"team_{era['team'].lower()}_{era['firstSeason']}_{era['lastSeason']}"

    # Both archive PNGs and rasterized official SVGs are normalized here.
    with tempfile.TemporaryDirectory() as temp:
        renderer = pathlib.Path(temp) / "normalize-logo"
        subprocess.run(["swiftc", str(ROOT / "Tools/normalize_logo.swift"), "-o", str(renderer)], check=True)
        for era in derived:
            source = pathlib.Path(temp) / f"{era['assetName']}.png"
            source.write_bytes(era["data"])
            image_set = ASSETS / f"{era['assetName']}.imageset"
            image_set.mkdir(parents=True, exist_ok=True)
            subprocess.run([str(renderer), str(source), str(image_set / "logo.png")], check=True)
            (image_set / "Contents.json").write_text(json.dumps({
                "images": [{"filename": "logo.png", "idiom": "universal", "scale": "1x"}],
                "info": {"author": "xcode", "version": 1},
            }, indent=2) + "\n")

    manifest = json.loads(MANIFEST.read_text())
    manifest["teamLogos"] = [{
        "assetName": era["assetName"], "team": era["team"],
        "firstSeason": era["firstSeason"], "lastSeason": era["lastSeason"],
        "source": "Official NBA/team branding" if era.get("official") else SOURCE,
        "rights": RIGHTS, "sourceURL": era["url"], "sourceSHA256": era["sourceSHA256"],
    } for era in derived]
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
    expected = []
    for row in all_rows:
        asset = next(era["assetName"] for era in derived if era["team"] == row["team"] and era["firstSeason"] <= row["season"] <= era["lastSeason"])
        expected.append({"team": row["team"], "season": row["season"], "assetName": asset,
                         "sourceSHA256": row["sourceSHA256"]})
    AUDIT.write_text(json.dumps({"source": SOURCE, "teamSeasons": expected}, indent=2) + "\n")
    print(f"Derived {len(derived)} eras for {len(expected)} team-seasons.")


if __name__ == "__main__":
    main()
