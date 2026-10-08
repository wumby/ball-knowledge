# Ranked Ladder launch configuration

The app code expects these Game Center components for the `com.jackziegler.HoopsIQ` bundle ID.

## Matchmaking queues

- Five Alive queue: `com.jackziegler.hoopsiq.ranked`
- Box Wars queue: `com.jackziegler.hoopsiq.gridduel.ranked`
- Players: exactly 2.
- Match rule inputs: integer `ratingBucket`, `minimumRatingBucket`, and `maximumRatingBucket`, calculated from current MMR in 100-point buckets.
- Prefer the same bucket, then adjacent buckets; allow a broad fallback after 45 seconds.
- Keep ranked clients in one multiplayer compatibility group per supported app version.
- Enable either queue in the app only after its App Store Connect definition and rules are live. Until then, use the platform bucket request and retain the timed ranked-AI fallback. Queue errors other than a missing queue are surfaced to the player.

## Leaderboards

- Leaderboard ID: `com.jackziegler.hoopsiq.ranked.monthly`
- Name: `Hoops IQ Monthly Ladder`
- Type: recurring, UTC monthly restart.
- Score type: integer MMR, high-to-low sort, **Most Recent Score** submission.
- Range: 0–3000; suffix: `MMR`.

- Box Wars leaderboard ID: `com.jackziegler.hoopsiq.gridduel.monthly`
- Name: `Box Wars Monthly Ladder`
- Use the same recurring UTC-monthly, integer MMR, high-to-low, most-recent-score configuration.

Five Alive defaults every new monthly season to 781 MMR. A win against the standard 1,000-MMR opponent awards 19 MMR and enters Silver at 800. Tier thresholds are Bronze below 800, Silver 800–949, Gold 950–1099, Platinum 1100–1249, and GOAT at 1250 or higher. The recurring UTC reset is required: an all-time leaderboard could otherwise refresh an old remote score over the local monthly reset.

Before release, test queueing and score submission with two Game Center-enabled TestFlight accounts. The current design is peer-hosted: it validates completion and prevents local duplicate submissions, but it is not server-authoritative anti-cheat.
