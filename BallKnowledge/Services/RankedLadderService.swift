import Foundation
import GameKit

enum RankedTier: String, CaseIterable, Equatable {
    case bronze = "BRONZE"
    case silver = "SILVER"
    case gold = "GOLD"
    case platinum = "PLATINUM"
    case goat = "GOAT"

    static func forRating(_ rating: Int) -> RankedTier {
        switch rating {
        case ..<800: .bronze
        case 800..<950: .silver
        case 950..<1_100: .gold
        case 1_100..<1_250: .platinum
        default: .goat
        }
    }

    var requiredMMR: String {
        switch self {
        case .bronze: "0–799 MMR"
        case .silver: "800–949 MMR"
        case .gold: "950–1,099 MMR"
        case .platinum: "1,100–1,249 MMR"
        case .goat: "1,250+ MMR"
        }
    }

    func badgeAssetName(for game: CompetitiveGame) -> String {
        let prefix = game == .fiveAlive ? "FiveAliveRank" : "BoxWarsRank"
        return prefix + assetSuffix
    }

    var assetSuffix: String {
        switch self {
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        case .platinum: "Platinum"
        case .goat: "GOAT"
        }
    }

    /// Box Wars uses the player's current rank to set a beatable, predictable
    /// ranked AI opponent. Keep this alongside the tier thresholds so neither
    /// game's rank rules grow a second source of truth.
    var boxWarsAIProfile: BoxWarsAIProfile {
        switch self {
        case .bronze: .init(filledCellCount: 1, maximumAnswerPoints: 1, answerStrategy: .weakest)
        case .silver: .init(filledCellCount: 2, maximumAnswerPoints: 2, answerStrategy: .highestWithinCeiling)
        case .gold: .init(filledCellCount: 3, maximumAnswerPoints: 3, answerStrategy: .highestWithinCeiling)
        case .platinum: .init(filledCellCount: 4, maximumAnswerPoints: 4, answerStrategy: .highestWithinCeiling)
        case .goat: .init(filledCellCount: 4, maximumAnswerPoints: 5, answerStrategy: .strongest)
        }
    }
}

/// The Box Wars-specific portion of ranked AI difficulty.
struct BoxWarsAIProfile: Equatable, Sendable {
    enum AnswerStrategy: Equatable, Sendable {
        case weakest
        case highestWithinCeiling
        case strongest
    }

    let filledCellCount: Int
    let maximumAnswerPoints: Int
    let answerStrategy: AnswerStrategy
}

/// Bronze through Platinum are split into four 37/38-MMR divisions; GOAT is
/// deliberately a single, open-ended tier.
enum RankedDivision: String, CaseIterable, Equatable {
    case four = "IV", three = "III", two = "II", one = "I"

    static func forRating(_ rating: Int) -> RankedDivision? {
        let tier = RankedTier.forRating(rating)
        guard tier != .goat else { return nil }
        let base: Int = switch tier { case .bronze: 0; case .silver: 800; case .gold: 950; case .platinum: 1_100; case .goat: 0 }
        switch max(0, rating - base) {
        case 0..<38: return .four
        case 38..<76: return .three
        case 76..<113: return .two
        default: return .one
        }
    }
}

struct RankedDisplay: Equatable {
    let tier: RankedTier
    let division: RankedDivision?
    let rating: Int
    init(rating: Int) { self.rating = rating; tier = .forRating(rating); division = RankedDivision.forRating(rating) }
    var title: String { division.map { "\(tier.rawValue) \($0.rawValue)" } ?? tier.rawValue }
    var nextRankRating: Int? {
        guard tier != .goat else { return nil }
        let base: Int = switch tier { case .bronze: 0; case .silver: 800; case .gold: 950; case .platinum: 1_100; case .goat: 0 }
        return [38, 76, 113, 150].first(where: { rating < base + $0 }).map { base + $0 }
    }
}

/// The fixed skill contract for a Ranked-vs-AI match.  This is stored on the
/// match engine so rating changes after a match never alter its opponent.
enum RankedAIProfile: String, CaseIterable, Codable, Equatable {
    case bronze, silver, gold, platinum, goat

