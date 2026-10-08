import Foundation
import GameKit
import SwiftUI

enum RankedSearchStage: Int, CaseIterable, Equatable {
    case closeMatch, expanded, wide

    static let duration: Int = 30
    static let stageDuration: Int = 10

    var acceptedMMRRange: Int {
        switch self { case .closeMatch: 100; case .expanded: 250; case .wide: 500 }
    }

    var playerMessage: String {
        switch self {
        case .closeMatch: "Looking for a player close to your skill level…"
        case .expanded: "Still looking — expanding the search to find you a fair match."
        case .wide: "Searching a wider range of players…"
        }
    }

    static func forElapsedSeconds(_ seconds: Int) -> RankedSearchStage {
        switch seconds {
        case 0..<stageDuration: .closeMatch
        case stageDuration..<(stageDuration * 2): .expanded
        default: .wide
        }
    }
}

enum RankedSearchState: Equatable {
    case idle, searching(stage: RankedSearchStage, secondsElapsed: Int), matched, startingAI(profile: RankedAIProfile), failed(String)
}

/// A small seam around GameKit keeps the ranked session lifecycle testable
/// without requiring a live Game Center queue.
@MainActor protocol RankedMatchmaking: AnyObject {
    func findMatch(for request: GKMatchRequest) async throws -> GKMatch
    func cancel()
}

@MainActor final class GameKitRankedMatchmaking: RankedMatchmaking {
    func findMatch(for request: GKMatchRequest) async throws -> GKMatch {
        try await GKMatchmaker.shared().findMatch(for: request)
    }

    func cancel() { GKMatchmaker.shared().cancel() }
}

struct RankedMatchTicket {
    let id: UUID
    let match: GKMatch
}

struct RankedAIFallbackTicket {
    let id: UUID
    let profile: RankedAIProfile
}

@MainActor final class GameCenterCoordinator: NSObject, ObservableObject {
    enum Status: Equatable { case idle, authenticating, ready, unavailable(String) }
    @Published private(set) var status: Status = .idle
    @Published var authenticationController: UIViewController?
    @Published var match: GKMatch?
    @Published var inviteError: String?
    @Published var isFindingRankedMatch = false
    @Published private(set) var rankedSearchState: RankedSearchState = .idle
    private var rankedSearchTask: Task<Void, Never>?
    private var rankedRequestTask: Task<Void, Never>?
    private var rankedSearchGeneration = UUID()
    private var rankedReadyMatch: GKMatch?
    private var rankedReadyAIProfile: RankedAIProfile?
    private var consumedRankedSessionID: UUID?
    private let rankedMatcher: RankedMatchmaking
    /// A coordinator has one game identity for its lifetime. Root owns one for
    /// Five Alive and one for Box Wars, so a ticket can never be consumed by
    /// the other game's hub.
    private let competitiveGame: CompetitiveGame
    /// Turn this on only after the matching queue has been created and released
    /// in App Store Connect under this exact identifier.
    private static let usesConfiguredRankedQueue = false

    init(rankedMatcher: RankedMatchmaking = GameKitRankedMatchmaking(), competitiveGame: CompetitiveGame = .fiveAlive) {
        self.rankedMatcher = rankedMatcher
        self.competitiveGame = competitiveGame
        super.init()
    }

    nonisolated static func fallbackProfile(forRating rating: Int) -> RankedAIProfile {
        RankedAIProfile(tier: .forRating(rating))
    }

    func authenticate() {
        guard !GKLocalPlayer.local.isAuthenticated else {
            authenticationController = nil
            status = .ready
            return
        }

        status = .authenticating
        GKLocalPlayer.local.authenticateHandler = { [weak self] controller, error in
            Task { @MainActor in
                guard let self else { return }
                self.authenticationController = controller
                if let error { self.status = .unavailable(error.localizedDescription) }
                else if GKLocalPlayer.local.isAuthenticated { self.status = .ready }
                else if controller == nil { self.status = .unavailable("Sign in to Game Center to challenge a friend.") }
            }
        }
    }

    func refreshAuthenticationStatus() {
        authenticationController = nil
        status = GKLocalPlayer.local.isAuthenticated
            ? .ready
            : .unavailable("Sign in to Game Center to challenge a friend.")
    }
    func receive(match: GKMatch) { self.match = match }

    func startRankedSearch(rating: Int) {
        guard status == .ready, !hasActiveRankedSearch else { return }
        resetRankedSession()
        inviteError = nil
        isFindingRankedMatch = true
        let generation = UUID()
        rankedSearchGeneration = generation
        rankedSearchState = .searching(stage: .closeMatch, secondsElapsed: 0)
        rankedSearchTask = Task { [weak self] in
            guard let self else { return }
            await self.runRankedSearch(rating: rating, generation: generation)
        }
    }

