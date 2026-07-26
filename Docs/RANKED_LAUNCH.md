# Ranked Ladder launch configuration

The app code expects these Game Center components for the `com.jackziegler.HoopsIQ` bundle ID.

## Matchmaking queue

- Queue name: `com.jackziegler.hoopsiq.ranked`
- Players: exactly 2.
- Match rule input: integer `ratingBucket`, calculated as current MMR divided by 100.
- Prefer the same bucket, then adjacent buckets; allow a broad fallback after 45 seconds.
- Keep ranked clients in one multiplayer compatibility group per supported app version.

## Leaderboard

- Leaderboard ID: `com.jackziegler.hoopsiq.ranked.monthly`
- Name: `Hoops IQ Monthly Ladder`
- Type: recurring, UTC monthly restart.
- Score type: integer MMR, high-to-low sort, **Most Recent Score** submission.
- Range: 0–3000; suffix: `MMR`.

The app defaults an unranked player to 1,000 MMR. Tier thresholds are Bronze below 800, Silver 800–949, Gold 950–1099, Platinum 1100–1249, and GOAT at 1250 or higher.

Before release, test queueing and score submission with two Game Center-enabled TestFlight accounts. The current design is peer-hosted: it validates completion and prevents local duplicate submissions, but it is not server-authoritative anti-cheat.
