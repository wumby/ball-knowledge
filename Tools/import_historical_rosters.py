#!/usr/bin/env python3
"""Build a complete NBA team-season roster bundle for NBA Auction Duel.

The importer covers the 1979-80 season through a chosen completed season,
discovers each league's team pages, caches every response, and can resume after
interruptions or rate limits. It emits TeamSeason JSON consumed by the iOS app.

Example:
  python3 Tools/import_historical_rosters.py --start 1979 --end 2026 \
    --output NBAAuctionDuel/Database/nba_historical_rosters.json
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import re
import time
from datetime import datetime, timezone
import urllib.error
import urllib.request
from pathlib import Path

BASE_URL = "https://www.basketball-reference.com"
USER_AGENT = "NBAAuctionDuel historical roster importer (local development)"


def clean(value: str) -> str:
    return html.unescape(re.sub(r"<.*?>", "", value)).strip()


def field(row: str, name: str) -> str:
    match = re.search(r'<t[dh][^>]*data-stat="' + re.escape(name) + r'"[^>]*>(.*?)</t[dh]>', row, re.S)
    return clean(match.group(1)) if match else ""


def number(value: str) -> float:
    try:
        return float(value)
    except ValueError:
        return 0.0


def fetch(url: str, cache: Path, pause: float) -> str:
    digest = hashlib.sha256(url.encode()).hexdigest()
    target = cache / f"{digest}.html"
    if target.exists():
        return target.read_text(encoding="utf-8")
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                body = response.read().decode("utf-8")
            target.write_text(body, encoding="utf-8")
            time.sleep(pause)
            return body
        except urllib.error.HTTPError as error:
            if error.code not in (429, 500, 502, 503, 504) or attempt == 4:
                raise
            time.sleep((attempt + 1) * 15)
    raise RuntimeError(f"Unable to fetch {url}")


def team_links(league_html: str, season_end: int) -> list[str]:
    links = re.findall(r'href="/teams/([A-Z]{3})/' + str(season_end) + r'\.html"', league_html)
    return sorted(set(links))


def player_rows(team_html: str) -> list[dict]:
    table_start = team_html.find('id="per_game_stats"')
    if table_start < 0:
        raise ValueError("Per-game table was not found")
    body_end = team_html.find("</tbody>", table_start)
    rows = re.findall(r"<tr[^>]*>(.*?)</tr>", team_html[table_start:body_end], re.S)
    players = []
    for row in rows:
        name, position = field(row, "name_display"), field(row, "pos")
        if not name or not position or name == "Player":
            continue
        games = int(number(field(row, "games")))
        minutes = number(field(row, "mp_per_g"))
        points = number(field(row, "pts_per_g"))
        rebounds = number(field(row, "trb_per_g"))
        assists = number(field(row, "ast_per_g"))
        steals = number(field(row, "stl_per_g"))
        blocks = number(field(row, "blk_per_g"))
        fg = number(field(row, "fg_pct")) * 100
        three = number(field(row, "fg3_pct")) * 100
        ft = number(field(row, "ft_pct")) * 100
        efficiency = max(0, fg - 45) * 0.18 + max(0, three - 33) * 0.08 + max(0, ft - 75) * 0.06
        rating = round(min(96, max(60, 60 + points * 0.65 + rebounds * 0.70 + assists * 0.75 + steals * 1.5 + blocks * 1.5 + efficiency)))
        player_link = re.search(r'<t[dh][^>]*data-stat="name_display"[^>]*>.*?href="/players/[^"]*/([^/".]+)\.html"', row, re.S)
        if not player_link:
            raise ValueError(f"Basketball-Reference player identifier missing for {name}")
        players.append({
            "playerID": player_link.group(1), "playerName": name, "position": position, "games": games, "minutes": minutes,
            "points": points, "rebounds": rebounds, "assists": assists, "steals": steals,
            "blocks": blocks, "fgPercent": fg, "threePercent": three, "ftPercent": ft,
            "overallRating": rating,
        })
    return players


def season_label(season_end: int) -> str:
    return f"{season_end - 1}\u2013{str(season_end)[-2:]}"


def write_checkpoint(records: list[dict], checkpoint: Path) -> None:
    checkpoint.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def build(start: int, end: int, cache: Path, pause: float, checkpoint: Path, existing: list[dict]) -> list[dict]:
    records: list[dict] = existing or []
    completed_ids = {record["id"] for record in records}
    for season_end in range(start + 1, end + 1):
        league = fetch(f"{BASE_URL}/leagues/NBA_{season_end}.html", cache, pause)
        label = season_label(season_end)
        for team in team_links(league, season_end):
            team_id = f"{team.lower()}-{season_end}"
            if team_id in completed_ids:
                continue
            url = f"{BASE_URL}/teams/{team}/{season_end}.html"
            try:
                players = player_rows(fetch(url, cache, pause))
            except (urllib.error.HTTPError, ValueError) as error:
                raise RuntimeError(f"Import stopped at {team} {season_end}: {error}") from error
            normalized = []
            for index, player in enumerate(players):
                normalized.append({"id": f"{team_id}-{index}", "season": label, "team": team, **player})
            records.append({"id": team_id, "team": team, "season": label, "players": normalized})
            completed_ids.add(team_id)
            print(f"Imported {team} {label}: {len(normalized)} players")
            write_checkpoint(records, checkpoint)
        write_checkpoint(records, checkpoint)
        print(f"Checkpointed {len(records)} team-seasons through {label}")
    return records


def validate(records: list[dict], start: int, end: int, cache: Path, pause: float) -> None:
    by_id = {record["id"]: record for record in records}
    errors = []
    for season_end in range(start + 1, end + 1):
        expected = {f"{team.lower()}-{season_end}" for team in team_links(fetch(f"{BASE_URL}/leagues/NBA_{season_end}.html", cache, pause), season_end)}
        actual = {team_id for team_id in by_id if team_id.endswith(f"-{season_end}")}
        missing = expected - actual
        unexpected = actual - expected
        empty = [team_id for team_id in expected & actual if not by_id[team_id].get("players")]
        if missing or unexpected or empty:
            errors.append(f"{season_label(season_end)}: missing={sorted(missing)}, unexpected={sorted(unexpected)}, empty={sorted(empty)}")
    if errors:
        raise RuntimeError("Archive validation failed:\n" + "\n".join(errors))


def archive_payload(records: list[dict], start: int, end: int) -> dict:
    return {
        "schemaVersion": 2,
        "source": "basketball-reference",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "coveredSeasons": [season_label(year) for year in range(start + 1, end + 1)],
        "teamSeasons": records,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--start", type=int, default=1979, help="First season start year (default: 1979)")
    parser.add_argument("--end", type=int, default=2026, help="Final season end year (default: 2026)")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cache", type=Path, default=Path(".cache/nba-rosters"))
    parser.add_argument("--checkpoint", type=Path, help="Resume state; defaults beside the output file")
    parser.add_argument("--pause", type=float, default=3.0, help="Seconds between uncached requests")
    parser.add_argument("--verify", action="store_true", help="Validate an existing archive without fetching roster pages")
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    checkpoint = args.checkpoint or args.output.with_suffix(".checkpoint.json")
    existing = []
    resume_source = checkpoint if checkpoint.exists() else args.output
    if resume_source.exists():
        loaded = json.loads(resume_source.read_text(encoding="utf-8"))
        existing = loaded.get("teamSeasons", []) if isinstance(loaded, dict) else loaded
        print(f"Resuming from {len(existing)} saved team-seasons in {resume_source}")
    if args.verify:
        validate(existing, args.start, args.end, args.cache, args.pause)
        print(f"Verified {len(existing)} team-seasons")
        return
    teams = build(args.start, args.end, args.cache, args.pause, checkpoint, existing)
    validate(teams, args.start, args.end, args.cache, args.pause)
    args.output.write_text(json.dumps(archive_payload(teams, args.start, args.end), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    checkpoint.unlink(missing_ok=True)
    print(f"Wrote and validated {len(teams)} team-seasons to {args.output}")


if __name__ == "__main__":
    main()