    init(tier: RankedTier) {
        switch tier {
        case .bronze: self = .bronze
        case .silver: self = .silver
        case .gold: self = .gold
        case .platinum: self = .platinum
        case .goat: self = .goat
        }
    }

    var tier: RankedTier {
        switch self {
        case .bronze: .bronze
        case .silver: .silver
        case .gold: .gold
        case .platinum: .platinum
        case .goat: .goat
        }
    }
}

enum RankedMatchOutcome: Equatable {
    case win
    case loss
    case draw
}

struct RankedMatchResult: Equatable {
    let ratingBefore: Int
    let ratingAfter: Int
    let outcome: RankedMatchOutcome

    var delta: Int { ratingAfter - ratingBefore }
    var didWin: Bool { outcome == .win }
    var isDraw: Bool { outcome == .draw }
    var tier: RankedTier { .forRating(ratingAfter) }
    var displayBefore: RankedDisplay { RankedDisplay(rating: ratingBefore) }
    var displayAfter: RankedDisplay { RankedDisplay(rating: ratingAfter) }
    var isPromotion: Bool { ratingAfter > ratingBefore && (displayBefore.tier != displayAfter.tier || displayBefore.division != displayAfter.division) }
    var isTierPromotion: Bool { ratingAfter > ratingBefore && displayBefore.tier != displayAfter.tier }
}

/// Transient presentation-only data. It deliberately wraps the finalized
/// result rather than recomputing a rating change in a view.
struct RankTransition: Identifiable, Equatable {
    enum Kind: Equatable { case unchanged, divisionPromotion, tierPromotion, demotion }

    let id: UUID
    let result: RankedMatchResult
    let game: CompetitiveGame

    init(id: UUID = UUID(), result: RankedMatchResult, game: CompetitiveGame) {
        self.id = id
        self.result = result
        self.game = game
    }

    var kind: Kind {
        guard !result.isDraw, result.ratingAfter != result.ratingBefore else { return .unchanged }
        if result.ratingAfter < result.ratingBefore { return .demotion }
        return result.displayBefore.tier != result.displayAfter.tier ? .tierPromotion : .divisionPromotion
    }
}

/// Game Center leaderboard IDs are permanent once created in App Store Connect.
/// Configure this as a monthly, recurring, high-to-low, most-recent-score leaderboard.
enum RankedLadder {
    static let leaderboardID = "com.jackziegler.hoopsiq.ranked.monthly"
    /// Five Alive starts just below Silver so a standard win against the
    /// 1,000-MMR ranked opponent places a new player at 800 MMR.
    static let initialRating = 781
    static let defaultOpponentRating = 1_000
    static let kFactor = 24.0
    static let minimumRating = 0
    static let maximumRating = 3_000

    /// All ranked season calculations use Gregorian UTC, matching the
    /// recurring Game Center leaderboard's reset boundary.
    static var seasonCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func seasonIdentifier(for date: Date, calendar: Calendar = RankedLadder.seasonCalendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    static func seasonDateRange(for date: Date = .now, calendar: Calendar = RankedLadder.seasonCalendar) -> String {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return "CURRENT MONTH" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d"
        let start = formatter.string(from: interval.start)
        formatter.dateFormat = "MMMM d, yyyy"
        let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return "\(start) – \(formatter.string(from: lastDay))"
    }

    static func rating(afterWin didWin: Bool, rating: Int, opponentRating: Int = defaultOpponentRating) -> Int {
        let expected = 1 / (1 + pow(10, Double(opponentRating - rating) / 400))
        let actual = didWin ? 1.0 : 0.0
        return min(maximumRating, max(minimumRating, Int((Double(rating) + kFactor * (actual - expected)).rounded())))
    }
}

enum RankedLeaderboardFilter: String, CaseIterable, Identifiable {
    case global = "Global"
    case friends = "Friends"
    var id: Self { self }
    var playerScope: GKLeaderboard.PlayerScope { self == .global ? .global : .friendsOnly }
}

struct RankedLeaderboardRow: Identifiable, Equatable {
    let placement: Int
    let playerID: String
    let displayName: String
    let mmr: Int
    let isLocalPlayer: Bool

    var id: String { playerID }
    var tier: RankedTier { .forRating(mmr) }
}

/// Presentation data is deliberately separate from leaderboard loading so a
/// match can begin even when Game Center has no current entry for a player.
struct RankedMatchup: Equatable {
    struct Participant: Equatable {
        let displayName: String
        let tier: RankedTier?
        let mmr: Int?

