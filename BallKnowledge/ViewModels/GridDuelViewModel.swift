import Foundation

@MainActor final class GridDuelViewModel: ObservableObject {
    enum Phase: Equatable { case loading, playing, calculatingResults, results, failed(String) }
    enum SubmissionFeedback: Equatable {
        case incorrect(cellID: String)
    }
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var engine: GridDuelEngine?
    @Published private(set) var deadline: Date?
    @Published var selectedCellID: String?
    @Published var query = "" { didSet { refreshMatches() } }
    @Published private(set) var matches: [SeasonRecord] = []
    @Published private(set) var secondsRemaining = Int(GridDuelEngine.duration)
    @Published private(set) var result: GridDuelResult?
    @Published private(set) var rankedResult: RankedMatchResult?
    @Published private(set) var submissionFeedback: SubmissionFeedback?
    @Published private(set) var quickChatToast: GameQuickChatToast?
    private var clock: Task<Void, Never>?
    private var feedbackReset: Task<Void, Never>?
    private var resultCalculation: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var quickChatUpdates: Task<Void, Never>?
    private var quickChatDismissTask: Task<Void, Never>?
    private var sentBotChatTriggers: Set<String> = []
    private let mode: OnlineMatchMode
    private let ladder: GridDuelLadderService?
    private let battleSession: BoxWarsBattleSession?
    private var battleUpdates: Task<Void, Never>?

    var ladderDisplay: RankedDisplay? { ladder?.display }

    init(mode: OnlineMatchMode, ladder: GridDuelLadderService? = nil, battleSession: BoxWarsBattleSession? = nil) {
        self.mode = mode
        self.ladder = ladder
        self.battleSession = battleSession
    }

    func start() async {
        phase = .loading; result = nil; rankedResult = nil; submissionFeedback = nil; quickChatToast = nil; sentBotChatTriggers = []
        do {
            let rows = try await NBAStatsStore.shared.database().teamSeasons.flatMap(\.players)
            if let battleSession {
                startBattleUpdates(session: battleSession)
                try await battleSession.start(rows: rows)
                return
            }
            guard let grid = GridDuelEngine.generate(from: rows, seed: UInt64(Date().timeIntervalSince1970)) else { throw ArchiveLoadError.invalidArchive }
            var createdEngine = GridDuelEngine(grid: grid, archiveRows: rows)
            // A live GameKit session is PVP whether it was created through a
            // friend invite or the ranked queue. Only a nil session is local
            // AI. This keeps a ranked ticket from being replaced by an AI
            // board after matchmaking succeeds.
            if battleSession == nil {
                if mode == .ranked {
                    let profile = (ladder?.tier ?? .bronze).boxWarsAIProfile
                    for (cell, answer) in createdEngine.rankedAIAnswers(profile: profile) {
                        _ = createdEngine.submit(answer, to: cell.id, forLocalPlayer: false, at: Date().addingTimeInterval(20))
                    }
                } else {
                    for cell in grid.cells.prefix(3) {
                        guard let answer = createdEngine.validRecords(for: cell).sorted(by: { $0.playerName < $1.playerName }).first else { continue }
                        _ = createdEngine.submit(answer, to: cell.id, forLocalPlayer: false, at: Date().addingTimeInterval(20))
                    }
                }
            }
            engine = createdEngine
            if mode == .ranked { ladder?.beginActiveRankedMatch(id: rankedMatchID(for: createdEngine)) }
            selectedCellID = nil; deadline = Date().addingTimeInterval(GridDuelEngine.duration); phase = .playing
            refreshMatches()
            startClock()
            sendBotQuickChat(.goodLuck, trigger: "match-start")
        } catch { phase = .failed(error.localizedDescription) }
    }

    var selectedCell: GridDuelCell? { engine?.grid.cells.first(where: { $0.id == selectedCellID }) }

    func careerRange(for record: SeasonRecord) -> String {
        engine?.careerRange(for: record) ?? record.season
    }

    private func refreshMatches() {
        searchTask?.cancel()
        let searchedQuery = query
        guard !searchedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let engine,
              let searchedCellID = selectedCellID else {
            matches = []
            return
        }
        matches = []
        searchTask = Task.detached(priority: .userInitiated) { [weak self, engine, searchedQuery, searchedCellID] in
            let results = engine.searchRecords(query: searchedQuery)
            guard !Task.isCancelled else { return }
            await self?.publishSearchResults(results, query: searchedQuery, cellID: searchedCellID)
        }
    }

    private func publishSearchResults(_ results: [SeasonRecord], query: String, cellID: String) {
        guard !Task.isCancelled, self.query == query, selectedCellID == cellID else { return }
        matches = results
    }

    func select(cell: GridDuelCell) {
        selectedCellID = cell.id
        query = ""
    }

    func clearSelection() {
        selectedCellID = nil
        query = ""
        matches = []
    }
    func submit(_ record: SeasonRecord) {
        guard phase == .playing, var engine, let cellID = selectedCellID else { return }
        if let battleSession {
            Task { _ = await battleSession.submit(record, to: cellID) }
            return
        }
        guard engine.submit(record, to: cellID, forLocalPlayer: true, deadline: deadline) else {
            showIncorrectFeedback(for: cellID)
            return
        }
        self.engine = engine
        query = ""
    }

