import Foundation
import GameKit

/// Box Wars owns its score, season marker and Game Center board.  The rating
/// math intentionally delegates to `RankedLadder`, which is the published
/// Five Alive contract.
enum GridDuelLadder {
    static let leaderboardID = "com.jackziegler.hoopsiq.gridduel.monthly"
    static let initialRating = RankedLadder.initialRating
    static let baselineVersion = "box-wars-781-v3"
}

enum LeaderboardSubmissionStatus: Equatable {
    case synced
    case pending(score: Int)
    case failed(score: Int?, message: String)
}

@MainActor final class GridDuelLadderService: ObservableObject {
    @Published private var storedRating: Int
    @Published private(set) var lastSubmissionError: String?
    @Published private(set) var pendingSubmissionScore: Int?

    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: Calendar
    private let isGameCenterAuthenticated: () -> Bool
    private let submitScore: (Int, @escaping @Sendable (Error?) -> Void) -> Void
    private let ratingKey = "gridduel.monthly.rating"
    private let matchKey = "gridduel.monthly.submittedMatchIDs"
    private let seasonKey = "gridduel.monthly.season"
    private let mutationKey = "gridduel.monthly.lastLocalMutation"
    private let pendingBaselineSubmissionKey = "gridduel.monthly.pendingBaselineSubmission"
    private let pendingSubmissionScoreKey = "gridduel.monthly.pendingSubmissionScore"
    private let baselineVersionKey = "gridduel.monthly.baselineVersion"
    private let activeMatchKey = "gridduel.monthly.activeMatchID"

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = RankedLadder.seasonCalendar,
        isGameCenterAuthenticated: @escaping () -> Bool = { GKLocalPlayer.local.isAuthenticated },
        submitScore: @escaping (Int, @escaping @Sendable (Error?) -> Void) -> Void = { score, completion in
            GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [GridDuelLadder.leaderboardID], completionHandler: completion)
        }
    ) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        self.isGameCenterAuthenticated = isGameCenterAuthenticated
        self.submitScore = submitScore
        storedRating = defaults.object(forKey: ratingKey) as? Int ?? GridDuelLadder.initialRating
        pendingSubmissionScore = defaults.object(forKey: pendingSubmissionScoreKey) as? Int
        resetForCurrentSeasonIfNeeded()
        recoverUnresolvedRankedMatch()
    }

    var rating: Int { resetForCurrentSeasonIfNeeded(); submitPendingScoreIfPossible(); return storedRating }
    var tier: RankedTier { .forRating(rating) }
    var display: RankedDisplay { .init(rating: rating) }
    var matchmakingBucket: Int { rating / 100 }
    var leaderboardSubmissionStatus: LeaderboardSubmissionStatus {
        if let lastSubmissionError { return .failed(score: pendingSubmissionScore, message: lastSubmissionError) }
        if let pendingSubmissionScore { return .pending(score: pendingSubmissionScore) }
        return .synced
    }

    func recordCompletedMatch(id: String, didWin: Bool) -> RankedMatchResult? {
        recordCompletedMatch(id: id, outcome: didWin ? .win : .loss)
    }

    func recordCompletedMatch(id: String, outcome: RankedMatchOutcome) -> RankedMatchResult? {
        resetForCurrentSeasonIfNeeded()
        var ids = Set(defaults.stringArray(forKey: matchKey) ?? [])
        guard ids.insert(id).inserted else { return nil }
        let before = storedRating
        let after = outcome == .draw ? before : RankedLadder.rating(afterWin: outcome == .win, rating: before)
        storedRating = after
        defaults.set(after, forKey: ratingKey)
        defaults.set(now(), forKey: mutationKey)
        defaults.set(Array(ids.suffix(100)), forKey: matchKey)
        if outcome != .draw { queueSubmission(of: after) }
        return .init(ratingBefore: before, ratingAfter: after, outcome: outcome)
    }

    func beginActiveRankedMatch(id: String) { resetForCurrentSeasonIfNeeded(); defaults.set(id, forKey: activeMatchKey) }
    func finalizeActiveRankedMatch(id: String, outcome: RankedMatchOutcome) -> RankedMatchResult? {
        guard defaults.string(forKey: activeMatchKey) == id else { return nil }
        if outcome == .draw { defaults.removeObject(forKey: activeMatchKey); return .init(ratingBefore: storedRating, ratingAfter: storedRating, outcome: .draw) }
        let result = recordCompletedMatch(id: id, outcome: outcome)
        defaults.removeObject(forKey: activeMatchKey)
        return result
    }
    func recoverUnresolvedRankedMatch() {
        guard let id = defaults.string(forKey: activeMatchKey) else { return }
        _ = recordCompletedMatch(id: id, outcome: .loss)
        defaults.removeObject(forKey: activeMatchKey)
    }

    func refreshFromGameCenter() async {
        resetForCurrentSeasonIfNeeded(); submitPendingScoreIfPossible()
        guard !defaults.bool(forKey: pendingBaselineSubmissionKey), GKLocalPlayer.local.isAuthenticated else { return }
        do {
            guard let board = try await GKLeaderboard.loadLeaderboards(IDs: [GridDuelLadder.leaderboardID]).first else { return }
            let (local, _, _) = try await board.loadEntries(for: .global, timeScope: .allTime, range: NSRange(location: 1, length: 1))
            guard let local, (defaults.stringArray(forKey: matchKey) ?? []).isEmpty, defaults.object(forKey: mutationKey) == nil else { return }
            storedRating = Int(local.score); defaults.set(storedRating, forKey: ratingKey)
        } catch { lastSubmissionError = error.localizedDescription }
    }

    func retryPendingLeaderboardSubmission() {
        lastSubmissionError = nil
        submitPendingScoreIfPossible()
    }

    private func resetForCurrentSeasonIfNeeded() {
        let current = RankedLadder.seasonIdentifier(for: now(), calendar: calendar)
        // Keep baseline migrations one-shot and symmetric with Five Alive.
        // A persisted zero is intentionally excluded: it may be an earned
        // rating, and the stale-zero repair below has the mutation check.
        if defaults.string(forKey: baselineVersionKey) != GridDuelLadder.baselineVersion,
           (defaults.object(forKey: ratingKey) as? Int) != 0 {
            storedRating = GridDuelLadder.initialRating
            defaults.set(storedRating, forKey: ratingKey)
            defaults.removeObject(forKey: matchKey)
            defaults.removeObject(forKey: mutationKey)
            defaults.set(true, forKey: pendingBaselineSubmissionKey)
            markSubmissionPending(storedRating)
            defaults.set(GridDuelLadder.baselineVersion, forKey: baselineVersionKey)
            defaults.set(current, forKey: seasonKey)
            return
        }
        let seasonChanged = defaults.string(forKey: seasonKey).map { $0 != current } ?? false
        // Repair only the old unplayed zero-initialization bug. A zero with a
        // local mutation is a legitimate earned rating and stays.
        let staleZero = (defaults.object(forKey: ratingKey) as? Int) == 0
            && defaults.object(forKey: mutationKey) == nil
        let shouldReset = seasonChanged || staleZero
        if shouldReset {
            if seasonChanged || staleZero {
                storedRating = GridDuelLadder.initialRating; defaults.set(storedRating, forKey: ratingKey)
                defaults.set(true, forKey: pendingBaselineSubmissionKey)
                markSubmissionPending(storedRating)
            }
            defaults.removeObject(forKey: matchKey); defaults.removeObject(forKey: mutationKey)
        }
        defaults.set(GridDuelLadder.baselineVersion, forKey: baselineVersionKey)
        defaults.set(current, forKey: seasonKey)
        if shouldReset { defaults.removeObject(forKey: activeMatchKey) }
    }

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

