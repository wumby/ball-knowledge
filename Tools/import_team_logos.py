#!/usr/bin/env python3
"""Ingest approved historical logo files into Xcode image sets.

The manifest is the source of truth: each team-logo entry identifies one era and
the asset name that must be supplied.  This script deliberately has no network
code.  Call it with a directory containing rights-cleared PNG files named after
the era assets (for example `team_njn_1976_2011.png`).
"""
import argparse
import json
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
ASSETS = ROOT / "BallKnowledge/Assets.xcassets"
MANIFEST = ROOT / "BallKnowledge/Database/OfflineVisualManifest.json"


def normalize(renderer: pathlib.Path, source: pathlib.Path, destination: pathlib.Path) -> None:
    # The renderer removes only edge-connected white background pixels and places
    # the logo on a transparent, square 512px canvas.
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(renderer), str(source), str(destination)], check=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_directory", type=pathlib.Path)
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    missing = []
    with tempfile.TemporaryDirectory() as temp:
        renderer = pathlib.Path(temp) / "normalize-logo"
        subprocess.run(["swiftc", str(ROOT / "Tools/normalize_logo.swift"), "-o", str(renderer)], check=True)
        for era in manifest.get("teamLogos", []):
            asset_name = era["assetName"]
            source = args.source_directory / f"{asset_name}.png"
            if not source.exists():
                missing.append(source.name)
                continue
            image_set = ASSETS / f"{asset_name}.imageset"
            normalize(renderer, source, image_set / "logo.png")
            (image_set / "Contents.json").write_text(json.dumps({
                "images": [{"filename": "logo.png", "idiom": "universal", "scale": "1x"}],
                "info": {"author": "xcode", "version": 1},
            }, indent=2) + "\n")
    if missing:
        print("Missing approved era files: " + ", ".join(missing))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
