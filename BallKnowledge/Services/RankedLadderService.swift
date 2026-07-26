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

    var badgeAssetName: String {
        switch self {
        case .bronze: "RankBronze"
        case .silver: "RankSilver"
        case .gold: "RankGold"
        case .platinum: "RankPlatinum"
        case .goat: "RankGOAT"
        }
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

struct RankedMatchResult: Equatable {
    let ratingBefore: Int
    let ratingAfter: Int
    let didWin: Bool

    var delta: Int { ratingAfter - ratingBefore }
    var tier: RankedTier { .forRating(ratingAfter) }
}

/// Game Center leaderboard IDs are permanent once created in App Store Connect.
/// Configure this as a monthly, recurring, high-to-low, most-recent-score leaderboard.
enum RankedLadder {
    static let leaderboardID = "com.jackziegler.hoopsiq.ranked.monthly"
    static let initialRating = 1_000
    static let kFactor = 24.0
    static let minimumRating = 0
    static let maximumRating = 3_000

    static func rating(afterWin didWin: Bool, rating: Int, opponentRating: Int = initialRating) -> Int {
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

    private static func row(_ entry: GKLeaderboard.Entry) -> RankedLeaderboardRow {
        row(placement: entry.rank, playerID: entry.player.gamePlayerID, displayName: entry.player.displayName, mmr: Int(entry.score), isLocalPlayer: entry.player.gamePlayerID == GKLocalPlayer.local.gamePlayerID)
    }
}

private enum RankedLeaderboardError: LocalizedError { case unavailable; var errorDescription: String? { "The monthly ranked leaderboard is unavailable right now." } }

@MainActor final class RankedLadderService: ObservableObject {
    @Published private(set) var rating: Int
    @Published private(set) var lastSubmissionError: String?

    private let defaults: UserDefaults
    private let ratingKey = "ranked.monthly.rating"
    private let matchKey = "ranked.monthly.submittedMatchIDs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.rating = defaults.object(forKey: "ranked.monthly.rating") as? Int ?? RankedLadder.initialRating
    }

    var tier: RankedTier { RankedTier.forRating(rating) }
    var matchmakingBucket: Int { rating / 100 }

    func recordCompletedMatch(id: String, didWin: Bool) -> RankedMatchResult? {
        var submittedIDs = Set(defaults.stringArray(forKey: matchKey) ?? [])
        guard submittedIDs.insert(id).inserted else { return nil }

        let before = rating
        let after = RankedLadder.rating(afterWin: didWin, rating: before)
        rating = after
        defaults.set(after, forKey: ratingKey)
        // Keep a bounded idempotency journal so replayed end packets cannot change rank twice.
        defaults.set(Array(submittedIDs.suffix(100)), forKey: matchKey)
        submit(after)
        return RankedMatchResult(ratingBefore: before, ratingAfter: after, didWin: didWin)
    }

    func refreshFromGameCenter() async {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        do {
            let boards = try await GKLeaderboard.loadLeaderboards(IDs: [RankedLadder.leaderboardID])
            guard let board = boards.first else { return }
            let (local, _, _) = try await board.loadEntries(for: .global, timeScope: .allTime, range: NSRange(location: 1, length: 1))
            guard let local else { return }
            rating = Int(local.score)
            defaults.set(rating, forKey: ratingKey)
        } catch {
            lastSubmissionError = error.localizedDescription
        }
    }

    private func submit(_ score: Int) {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [RankedLadder.leaderboardID]) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in self?.lastSubmissionError = error.localizedDescription }
        }
    }
}