    private func runRankedSearch(rating: Int, generation: UUID) async {
        for stage in RankedSearchStage.allCases {
            guard isCurrentRankedSession(generation) else { return }
            let elapsed = stage.rawValue * RankedSearchStage.stageDuration
            rankedSearchState = .searching(stage: stage, secondsElapsed: elapsed)
            beginRankedRequest(rating: rating, stage: stage, generation: generation)
            try? await Task.sleep(for: .seconds(RankedSearchStage.stageDuration))
            guard isCurrentRankedSession(generation) else { return }
            if case .failed = rankedSearchState { return }
            rankedMatcher.cancel()
            rankedRequestTask?.cancel()
            if stage == .wide {
                isFindingRankedMatch = false
                // The profile is captured at the fallback boundary, before the
                // ranked game can update the player's rating.
                let profile = Self.fallbackProfile(forRating: rating)
                rankedReadyAIProfile = profile
                rankedSearchState = .startingAI(profile: profile)
            }
        }
    }

    private func beginRankedRequest(rating: Int, stage: RankedSearchStage, generation: UUID) {
        let request = rankedRequest(rating: rating, stage: stage, usesConfiguredQueue: Self.usesConfiguredRankedQueue)
        rankedRequestTask = Task { [weak self] in
            guard let self else { return }
            do {
                let found = try await self.rankedMatcher.findMatch(for: request)
                self.handleRankedMatchResult(.success(found), generation: generation)
            } catch {
                guard !Task.isCancelled else { return }
                // Local development and App Store Connect configurations without
                // this named queue return GKError 5003 immediately. Retry using
                // the platform's rating-bucket matchmaking instead of surfacing
                // an error or preventing the timed AI fallback.
                if Self.isMissingQueueError(error) {
                    do {
                        let fallbackRequest = self.rankedRequest(rating: rating, stage: stage, usesConfiguredQueue: false)
                        let found = try await self.rankedMatcher.findMatch(for: fallbackRequest)
                        self.handleRankedMatchResult(.success(found), generation: generation)
                    } catch {
                        guard !Task.isCancelled else { return }
                        self.handleRankedMatchResult(.failure(error), generation: generation)
                    }
                } else {
                    self.handleRankedMatchResult(.failure(error), generation: generation)
                }
            }
        }
    }