    func finish() {
        guard phase == .playing, let engine else { return }
        if let battleSession { Task { await battleSession.finishIfExpired() }; return }
        clock?.cancel()
        feedbackReset?.cancel()
        submissionFeedback = nil
        phase = .calculatingResults
        resultCalculation = Task { [weak self, engine] in
            // Let SwiftUI present the calculation state before resolving the board.
            await Task.yield()
            let final = await Task.detached(priority: .userInitiated) { engine.resolve() }.value
            guard !Task.isCancelled, let self, self.phase == .calculatingResults else { return }
            self.result = final
            self.phase = .results
            if self.mode == .ranked {
                let outcome: RankedMatchOutcome = switch final.winner {
                case .local: .win
                case .opponent: .loss
                case .draw: .draw
                }
                self.rankedResult = self.ladder?.finalizeActiveRankedMatch(id: self.rankedMatchID(for: engine), outcome: outcome)
            }
        }
    }

    /// Ends the active game. The ladder service de-duplicates by grid ID, so a
    /// repeated UI action can never submit more than one ranked loss.
    func forfeit() {
        clock?.cancel()
        feedbackReset?.cancel()
        submissionFeedback = nil
        guard phase == .playing, let engine else { return }
        if let battleSession { Task { try? await battleSession.transport.send(BattleEnvelope(sequence: 0, event: .forfeit)) }; return }
        if mode == .ranked {
            rankedResult = ladder?.finalizeActiveRankedMatch(id: rankedMatchID(for: engine), outcome: .loss)
        }
    }

    var canQuickChat: Bool { battleSession != nil || mode != .friend }

    func sendQuickChat(_ message: BoxWarsQuickChat) {
        guard canQuickChat else { return }
        presentQuickChat(from: "YOU", text: message.text)
        if let battleSession {
            Task { try? await battleSession.sendQuickChat(message) }
            return
        }

        let reply: BoxWarsQuickChat = switch message {
        case .goodLuck: .goodLuck
        case .niceFind: .niceFind
        case .gg: .gg
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.sendBotQuickChat(reply, trigger: "player-chat-\(message.rawValue)")
        }
    }

    func stopSession() {
        quickChatUpdates?.cancel()
        quickChatUpdates = nil
        quickChatDismissTask?.cancel()
        quickChatDismissTask = nil
        battleUpdates?.cancel()
        battleSession?.stop()
    }

    private func startBattleUpdates(session: BoxWarsBattleSession) {
        guard battleUpdates == nil else { return }
        battleUpdates = Task { [weak self, session] in
            for await snapshot in session.$snapshot.values {
                guard let snapshot else { continue }
                self?.apply(snapshot, from: session)
            }
        }
        if quickChatUpdates == nil {
            quickChatUpdates = Task { [weak self, session] in
                for await chat in session.$latestQuickChat.values {
                    guard let chat else { continue }
                    self?.presentQuickChat(from: session.opponentName, text: chat.message.text)
                }
            }
        }
    }

    private func sendBotQuickChat(_ message: BoxWarsQuickChat, trigger: String) {
        guard battleSession == nil, sentBotChatTriggers.insert(trigger).inserted else { return }
        presentQuickChat(from: "OPPONENT", text: message.text)
    }

    private func presentQuickChat(from sender: String, text: String) {
        let toast = GameQuickChatToast(sender: sender, text: text)
        quickChatDismissTask?.cancel()
        quickChatToast = toast
        quickChatDismissTask = Task { [weak self, toast] in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled, self?.quickChatToast?.id == toast.id else { return }
            self?.quickChatToast = nil
        }
    }

    private func rankedMatchID(for engine: GridDuelEngine) -> String { battleSession?.matchID ?? "grid-duel-\(engine.grid.id.uuidString)" }

    private func apply(_ snapshot: BoxWarsSnapshot, from session: BoxWarsBattleSession) {
        engine = snapshot.engine
        deadline = snapshot.deadline
        if mode == .ranked, ladder != nil, rankedResult == nil { ladder?.beginActiveRankedMatch(id: snapshot.matchID) }
        guard let winner = snapshot.winner else {
            phase = .playing; refreshMatches(); startClock(); return
        }
        clock?.cancel(); result = snapshot.engine.resolve(); phase = .results
        if mode == .ranked {
            let localWinner: GridDuelWinner = session.localIsHost ? winner : (winner == .local ? .opponent : winner == .opponent ? .local : .draw)
            let outcome: RankedMatchOutcome = localWinner == .local ? .win : localWinner == .opponent ? .loss : .draw
            rankedResult = ladder?.finalizeActiveRankedMatch(id: snapshot.matchID, outcome: outcome)
        }
    }

    private func startClock() {
        clock?.cancel()
        clock = Task { [weak self] in
            while let self, !Task.isCancelled, let deadline = self.deadline {
                self.secondsRemaining = max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
                if self.secondsRemaining == 0 { self.finish(); return }
                try? await Task.sleep(for: .seconds(0.25))
            }
        }
    }

    private func showIncorrectFeedback(for cellID: String) {
        feedbackReset?.cancel()
        submissionFeedback = .incorrect(cellID: cellID)
        feedbackReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.15))
            guard !Task.isCancelled else { return }
            self?.submissionFeedback = nil
        }
    }

    deinit { clock?.cancel(); feedbackReset?.cancel(); resultCalculation?.cancel(); searchTask?.cancel(); battleUpdates?.cancel(); quickChatUpdates?.cancel(); quickChatDismissTask?.cancel() }
}
