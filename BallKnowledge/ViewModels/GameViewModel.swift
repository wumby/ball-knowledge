import Foundation

@MainActor final class GameViewModel: ObservableObject {
    enum Phase: Equatable { case matching, revealing, auction, bidResult, selecting, draftReveal, reportLoading, results }
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
    @Published private(set) var bestPossibleTeam: [DraftedPlayer] = []
    @Published private(set) var bestPossibleOpponentTeam: [DraftedPlayer] = []
    let difficulty: MatchDifficulty
    private var timer: Task<Void, Never>?
    private var reportCalculation: Task<Void, Never>?
    private var reportCalculationID: UUID?
    private let transport: MatchTransport

    init(difficulty: MatchDifficulty, transport: MatchTransport = LocalBotMatchTransport()) { self.difficulty = difficulty; self.transport = transport }
    func start() async {
        reportCalculation?.cancel(); reportCalculation = nil; reportCalculationID = nil
        bestPossibleTeam = []; bestPossibleOpponentTeam = []
        phase = .matching; loadError = nil; revealedPlayer = nil; pendingWinner = nil; isForcedAward = false; playerBid = 0; opponentBid = 0; toast = ""; let seed = UInt64(Date().timeIntervalSince1970); try? await transport.connect(seed: seed)
        do {
            let teams = try await BundledSeasonRepository.randomTeams(count: 10, seed: seed)
            guard teams.count == 10 else { throw ArchiveLoadError.invalidArchive }
            engine = AuctionEngine(teams: teams, seed: seed)
        } catch {
            loadError = error.localizedDescription
            return
        }
        bid = 0; phase = .revealing
    }
    func adjustBid(by amount: Int) { guard let engine else { return }; bid = min(engine.playerBudget, max(0, bid + amount)) }
    func submitBid() {
        guard var engine else { return }
        let opponentBid = engine.botBid()
        guard let outcome = engine.resolve(playerBid: bid, opponentBid: opponentBid) else { return }
        self.engine = engine; pendingWinner = outcome.winner; pendingBid = outcome.bid; playerBid = bid; self.opponentBid = opponentBid; isForcedAward = false; timer?.cancel()
        toast = outcome.winner == .player ? "YOU WON · $\(outcome.bid)M" : "OPPONENT WON · $\(outcome.bid)M"
        phase = .bidResult
    }
    func continueAfterBid() {
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
        guard var engine, let winner = pendingWinner, engine.select(player, for: winner, bid: pendingBid) else { return }
        timer?.cancel()
        self.engine = engine; revealedPlayer = engine.playerRoster.last; pendingWinner = nil; phase = .draftReveal
    }
    private func autoPickForOpponent() {
        guard var engine, let pick = engine.botPick(), let winner = pendingWinner, engine.select(pick, for: winner, bid: pendingBid) else { return }
        self.engine = engine; revealedPlayer = engine.opponentRoster.last; pendingWinner = nil; toast = "OPPONENT DRAFTED \(pick.playerName)"; phase = .draftReveal
    }
    func finishDraftReveal() {
        guard let engine else { return }
        revealedPlayer = nil; pendingWinner = nil; isForcedAward = false
        if engine.isComplete { prepareFinalReport(from: engine) } else { bid = 0; seconds = 20; phase = .revealing }
    }
    func finishReveal() {
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
    var result: String { guard let engine else { return "" }; return TeamSimulator.winner(player: engine.playerRoster, opponent: engine.opponentRoster) }
    var playerNetRating: TeamNetRating { TeamSimulator.rating(for: engine?.playerRoster ?? []) }
    var opponentNetRating: TeamNetRating { TeamSimulator.rating(for: engine?.opponentRoster ?? []) }
    var playerStats: TeamStatLine { TeamSimulator.stats(for: engine?.playerRoster ?? []) }
    var opponentStats: TeamStatLine { TeamSimulator.stats(for: engine?.opponentRoster ?? []) }
    var playerRatingBreakdown: LineupRatingBreakdown { TeamSimulator.ratingBreakdown(for: engine?.playerRoster ?? []) }
    var opponentRatingBreakdown: LineupRatingBreakdown { TeamSimulator.ratingBreakdown(for: engine?.opponentRoster ?? []) }
    var playerAverageRating: Double { TeamSimulator.averageLineupRating(for: engine?.playerRoster ?? []) }
    var opponentAverageRating: Double { TeamSimulator.averageLineupRating(for: engine?.opponentRoster ?? []) }
    var playerRoles: [LineupRole] { TeamSimulator.roleAssignments(for: engine?.playerRoster ?? []) }
    private func prepareFinalReport(from engine: AuctionEngine) {
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
        }
    }
    var bestValuePick: DraftedPlayer? { engine?.playerRoster.filter { $0.bid > 0 }.max { TeamSimulator.playerImpact($0.season) / Double($0.bid) < TeamSimulator.playerImpact($1.season) / Double($1.bid) } }
    var biggestOverpay: DraftedPlayer? { engine?.playerRoster.filter { $0.bid > 0 }.min { TeamSimulator.playerImpact($0.season) / Double($0.bid) < TeamSimulator.playerImpact($1.season) / Double($1.bid) } }
    deinit { timer?.cancel(); reportCalculation?.cancel() }
}