    private func rankedRequest(rating: Int, stage: RankedSearchStage, usesConfiguredQueue: Bool) -> GKMatchRequest {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.defaultNumberOfPlayers = 2
        let lowerBucket = max(0, (rating - stage.acceptedMMRRange) / 100)
        let upperBucket = (rating + stage.acceptedMMRRange) / 100
        if #available(iOS 17.2, *), usesConfiguredQueue {
            request.queueName = competitiveGame == .boxWars ? "com.jackziegler.hoopsiq.gridduel.ranked" : "com.jackziegler.hoopsiq.ranked"
            // Matchmaking rules in App Store Connect consume these values. The
            // current bucket is retained for queue diagnostics and analytics.
            request.properties = ["ratingBucket": rating / 100, "minimumRatingBucket": lowerBucket, "maximumRatingBucket": upperBucket]
        } else {
            // Keep GameKit's fallback bucket game-specific as well.
            request.playerGroup = rating / 100 + (competitiveGame == .boxWars ? 10_000 : 0)
        }
        return request
    }

    nonisolated static func isMissingQueueError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.code == 5003
    }

    private func handleRankedMatchResult(_ result: Result<GKMatch, Error>, generation: UUID) {
        guard isCurrentRankedSession(generation) else { return }
        switch result {
        case let .success(found):
            rankedReadyMatch = found
            isFindingRankedMatch = false
            rankedSearchTask?.cancel(); rankedSearchTask = nil
            rankedRequestTask = nil
            rankedSearchState = .matched
        case let .failure(error):
            guard !Task.isCancelled else { return }
            isFindingRankedMatch = false; rankedSearchState = .failed(error.localizedDescription); rankedSearchGeneration = UUID()
        }
    }

    /// Atomically transfers a found match to gameplay. A ticket can be used
    /// once only; returning to the hub can never reuse its match.
    func consumeRankedMatch() -> RankedMatchTicket? {
        guard let found = rankedReadyMatch else { return nil }
        let ticket = RankedMatchTicket(id: rankedSearchGeneration, match: found)
        resetRankedSession(keepingConsumedSessionID: ticket.id)
        return ticket
    }

    /// Atomically transfers the captured fallback profile to gameplay.
    func consumeRankedAIFallback() -> RankedAIFallbackTicket? {
        guard let profile = rankedReadyAIProfile else { return nil }
        let ticket = RankedAIFallbackTicket(id: rankedSearchGeneration, profile: profile)
        resetRankedSession(keepingConsumedSessionID: ticket.id)
        return ticket
    }

    /// A consumed ticket remains valid only while the hub is transitioning to
    /// gameplay. Any cancel, navigation away, or background event revokes it.
    func isConsumedRankedSessionCurrent(_ id: UUID) -> Bool {
        consumedRankedSessionID == id
    }

    func cancelRankedMatch() { resetRankedSession() }

    /// Invalidates all pre-game ranked work. This deliberately does not touch
    /// a match already handed to `GameView` through a consume ticket.
    func resetRankedSession() { resetRankedSession(keepingConsumedSessionID: nil) }

    private func resetRankedSession(keepingConsumedSessionID: UUID?) {
        rankedSearchGeneration = UUID()
        rankedSearchTask?.cancel(); rankedSearchTask = nil
        rankedRequestTask?.cancel(); rankedRequestTask = nil
        rankedMatcher.cancel()
        rankedReadyMatch = nil
        rankedReadyAIProfile = nil
        consumedRankedSessionID = keepingConsumedSessionID
        match = nil
        isFindingRankedMatch = false
        rankedSearchState = .idle
    }

    /// Leaderboard lookup is best-effort: Game Center may not have a submitted
    /// score yet, and that must never hold the matched players at the gate.
    func rankedMatchup(for match: GKMatch, localRating: Int) async -> RankedMatchup {
        let localName = GKLocalPlayer.local.displayName
        let opponent = match.players.first
        let fallbackName = opponent?.displayName ?? "OPPONENT"
        guard let opponent else {
            return .pvp(localName: localName, localRating: localRating, opponentName: fallbackName, opponentRow: nil)
        }
        do {
            let leaderboardID = competitiveGame == .boxWars
                ? GridDuelLadder.leaderboardID
                : RankedLadder.leaderboardID
            let boards = try await GKLeaderboard.loadLeaderboards(IDs: [leaderboardID])
            guard let board = boards.first else {
                return .pvp(localName: localName, localRating: localRating, opponentName: fallbackName, opponentRow: nil)
            }
            let (_, entries) = try await board.loadEntries(for: [opponent], timeScope: .allTime)
            let entry = entries.first { $0.player.gamePlayerID == opponent.gamePlayerID }
            let row = entry.map { RankedLeaderboardRow(placement: $0.rank, playerID: $0.player.gamePlayerID, displayName: $0.player.displayName, mmr: Int($0.score), isLocalPlayer: false) }
            return .pvp(localName: localName, localRating: localRating, opponentName: fallbackName, opponentRow: row)
        } catch {
            return .pvp(localName: localName, localRating: localRating, opponentName: fallbackName, opponentRow: nil)
        }
    }
    private var hasActiveRankedSearch: Bool {
        if case .searching = rankedSearchState { return true }
        return false
    }

    private func isCurrentRankedSession(_ generation: UUID) -> Bool {
        generation == rankedSearchGeneration && rankedReadyMatch == nil && rankedReadyAIProfile == nil
    }
}

struct GameCenterAuthenticationView: UIViewControllerRepresentable {
    let controller: UIViewController
    func makeUIViewController(context: Context) -> UIViewController { controller }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) { }
}

struct FriendMatchmakerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let coordinator: GameCenterCoordinator
    func makeCoordinator() -> Delegate { Delegate(parent: self) }
    func makeUIViewController(context: Context) -> GKMatchmakerViewController {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.defaultNumberOfPlayers = 2
        let controller = GKMatchmakerViewController(matchRequest: request)!
        controller.matchmakerDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: GKMatchmakerViewController, context: Context) { }
    @MainActor final class Delegate: NSObject, @preconcurrency GKMatchmakerViewControllerDelegate {
        let parent: FriendMatchmakerView
        init(parent: FriendMatchmakerView) { self.parent = parent }
        func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
            parent.coordinator.inviteError = "Friend invite cancelled."; parent.dismiss()
        }
        func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
            parent.coordinator.inviteError = error.localizedDescription; parent.dismiss()
        }
        func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
            parent.coordinator.receive(match: match); parent.dismiss()
        }
    }
}
