import Foundation

@MainActor final class GameViewModel: ObservableObject {
    enum Phase: Equatable { case matching, matchup, revealing, auction, bidResult, selecting, draftReveal, reportLoading, results }
    @Published var phase: Phase = .matching
    @Published var engine: AuctionEngine?
    @Published var bid = 0
    @Published var seconds = 20
    @Published var toast = ""
    @Published var pendingWinner: AuctionWinner?
    @Published var pendingBid = 0
    @Published var playerBid = 0
    @Published var opponentBid = 0
    @Published var revealedPlayer: DraftedPlayer?
    @Published var isForcedAward = false
    @Published var loadError: String?
    @Published var opponentDisplayName = "OPPONENT"
    @Published var connectionMessage: String?
    @Published private(set) var rankedMatchResult: RankedMatchResult?
    @Published private(set) var forcedResult: String?
    @Published private(set) var bestPossibleTeam: [DraftedPlayer] = []
    @Published private(set) var bestPossibleOpponentTeam: [DraftedPlayer] = []
    @Published private(set) var difficulty: MatchDifficulty
    private var timer: Task<Void, Never>?
    private var reportCalculation: Task<Void, Never>?
    private var reportCalculationID: UUID?
    private var matchupTimer: Task<Void, Never>?
    private let transport: MatchTransport
    private let friendSession: FriendBattleSession?
    private var friendUpdates: Task<Void, Never>?
    private let matchMode: OnlineMatchMode
    private let rankedLadder: RankedLadderService?
    let rankedAIProfile: RankedAIProfile?

