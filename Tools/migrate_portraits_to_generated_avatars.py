#!/usr/bin/env python3
"""Remove bundled third-party portraits and mark the catalog as app-generated.

Run this only when changing the product decision from licensed photographs to
native generated avatars.  It removes only `player_*.imageset` directories;
team-logo assets and their manifest data are left untouched.
"""
import json
import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parents[1]
ASSETS = ROOT / "BallKnowledge/Assets.xcassets"
MANIFEST = ROOT / "BallKnowledge/Database/OfflineVisualManifest.json"


def main():
    removed = 0
    for image_set in ASSETS.glob("player_*.imageset"):
        if image_set.is_dir():
            shutil.rmtree(image_set)
            removed += 1
    manifest = json.loads(MANIFEST.read_text())
    manifest["schemaVersion"] = 5
    manifest["portraitMode"] = "generatedAvatars"
    manifest["portraits"] = []
    manifest.pop("portraitLicenses", None)
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Removed {removed} third-party portrait asset sets. Generated avatars now cover all players.")


if __name__ == "__main__":
    main()