        var rankLabel: String { tier?.rawValue ?? "RANK UNAVAILABLE" }
    }

    let local: Participant
    let opponent: Participant
    let kind: RankedMatchKind

    static func pvp(localName: String, localRating: Int, opponentName: String, opponentRow: RankedLeaderboardRow?) -> Self {
        Self(local: .init(displayName: localName, tier: .forRating(localRating), mmr: localRating),
             opponent: .init(displayName: opponentRow?.displayName ?? opponentName, tier: opponentRow?.tier, mmr: opponentRow?.mmr),
             kind: .pvp)
    }

    static func aiFallback(localName: String, localRating: Int, profile: RankedAIProfile) -> Self {
        Self(local: .init(displayName: localName, tier: .forRating(localRating), mmr: localRating),
             opponent: .init(displayName: "RANKED AI", tier: profile.tier, mmr: nil),
             kind: .aiFallback)
    }
}

@MainActor final class RankedLeaderboardService: ObservableObject {
    enum State: Equatable { case idle, loading, loaded, emptyFriends, signInRequired, failed(String) }
    @Published private(set) var rows: [RankedLeaderboardRow] = []
    @Published private(set) var pinnedLocalPlayer: RankedLeaderboardRow?
    @Published private(set) var state: State = .idle

    func load(filter: RankedLeaderboardFilter) async {
        guard GKLocalPlayer.local.isAuthenticated else { state = .signInRequired; rows = []; pinnedLocalPlayer = nil; return }
        state = .loading; rows = []; pinnedLocalPlayer = nil
        do {
            let boards = try await GKLeaderboard.loadLeaderboards(IDs: [RankedLadder.leaderboardID])
            guard let board = boards.first else { throw RankedLeaderboardError.unavailable }
            let (local, entries, _) = try await board.loadEntries(for: filter.playerScope, timeScope: .allTime, range: NSRange(location: 1, length: 100))
            let loadedRows = entries.map(Self.row)
            rows = loadedRows
            if filter == .global, let local {
                let localRow = Self.row(local)
                pinnedLocalPlayer = loadedRows.contains(where: { $0.playerID == localRow.playerID }) ? nil : localRow
            }
            state = filter == .friends && loadedRows.isEmpty ? .emptyFriends : .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    nonisolated static func row(placement: Int, playerID: String, displayName: String, mmr: Int, isLocalPlayer: Bool) -> RankedLeaderboardRow {
        RankedLeaderboardRow(placement: placement, playerID: playerID, displayName: displayName, mmr: mmr, isLocalPlayer: isLocalPlayer)
    }

    static func matchup(localName: String, localRating: Int, opponentName: String, opponentRow: RankedLeaderboardRow?) -> RankedMatchup {
        .pvp(localName: localName, localRating: localRating, opponentName: opponentName, opponentRow: opponentRow)
    }

    private static func row(_ entry: GKLeaderboard.Entry) -> RankedLeaderboardRow {
        row(placement: entry.rank, playerID: entry.player.gamePlayerID, displayName: entry.player.displayName, mmr: Int(entry.score), isLocalPlayer: entry.player.gamePlayerID == GKLocalPlayer.local.gamePlayerID)
    }
}

private enum RankedLeaderboardError: LocalizedError { case unavailable; var errorDescription: String? { "The monthly ranked leaderboard is unavailable right now." } }

@MainActor final class RankedLadderService: ObservableObject {
    @Published private var storedRating: Int
    @Published private(set) var lastSubmissionError: String?
    @Published private(set) var pendingSubmissionScore: Int?

    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: Calendar
    private let isGameCenterAuthenticated: () -> Bool
    private let submitScore: (Int, @escaping @Sendable (Error?) -> Void) -> Void
    private let ratingKey = "ranked.monthly.rating"
    private let matchKey = "ranked.monthly.submittedMatchIDs"
    private let seasonKey = "ranked.monthly.season"
    private let mutationKey = "ranked.monthly.lastLocalMutation"
    private let pendingBaselineSubmissionKey = "ranked.monthly.pendingBaselineSubmission"
    private let pendingSubmissionScoreKey = "ranked.monthly.pendingSubmissionScore"
    // Bump this when a published ladder baseline must be migrated. It keeps
    // the reset one-shot rather than resetting a player on every launch.
    private let baselineVersionKey = "ranked.monthly.baselineVersion"
    private let baselineVersion = "five-alive-781-v3"
    private let activeMatchKey = "ranked.monthly.activeMatchID"

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = RankedLadder.seasonCalendar,
        isGameCenterAuthenticated: @escaping () -> Bool = { GKLocalPlayer.local.isAuthenticated },
        submitScore: @escaping (Int, @escaping @Sendable (Error?) -> Void) -> Void = { score, completion in
            GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [RankedLadder.leaderboardID], completionHandler: completion)
        }
    ) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        self.isGameCenterAuthenticated = isGameCenterAuthenticated
        self.submitScore = submitScore
        self.storedRating = defaults.object(forKey: "ranked.monthly.rating") as? Int ?? RankedLadder.initialRating
        self.pendingSubmissionScore = defaults.object(forKey: pendingSubmissionScoreKey) as? Int
        resetForCurrentSeasonIfNeeded()
        recoverUnresolvedRankedMatch()
    }

