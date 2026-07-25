# Historical roster import

Build the local database for every NBA team-season from 1979–80 onward:

```sh
python3 Tools/import_historical_rosters.py --start 1979 --end 2026 \
  --output BallKnowledge/Database/nba_historical_rosters.json
```

The importer caches responses in `.cache/nba-rosters`, waits three seconds
between uncached requests, retries rate limits, and writes resumable progress to
`nba_historical_rosters.checkpoint.json`. It validates every season's expected
team count before replacing the app bundle, so an incomplete checkpoint is never
shipped. It can safely be rerun after an interruption with the same cache and
output path.

Run `--verify` with the same arguments to recheck a completed archive without
refetching roster pages.
