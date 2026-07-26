import Foundation
import GameKit

/// A separate ladder keeps Grid Duel outcomes from changing Five Alive rank.
enum GridDuelLadder { static let leaderboardID = "com.jackziegler.hoopsiq.gridduel.monthly"; static let initialRating = 1_000 }

@MainActor final class GridDuelLadderService: ObservableObject {
    @Published private(set) var rating: Int
    private let defaults: UserDefaults
    private let ratingKey = "gridduel.monthly.rating"
    private let matchKey = "gridduel.monthly.submittedMatchIDs"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults; rating = defaults.object(forKey: ratingKey) as? Int ?? GridDuelLadder.initialRating }
    var tier: RankedTier { .forRating(rating) }
    func recordCompletedMatch(id: String, didWin: Bool) -> RankedMatchResult? {
        var ids = Set(defaults.stringArray(forKey: matchKey) ?? [])
        guard ids.insert(id).inserted else { return nil }
        let before = rating; rating = RankedLadder.rating(afterWin: didWin, rating: before)
        defaults.set(rating, forKey: ratingKey); defaults.set(Array(ids.suffix(100)), forKey: matchKey)
        if GKLocalPlayer.local.isAuthenticated { GKLeaderboard.submitScore(rating, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [GridDuelLadder.leaderboardID]) { _ in } }
        return .init(ratingBefore: before, ratingAfter: rating, didWin: didWin)
    }
}