    /// Checking through this accessor means long-lived UI services also reset
    /// when their first read happens after the UTC month rolls over.
    var rating: Int {
        resetForCurrentSeasonIfNeeded()
        submitPendingScoreIfPossible()
        return storedRating
    }
    var tier: RankedTier { RankedTier.forRating(rating) }
    var display: RankedDisplay { RankedDisplay(rating: rating) }
    var matchmakingBucket: Int { rating / 100 }
    var leaderboardSubmissionStatus: LeaderboardSubmissionStatus {
        if let lastSubmissionError { return .failed(score: pendingSubmissionScore, message: lastSubmissionError) }
        if let pendingSubmissionScore { return .pending(score: pendingSubmissionScore) }
        return .synced
    }

    func recordCompletedMatch(id: String, didWin: Bool) -> RankedMatchResult? {
        resetForCurrentSeasonIfNeeded()
        var submittedIDs = Set(defaults.stringArray(forKey: matchKey) ?? [])
        guard submittedIDs.insert(id).inserted else { return nil }

        let before = storedRating
        let after = RankedLadder.rating(afterWin: didWin, rating: before)
        storedRating = after
        defaults.set(after, forKey: ratingKey)
        defaults.set(now(), forKey: mutationKey)
        // Keep a bounded idempotency journal so replayed end packets cannot change rank twice.
        defaults.set(Array(submittedIDs.suffix(100)), forKey: matchKey)
        queueSubmission(of: after)
        return RankedMatchResult(ratingBefore: before, ratingAfter: after, outcome: didWin ? .win : .loss)
    }

    /// Persist before gameplay so force-quitting cannot evade a ranked loss.
    func beginActiveRankedMatch(id: String) {
        resetForCurrentSeasonIfNeeded()
        defaults.set(id, forKey: activeMatchKey)
    }

    /// The local journal is authoritative. Game Center submission remains
    /// best-effort inside recordCompletedMatch and never blocks this path.
    func finalizeActiveRankedMatch(id: String, outcome: RankedMatchOutcome) -> RankedMatchResult? {
        guard defaults.string(forKey: activeMatchKey) == id else { return nil }
        if outcome == .draw {
            defaults.removeObject(forKey: activeMatchKey)
            return RankedMatchResult(ratingBefore: storedRating, ratingAfter: storedRating, outcome: .draw)
        }
        let result: RankedMatchResult?
        switch outcome {
        case .draw: result = nil
        case .win: result = recordCompletedMatch(id: id, didWin: true)
        case .loss: result = recordCompletedMatch(id: id, didWin: false)
        }
        defaults.removeObject(forKey: activeMatchKey)
        return result
    }

    func recoverUnresolvedRankedMatch() {
        guard let id = defaults.string(forKey: activeMatchKey) else { return }
        _ = recordCompletedMatch(id: id, didWin: false)
        defaults.removeObject(forKey: activeMatchKey)
    }

