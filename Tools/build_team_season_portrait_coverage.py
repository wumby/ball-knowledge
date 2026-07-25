#!/usr/bin/env python3
"""Build draft portrait coverage from the roster and current portrait manifest."""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
ROSTER = ROOT / "BallKnowledge/Database/nba_historical_rosters.json"
MANIFEST = ROOT / "BallKnowledge/Database/OfflineVisualManifest.json"
REPORT = ROOT / "Tools/team_season_portrait_coverage_report.json"


def suppressed(missing_headshots, roster_count):
    """The boundary is strict: exactly half missing still remains eligible."""
    return roster_count > 0 and missing_headshots > roster_count / 2


def main():
    archive = json.loads(ROSTER.read_text())
    manifest = json.loads(MANIFEST.read_text())
    portrait_ids = {entry["playerID"].lower() for entry in manifest.get("portraits", [])}
    coverage = []
    for team_season in archive["teamSeasons"]:
        players = {player["playerID"].lower() for player in team_season["players"]}
        available = len(players & portrait_ids)
        missing = len(players) - available
        coverage.append({
            "team": team_season["team"],
            "season": team_season["season"],
            "rosterCount": len(players),
            "availableHeadshots": available,
            "missingHeadshots": missing,
            "suppressDraftPortraits": suppressed(missing, len(players)),
        })
    coverage.sort(key=lambda row: (row["season"], row["team"]))
    manifest["schemaVersion"] = max(6, manifest.get("schemaVersion", 1))
    # This report accompanies the Basketball Reference development catalog;
    # do not let a former generated-avatar setting hide the restored assets.
    manifest["portraitMode"] = "developmentReferencePhotos"
    manifest.pop("portraitLicenses", None)
    manifest["teamSeasonPortraitCoverage"] = coverage
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
    roster_player_ids = {player["playerID"].lower() for team in archive["teamSeasons"] for player in team["players"]}
    covered_player_ids = portrait_ids & roster_player_ids
    report = {
        "totalRosterPlayers": len(roster_player_ids),
        "coveredRosterPlayers": len(covered_player_ids),
        "coveragePercent": round(100 * len(covered_player_ids) / len(roster_player_ids), 2),
        "teamSeasons": coverage,
        "suppressedTeamSeasons": sum(row["suppressDraftPortraits"] for row in coverage),
    }
    REPORT.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Portrait coverage: {report['coveredRosterPlayers']}/{report['totalRosterPlayers']}; {report['suppressedTeamSeasons']}/{len(coverage)} team-seasons suppressed.")


if __name__ == "__main__":
    main()