    init(difficulty: MatchDifficulty, transport: MatchTransport = LocalBotMatchTransport(), friendSession: FriendBattleSession? = nil, matchMode: OnlineMatchMode = .versusAI, rankedLadder: RankedLadderService? = nil, rankedAIProfile: RankedAIProfile? = nil) {
        self.difficulty = difficulty; self.transport = transport; self.friendSession = friendSession; self.matchMode = matchMode
        self.rankedLadder = matchMode == .ranked ? (rankedLadder ?? RankedLadderService()) : nil
        self.rankedAIProfile = rankedAIProfile
    }
    func start() async {
        reportCalculation?.cancel(); reportCalculation = nil; reportCalculationID = nil
        bestPossibleTeam = []; bestPossibleOpponentTeam = []
        phase = .matching; loadError = nil; revealedPlayer = nil; pendingWinner = nil; isForcedAward = false; playerBid = 0; opponentBid = 0; toast = ""; rankedMatchResult = nil; forcedResult = nil
        if let friendSession {
            opponentDisplayName = friendSession.opponentName
            friendUpdates = Task { [weak self, friendSession] in
                for await snapshot in friendSession.$snapshot.values {
                    guard let snapshot else { continue }
                    await self?.apply(snapshot, from: friendSession)
                }
            }
            do { try await friendSession.start() } catch { loadError = error.localizedDescription }
            return
        }
        let seed = UInt64(Date().timeIntervalSince1970); try? await transport.connect()
        do {
            let teams = try await BundledSeasonRepository.randomTeams(count: 10, seed: seed)
            guard teams.count == 10 else { throw ArchiveLoadError.invalidArchive }
            engine = AuctionEngine(teams: teams, seed: seed, rankedAIProfile: rankedAIProfile)
            opponentDisplayName = engine?.opponentName ?? "OPPONENT"
        } catch {
            loadError = error.localizedDescription
            return
        }
        bid = 0
        if matchMode == .ranked {
            phase = .matchup
            scheduleLocalRankedMatchupAdvance()
        } else {
            phase = .revealing
        }
    }
    func adjustBid(by amount: Int) { guard let engine else { return }; bid = min(engine.playerBudget, max(0, bid + amount)) }
    func submitBid() {
        if let friendSession { Task { try? await friendSession.submitBid(bid) }; timer?.cancel(); return }
        guard var engine else { return }
        let opponentBid = engine.botBid()
        guard let outcome = engine.resolve(playerBid: bid, opponentBid: opponentBid) else { return }
        self.engine = engine; pendingWinner = outcome.winner; pendingBid = outcome.bid; playerBid = bid; self.opponentBid = opponentBid; isForcedAward = false; timer?.cancel()
        toast = outcome.winner == .player ? "YOU WON · $\(outcome.bid)M" : "OPPONENT WON · $\(outcome.bid)M"
        phase = .bidResult
    }
    func continueAfterBid() {
        if let friendSession { Task { try? await friendSession.advance() }; return }
        guard let winner = pendingWinner else { return }
        if winner == .player {
            seconds = 20
            phase = .selecting
            startSelectionTimer()
        } else {
            autoPickForOpponent()
        }
    }
    func selectPlayer(_ player: SeasonRecord) {
        if let friendSession { Task { try? await friendSession.submitPick(player.id) }; return }
        guard var engine, let winner = pendingWinner, engine.select(player, for: winner, bid: pendingBid) else { return }
        timer?.cancel()
        self.engine = engine; revealedPlayer = engine.playerRoster.last; pendingWinner = nil; phase = .draftReveal
    }
    func leaveMatch() {
        timer?.cancel()
        matchupTimer?.cancel()
        reportCalculation?.cancel()
        if let friendSession { Task { await friendSession.forfeit() } }
        transport.disconnect()
    }
    private func autoPickForOpponent() {
        guard var engine, let pick = engine.botPick(), let winner = pendingWinner, engine.select(pick, for: winner, bid: pendingBid) else { return }
        self.engine = engine; revealedPlayer = engine.opponentRoster.last; pendingWinner = nil; toast = "OPPONENT DRAFTED \(pick.playerName)"; phase = .draftReveal
    }
    private func scheduleLocalRankedMatchupAdvance() {
        matchupTimer?.cancel()
        matchupTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled, self.phase == .matchup else { return }
            self.phase = .revealing
        }
    }
    func finishDraftReveal() {
        if let friendSession { Task { try? await friendSession.advance() }; return }
        guard let engine else { return }
        revealedPlayer = nil; pendingWinner = nil; isForcedAward = false
        if engine.isComplete { prepareFinalReport(from: engine) } else { bid = 0; seconds = 20; phase = .revealing }
    }
    func finishReveal() {
        if let friendSession { Task { try? await friendSession.advance() }; return }
        guard phase == .revealing, var engine else { return }
        if engine.playerIsFull || engine.opponentIsFull, let outcome = engine.resolve(playerBid: 0, opponentBid: 0) {
            self.engine = engine; pendingWinner = outcome.winner; pendingBid = 0; playerBid = 0; opponentBid = 0; isForcedAward = true; phase = .bidResult
        } else { phase = .auction; startTimer() }
    }
    func startTimer() { timer?.cancel(); timer = Task { while !Task.isCancelled && seconds > 0 { try? await Task.sleep(for: .seconds(1)); seconds -= 1 }; if !Task.isCancelled && seconds == 0 { submitBid() } } }
    private func startSelectionTimer() {
        timer?.cancel()
        timer = Task {
            while !Task.isCancelled && seconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                seconds -= 1
            }
            guard !Task.isCancelled && seconds == 0 else { return }
            autoSelectForPlayer()
        }
    }
    private func autoSelectForPlayer() {
        guard let player = engine?.current?.players
            .filter({ !(engine?.isPlayerSelected($0) ?? true) })
            .max(by: { $0.overallRating < $1.overallRating }) else { return }
        selectPlayer(player)
    }
    var result: String { guard let engine else { return "" }; return forcedResult ?? TeamSimulator.winner(player: engine.playerRoster, opponent: engine.opponentRoster) }
    var playerNetRating: TeamNetRating { TeamSimulator.rating(for: engine?.playerRoster ?? []) }
    var opponentNetRating: TeamNetRating { TeamSimulator.rating(for: engine?.opponentRoster ?? []) }
    var playerStats: TeamStatLine { TeamSimulator.stats(for: engine?.playerRoster ?? []) }
    var opponentStats: TeamStatLine { TeamSimulator.stats(for: engine?.opponentRoster ?? []) }
    var playerRatingBreakdown: LineupRatingBreakdown { TeamSimulator.ratingBreakdown(for: engine?.playerRoster ?? []) }
    var opponentRatingBreakdown: LineupRatingBreakdown { TeamSimulator.ratingBreakdown(for: engine?.opponentRoster ?? []) }
    var playerAverageRating: Double { TeamSimulator.averageLineupRating(for: engine?.playerRoster ?? []) }
    var opponentAverageRating: Double { TeamSimulator.averageLineupRating(for: engine?.opponentRoster ?? []) }
    var playerRoles: [LineupRole] { TeamSimulator.roleAssignments(for: engine?.playerRoster ?? []) }
    private func prepareFinalReport(from engine: AuctionEngine, didWinOverride: Bool? = nil) {
        reportCalculation?.cancel()
        bestPossibleTeam = []
        bestPossibleOpponentTeam = []
        phase = .reportLoading

        let calculationID = UUID()
        reportCalculationID = calculationID
        let playerTeams = engine.playerWonTeams
        let opponentTeams = engine.opponentWonTeams
        reportCalculation = Task { [weak self, calculationID, playerTeams, opponentTeams] in
            let lineups = await Task.detached {
                let playerLineup = TeamSimulator.bestPossibleLineup(from: playerTeams)
                let opponentLineup = TeamSimulator.bestPossibleLineup(from: opponentTeams)
                return (playerLineup, opponentLineup)
            }.value
            guard !Task.isCancelled, let self, self.reportCalculationID == calculationID else { return }
            self.bestPossibleTeam = lineups.0
            self.bestPossibleOpponentTeam = lineups.1
            self.reportCalculation = nil
            self.phase = .results
            self.finishRankedMatchIfNeeded(engine: engine, didWinOverride: didWinOverride)
        }
    }
    private func finishRankedMatchIfNeeded(engine: AuctionEngine, didWinOverride: Bool? = nil) {
        guard matchMode == .ranked, let rankedLadder else { return }
        let localID = transport.localPlayerID
        let matchID = "\(engine.seed)-\(localID)"
        rankedMatchResult = rankedLadder.recordCompletedMatch(id: matchID, didWin: didWinOverride ?? (TeamSimulator.winner(player: engine.playerRoster, opponent: engine.opponentRoster) == "PLAYER WINS"))
    }
    var bestValuePick: DraftedPlayer? { engine?.playerRoster.filter { $0.bid > 0 }.max { TeamSimulator.playerImpact($0.season) / Double($0.bid) < TeamSimulator.playerImpact($1.season) / Double($1.bid) } }
    var biggestOverpay: DraftedPlayer? { engine?.playerRoster.filter { $0.bid > 0 }.min { TeamSimulator.playerImpact($0.season) / Double($0.bid) < TeamSimulator.playerImpact($1.season) / Double($1.bid) } }
    private func apply(_ snapshot: BattleSnapshot, from session: FriendBattleSession) {
        // The host's difficulty arrives in the same complete snapshot as the
        // board, so a guest never renders local setup settings for this match.
        difficulty = snapshot.difficulty
        let localIsHost = session.localIsHost
        engine = localIsHost ? snapshot.engine : snapshot.engine.withSidesSwapped()
        pendingWinner = localIsHost ? snapshot.winner : (snapshot.winner == .player ? .opponent : snapshot.winner == .opponent ? .player : nil)
        pendingBid = snapshot.winningBid
        playerBid = localIsHost ? (snapshot.hostBid ?? 0) : (snapshot.guestBid ?? 0)
        opponentBid = localIsHost ? (snapshot.guestBid ?? 0) : (snapshot.hostBid ?? 0)
        connectionMessage = session.connectionMessage
        switch snapshot.stage {
        case .lobby: phase = .matching
        case .matchup: phase = .matchup
        case .revealing: phase = .revealing
        case .bidding: phase = .auction; seconds = max(0, Int((snapshot.deadline ?? Date()).timeIntervalSinceNow.rounded(.up)))
        case .bidResult: phase = .bidResult
        case .picking: phase = .selecting; seconds = max(0, Int((snapshot.deadline ?? Date()).timeIntervalSinceNow.rounded(.up)))
        case .draftReveal: revealedPlayer = pendingWinner == .player ? engine?.playerRoster.last : engine?.opponentRoster.last; phase = .draftReveal
        case .paused: phase = .matching
        case .ended:
            let didWin = snapshot.forfeitWinnerID.map { $0 == session.localPlayerID }
            if let didWin { forcedResult = didWin ? "PLAYER WINS BY FORFEIT" : "OPPONENT WINS BY FORFEIT" }
            if let engine { prepareFinalReport(from: engine, didWinOverride: didWin) }
        }
    }
    deinit { timer?.cancel(); matchupTimer?.cancel(); reportCalculation?.cancel(); friendUpdates?.cancel() }
}