    func refreshFromGameCenter() async {
        resetForCurrentSeasonIfNeeded()
        submitPendingScoreIfPossible()
        // Until the new baseline has been accepted by Game Center, the
        // previous leaderboard score is known to be stale.
        guard !defaults.bool(forKey: pendingBaselineSubmissionKey) else { return }
        guard GKLocalPlayer.local.isAuthenticated else { return }
        do {
            let boards = try await GKLeaderboard.loadLeaderboards(IDs: [RankedLadder.leaderboardID])
            guard let board = boards.first else { return }
            let (local, _, _) = try await board.loadEntries(for: .global, timeScope: .allTime, range: NSRange(location: 1, length: 1))
            guard let local else { return }
            let hasLocalResult = !(defaults.stringArray(forKey: matchKey) ?? []).isEmpty
            // A leaderboard response has no safe local mutation ordering. Keep
            // the result that was persisted on this device for this season.
            guard !hasLocalResult, defaults.object(forKey: mutationKey) == nil else { return }
            storedRating = Int(local.score)
            defaults.set(storedRating, forKey: ratingKey)
        } catch {
            lastSubmissionError = error.localizedDescription
        }
    }

    func retryPendingLeaderboardSubmission() {
        lastSubmissionError = nil
        submitPendingScoreIfPossible()
    }

    private func resetForCurrentSeasonIfNeeded() {
        let currentSeason = RankedLadder.seasonIdentifier(for: now(), calendar: calendar)
        if defaults.string(forKey: baselineVersionKey) != baselineVersion,
           (defaults.object(forKey: ratingKey) as? Int) != 0 {
            storedRating = RankedLadder.initialRating
            defaults.set(storedRating, forKey: ratingKey)
            defaults.removeObject(forKey: matchKey)
            defaults.removeObject(forKey: mutationKey)
            defaults.set(true, forKey: pendingBaselineSubmissionKey)
            markSubmissionPending(storedRating)
            defaults.set(currentSeason, forKey: seasonKey)
            defaults.set(baselineVersion, forKey: baselineVersionKey)
            return
        }
        defaults.set(baselineVersion, forKey: baselineVersionKey)
        guard let storedSeason = defaults.string(forKey: seasonKey) else {
            // A missing marker denotes a fresh/new-season state and receives
            // the baseline immediately. Zero is the one valid rating that
            // must never be mistaken for an absent value.
            if (defaults.object(forKey: ratingKey) as? Int) != 0 {
                storedRating = RankedLadder.initialRating
                defaults.set(storedRating, forKey: ratingKey)
                defaults.removeObject(forKey: matchKey)
            }
            defaults.set(currentSeason, forKey: seasonKey)
            return
        }
        guard storedSeason != currentSeason else { return }

        storedRating = RankedLadder.initialRating
        defaults.set(storedRating, forKey: ratingKey)
        defaults.removeObject(forKey: matchKey)
        defaults.removeObject(forKey: mutationKey)
        defaults.removeObject(forKey: activeMatchKey)
        defaults.set(true, forKey: pendingBaselineSubmissionKey)
        markSubmissionPending(storedRating)
        defaults.set(currentSeason, forKey: seasonKey)
    }

    /// Keep the newest locally persisted MMR until Game Center acknowledges
    /// that exact value. This covers offline matches and avoids an older
    /// in-flight submission clearing a newer rating.
    private func queueSubmission(of score: Int) {
        lastSubmissionError = nil
        markSubmissionPending(score)
        submitPendingScoreIfPossible()
    }

    private func markSubmissionPending(_ score: Int) {
        defaults.set(score, forKey: pendingSubmissionScoreKey)
        pendingSubmissionScore = score
    }

    private func submitPendingScoreIfPossible() {
        guard let score = defaults.object(forKey: pendingSubmissionScoreKey) as? Int,
              isGameCenterAuthenticated() else { return }
        submitScore(score) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.lastSubmissionError = error.localizedDescription }
                else if self.pendingSubmissionScore == score {
                    self.defaults.removeObject(forKey: self.pendingSubmissionScoreKey)
                    self.defaults.removeObject(forKey: self.pendingBaselineSubmissionKey)
                    self.pendingSubmissionScore = nil
                    self.lastSubmissionError = nil
                } else {
                    self.submitPendingScoreIfPossible()
                }
            }
        }
    }
}