@MainActor final class GridDuelLeaderboardService: ObservableObject {
    enum State: Equatable { case idle, loading, loaded, emptyFriends, signInRequired, failed(String) }
    @Published private(set) var rows: [GridDuelLeaderboardRow] = []
    @Published private(set) var state: State = .idle

    func load(filter: RankedLeaderboardFilter) async {
        guard GKLocalPlayer.local.isAuthenticated else { rows = []; state = .signInRequired; return }
        state = .loading; rows = []
        do {
            guard let board = try await GKLeaderboard.loadLeaderboards(IDs: [GridDuelLadder.leaderboardID]).first else { throw GridDuelLeaderboardError.unavailable }
            let (_, entries, _) = try await board.loadEntries(for: filter.playerScope, timeScope: .allTime, range: NSRange(location: 1, length: 100))
            rows = entries.map { .init(placement: $0.rank, playerID: $0.player.gamePlayerID, displayName: $0.player.displayName, mmr: Int($0.score), isLocalPlayer: $0.player.gamePlayerID == GKLocalPlayer.local.gamePlayerID) }
            state = filter == .friends && rows.isEmpty ? .emptyFriends : .loaded
        } catch { state = .failed(error.localizedDescription) }
    }
}

struct GridDuelLeaderboardRow: Identifiable, Equatable {
    let placement: Int
    let playerID: String
    let displayName: String
    let mmr: Int
    let isLocalPlayer: Bool
    var id: String { playerID }
    var tier: RankedTier { .forRating(mmr) }
    var display: RankedDisplay { .init(rating: mmr) }
}

private enum GridDuelLeaderboardError: LocalizedError { case unavailable; var errorDescription: String? { "The Box Wars leaderboard is unavailable right now." } }
