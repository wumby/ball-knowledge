# Historical roster import

Build the local database for every NBA team-season from 1979–80 onward:

```sh
python3 Tools/import_historical_rosters.py --start 1979 --end 2026 \
  --output NBAAuctionDuel/Database/nba_historical_rosters.json
```

The importer caches responses in `.cache/nba-rosters`, waits three seconds
between uncached requests, and retries rate limits. It can safely be rerun: use
the same cache and output path after an interruption.

After validating the generated file, replace the current curated
`nba_seasons.json` bundle and update the Xcode resource reference if the file
name changes.
