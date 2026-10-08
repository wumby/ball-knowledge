import Foundation
import GameKit

/// Wire format for private battles.  `sequence` lets clients safely ignore replayed
/// Game Center packets; only the host emits authoritative snapshots.
enum BattleEvent: Codable, Sendable {
    case hello(version: Int, playerID: String, displayName: String)
    case snapshot(BattleSnapshot)
    case bid(round: Int, amount: Int)
    case pick(round: Int, playerID: String)
    case temporaryDisconnect
    case reconnect
    case forfeit
    case ended(winnerID: String)
    case finalOutcome(winnerID: String, matchID: String)
    case quickChat(game: CompetitiveGame, id: String)
    case boxWarsSnapshot(BoxWarsSnapshot)
    case boxWarsAnswer(cellID: String, recordID: String)
}

enum CompetitiveGame: String, Codable, Sendable, Equatable { case fiveAlive, boxWars }

enum FiveAliveQuickChat: String, CaseIterable, Codable, Sendable {
    case goodLuck = "good_luck"
    case niceBid = "nice_bid"
    case yourTurn = "your_turn"
    case thinking = "thinking"
    case gg = "gg"

    var text: String {
        switch self {
        case .goodLuck: "Good luck!"
        case .niceBid: "Nice bid."
        case .yourTurn: "Your turn!"
        case .thinking: "Thinking…"
        case .gg: "Good game!"
        }
    }
}

struct ReceivedFiveAliveQuickChat: Identifiable, Equatable {
    let id = UUID()
    let message: FiveAliveQuickChat
}

enum BoxWarsQuickChat: String, CaseIterable, Codable, Sendable {
    case goodLuck = "good_luck", niceFind = "nice_find", gg = "gg"
    var text: String { switch self { case .goodLuck: "Good luck!"; case .niceFind: "Nice find!"; case .gg: "Good game!" } }
}

struct ReceivedBoxWarsQuickChat: Identifiable, Equatable {
    let id = UUID()
    let message: BoxWarsQuickChat
}

struct BattleEnvelope: Codable, Sendable {
    static let version = 2
    let version: Int
    let sequence: Int
    let event: BattleEvent
    init(sequence: Int, event: BattleEvent) { self.version = Self.version; self.sequence = sequence; self.event = event }
}

enum MatchTransportError: LocalizedError {
    case unavailable, disconnected, invalidPayload
    var errorDescription: String? {
        switch self { case .unavailable: "Game Center match unavailable."; case .disconnected: "Your friend disconnected."; case .invalidPayload: "Received an incompatible match update." }
    }
}

@MainActor protocol MatchTransport: AnyObject {
    var events: AsyncStream<BattleEnvelope> { get }
    var localPlayerID: String { get }
    var opponentPlayerID: String { get }
    var opponentName: String { get }
    func connect() async throws
    func send(_ envelope: BattleEnvelope) async throws
    func disconnect()
}

/// Retained for offline AI play and unit tests; it is deliberately not used for Friend Match.
@MainActor final class LocalBotMatchTransport: MatchTransport {
    let difficulty: BotDifficulty
    let localPlayerID = "local"
    let opponentPlayerID = "bot"
    let opponentName = "Opponent"
    private var continuation: AsyncStream<BattleEnvelope>.Continuation?
    lazy var events: AsyncStream<BattleEnvelope> = AsyncStream { self.continuation = $0 }
    init(difficulty: BotDifficulty = .normal) { self.difficulty = difficulty }
    func connect() async throws { }
    func send(_ envelope: BattleEnvelope) async throws { }
    func disconnect() { continuation?.yield(BattleEnvelope(sequence: 0, event: .forfeit)) }
}

@MainActor final class MockMatchTransport: MatchTransport {
    let localPlayerID: String
    let opponentPlayerID: String
    let opponentName: String
    private(set) var sent: [BattleEnvelope] = []
    private var continuation: AsyncStream<BattleEnvelope>.Continuation?
    lazy var events: AsyncStream<BattleEnvelope> = AsyncStream { self.continuation = $0 }
    init(localPlayerID: String = "a", opponentPlayerID: String = "b", opponentName: String = "Friend") { self.localPlayerID = localPlayerID; self.opponentPlayerID = opponentPlayerID; self.opponentName = opponentName }
    func connect() async throws { }
    func send(_ envelope: BattleEnvelope) async throws { sent.append(envelope) }
    func receive(_ envelope: BattleEnvelope) { continuation?.yield(envelope) }
    func disconnect() { continuation?.yield(BattleEnvelope(sequence: 0, event: .forfeit)) }
}

@MainActor final class GameKitMatchTransport: NSObject, MatchTransport, GKMatchDelegate {
    private let match: GKMatch
    let localPlayerID: String
    let opponentPlayerID: String
    let opponentName: String
    private var continuation: AsyncStream<BattleEnvelope>.Continuation?
    lazy var events: AsyncStream<BattleEnvelope> = AsyncStream { self.continuation = $0 }

    init(match: GKMatch, localPlayer: GKLocalPlayer = .local) {
        self.match = match
        self.localPlayerID = localPlayer.gamePlayerID
        self.opponentPlayerID = match.players.first?.gamePlayerID ?? ""
        self.opponentName = match.players.first?.displayName ?? "Friend"
        super.init()
        match.delegate = self
    }
    func connect() async throws {
        guard !match.players.isEmpty else { throw MatchTransportError.unavailable }
    }
    func send(_ envelope: BattleEnvelope) async throws {
        let data = try JSONEncoder().encode(envelope)
        try match.sendData(toAllPlayers: data, with: .reliable)
    }
    func disconnect() { match.disconnect(); continuation?.finish() }
    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        guard let envelope = try? JSONDecoder().decode(BattleEnvelope.self, from: data) else { return }
        Task { @MainActor [weak self] in self?.continuation?.yield(envelope) }
    }
    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        // A peer that closes the game becomes disconnected. Treat that as a
        // forfeit rather than leaving the remaining player stuck in a pause.
        // Unexpected loss gets a reconnect grace period. A local navigation
        // path sends `.forfeit` explicitly before disconnecting.
        let event: BattleEvent = state == .connected ? .reconnect : .temporaryDisconnect
        Task { @MainActor [weak self] in self?.continuation?.yield(BattleEnvelope(sequence: 0, event: event)) }
    }
    nonisolated func match(_ match: GKMatch, didFailWithError error: Error?) {
        Task { @MainActor [weak self] in self?.continuation?.yield(BattleEnvelope(sequence: 0, event: .forfeit)) }
    }
}

enum BotDifficulty: String, CaseIterable, Identifiable { case easy = "Easy", normal = "Normal", hard = "Hard"; var id: String { rawValue } }

enum FriendBattleStage: String, Codable, Sendable { case lobby, matchup, revealing, bidding, bidResult, picking, draftReveal, paused, ended }

/// Complete host-authoritative Box Wars state.  Both players race on the same
/// grid, but each owns an independent answer column in `engine`.
struct BoxWarsSnapshot: Codable, Sendable {
    let hostID: String
    let matchID: String
    let engine: GridDuelEngine
    let deadline: Date
    let winner: GridDuelWinner?
    let forfeitWinnerID: String?
    let sequence: Int
}

/// The inviter (or deterministic lower player ID for ranked queue matches)
/// owns the board and validates every answer. Snapshots are sufficient to
/// reconnect and make replayed/out-of-order packets harmless.
@MainActor final class BoxWarsBattleSession: ObservableObject {
    @Published private(set) var snapshot: BoxWarsSnapshot?
    @Published private(set) var connectionMessage: String?
    @Published private(set) var latestQuickChat: ReceivedBoxWarsQuickChat?

    let transport: MatchTransport
    let opponentName: String
    private var nextSequence = 1
    private var receivedSequences: Set<Int> = []
    private var eventTask: Task<Void, Never>?
    private var disconnectTask: Task<Void, Never>?
    private var isStopped = false
    private var peerID: String
    private var hostID: String?
    private var lastSnapshotSequence = 0
    private var rows: [SeasonRecord] = []

    init(transport: MatchTransport, hostID: String? = nil) {
        self.transport = transport
        self.opponentName = transport.opponentName
        self.peerID = transport.opponentPlayerID
        self.hostID = hostID ?? [transport.localPlayerID, transport.opponentPlayerID].filter { !$0.isEmpty }.min()
    }
    var localIsHost: Bool { transport.localPlayerID == hostID }
    var matchID: String? { snapshot?.matchID }

    func start(rows: [SeasonRecord]) async throws {
        guard !isStopped else { throw MatchTransportError.disconnected }
        self.rows = rows
        guard eventTask == nil else { return }
        // Materialize the stream before connecting. A peer may send as soon as
        // GameKit reports the connection, so the stream must already buffer.
        let events = transport.events
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await envelope in events { await self.receive(envelope) }
        }
        do {
            try await transport.connect()
        } catch {
            eventTask?.cancel()
            eventTask = nil
            throw error
        }
        if localIsHost { try await beginHostedMatch() }
    }

    /// Compatibility entry point for chat-only callers. Production Box Wars
    /// always supplies the archive before starting the authoritative match.
    func start() async throws { try await start(rows: []) }

    func submit(_ record: SeasonRecord, to cellID: String) async -> Bool {
        guard let snapshot, snapshot.winner == nil, Date() < snapshot.deadline else { return false }
        if localIsHost { return await accept(recordID: record.id, cellID: cellID, from: transport.localPlayerID) }
        do { try await send(.boxWarsAnswer(cellID: cellID, recordID: record.id)); return true } catch { return false }
    }

    func sendQuickChat(_ message: BoxWarsQuickChat) async throws {
        let envelope = BattleEnvelope(sequence: nextSequence, event: .quickChat(game: .boxWars, id: message.rawValue))
        nextSequence += 1
        try await transport.send(envelope)
    }

    func stop(disconnect: Bool = true) {
        guard !isStopped else { return }
        isStopped = true
        eventTask?.cancel()
        eventTask = nil
        latestQuickChat = nil
        receivedSequences.removeAll(keepingCapacity: false)
        disconnectTask?.cancel()
        if disconnect { transport.disconnect() }
    }

    private func receive(_ envelope: BattleEnvelope) async {
        guard envelope.version == BattleEnvelope.version else { return }
        switch envelope.event {
        case let .boxWarsSnapshot(state):
            guard !localIsHost, state.hostID == peerID, state.sequence > lastSnapshotSequence else { return }
            hostID = state.hostID; lastSnapshotSequence = state.sequence; snapshot = state; connectionMessage = nil
        case let .boxWarsAnswer(cellID, recordID):
            guard localIsHost else { return }
            _ = await accept(recordID: recordID, cellID: cellID, from: peerID)
        case let .quickChat(game, id):
            guard game == .boxWars, let message = BoxWarsQuickChat(rawValue: id), receivedSequences.insert(envelope.sequence).inserted else { return }
            latestQuickChat = ReceivedBoxWarsQuickChat(message: message)
        case .temporaryDisconnect:
            connectionMessage = "Connection lost — waiting up to 60 seconds."
            disconnectTask?.cancel()
            disconnectTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled, self.snapshot?.winner == nil else { return }
                if self.localIsHost { await self.finish(forfeitWinnerID: self.transport.localPlayerID) }
                else { self.finishLocally(forfeitWinnerID: self.transport.localPlayerID) }
            }
        case .reconnect:
            connectionMessage = nil; disconnectTask?.cancel()
            if localIsHost, let snapshot { try? await publish(snapshot) }
        case .forfeit:
            if localIsHost { await finish(forfeitWinnerID: transport.localPlayerID) }
            else { finishLocally(forfeitWinnerID: transport.localPlayerID) }
        default: break
        }
    }

    private func beginHostedMatch() async throws {
        guard let hostID, let grid = GridDuelEngine.generate(from: rows, seed: UInt64.random(in: 1...UInt64.max)) else { throw ArchiveLoadError.invalidArchive }
        let state = BoxWarsSnapshot(hostID: hostID, matchID: UUID().uuidString, engine: GridDuelEngine(grid: grid, archiveRows: rows), deadline: Date().addingTimeInterval(GridDuelEngine.duration), winner: nil, forfeitWinnerID: nil, sequence: nextSequence)
        snapshot = state; try await publish(state)
    }
    private func accept(recordID: String, cellID: String, from playerID: String) async -> Bool {
        guard var state = snapshot, state.winner == nil, Date() < state.deadline, let record = rows.first(where: { $0.id == recordID }) else { return false }
        var engine = state.engine
        guard engine.submit(record, to: cellID, forLocalPlayer: playerID == state.hostID, deadline: state.deadline) else { return false }
        state = BoxWarsSnapshot(hostID: state.hostID, matchID: state.matchID, engine: engine, deadline: state.deadline, winner: nil, forfeitWinnerID: nil, sequence: nextSequence)
        snapshot = state; try? await publish(state); return true
    }
    func finishIfExpired() async {
        guard let state = snapshot, state.winner == nil, Date() >= state.deadline else { return }
        if localIsHost { await finish() }
    }
    private func finish(forfeitWinnerID: String? = nil) async {
        guard let state = snapshot, state.winner == nil else { return }
        let winner = forfeitWinnerID == nil ? state.engine.resolve().winner : (forfeitWinnerID == state.hostID ? .local : .opponent)
        let final = BoxWarsSnapshot(hostID: state.hostID, matchID: state.matchID, engine: state.engine, deadline: state.deadline, winner: winner, forfeitWinnerID: forfeitWinnerID, sequence: nextSequence)
        snapshot = final; try? await publish(final)
    }
    private func finishLocally(forfeitWinnerID: String) {
        guard let state = snapshot else { return }
        snapshot = BoxWarsSnapshot(hostID: state.hostID, matchID: state.matchID, engine: state.engine, deadline: state.deadline, winner: forfeitWinnerID == state.hostID ? .local : .opponent, forfeitWinnerID: forfeitWinnerID, sequence: state.sequence + 1)
    }
    private func send(_ event: BattleEvent) async throws { try await transport.send(BattleEnvelope(sequence: nextSequence, event: event)); nextSequence += 1 }
    private func publish(_ state: BoxWarsSnapshot) async throws { try await send(.boxWarsSnapshot(state)) }

    deinit { eventTask?.cancel(); disconnectTask?.cancel() }
}

@available(*, deprecated, renamed: "BoxWarsBattleSession")
typealias BoxWarsFriendChatSession = BoxWarsBattleSession

/// The host sends this complete, versioned state after every authoritative change.
/// It makes reconnects and duplicate packets harmless: clients only render snapshots.
struct BattleSnapshot: Codable, Sendable {
    /// The inviter is authoritative for the entire private match.
    let hostID: String
    /// Generated by the host once per session; never derive ranked identity
    /// from a reusable pair of player IDs.
    let matchID: String? = nil
    let difficulty: MatchDifficulty
    let seed: UInt64
    let engine: AuctionEngine
    let stage: FriendBattleStage
    let winner: AuctionWinner?
    let winningBid: Int
    let hostBid: Int?
    let guestBid: Int?
    let deadline: Date?
    /// Set only when a peer disconnects and the remaining player wins by forfeit.
    let forfeitWinnerID: String?
    let sequence: Int
}

@MainActor final class FriendBattleSession: ObservableObject {
    @Published private(set) var snapshot: BattleSnapshot?
    @Published private(set) var connectionMessage: String?
    /// Kept separate from authoritative snapshots so chat can arrive on any
    /// gameplay screen without changing the battle state.
    @Published private(set) var latestQuickChat: ReceivedFiveAliveQuickChat?
    let transport: MatchTransport
    let opponentName: String
    var localPlayerID: String { transport.localPlayerID }
    private var nextSequence = 1
    private var lastSequence = 0
    private var receivedQuickChatSequences: Set<Int> = []
    private var bids: [String: Int] = [:]
    private var eventTask: Task<Void, Never>?
    private var pauseTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var matchupTask: Task<Void, Never>?
    private var isStopped = false

    private let usesRankedMatchupIntro: Bool
    init(transport: MatchTransport, hostID: String? = nil, difficulty: MatchDifficulty = .easy, usesRankedMatchupIntro: Bool = false) {
        self.transport = transport
        self.opponentName = transport.opponentName
        self.peerID = transport.opponentPlayerID
        // Ranked quick matches have no inviter. Pick the same deterministic
        // authority on both devices while preserving an inviter for friends.
        self.hostID = hostID ?? [transport.localPlayerID, transport.opponentPlayerID].filter { !$0.isEmpty }.min()
        self.hostDifficulty = difficulty
        self.usesRankedMatchupIntro = usesRankedMatchupIntro
    }

    /// The inviter supplies this before opening the matchmaker. Guests learn it
    /// from the first complete host snapshot.
    private var hostID: String?
    private let hostDifficulty: MatchDifficulty
    private var peerID: String
    var localIsHost: Bool { transport.localPlayerID == hostID }

    func start() async throws {
        guard !isStopped else { throw MatchTransportError.disconnected }
        guard eventTask == nil else { return }
        // Establish the stream synchronously before the peer can send. Its
        // buffer makes inbound delivery safe even before this task is scheduled.
        let events = transport.events
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await envelope in events { await self.receive(envelope) }
        }
        do {
            try await transport.connect()
        } catch {
            eventTask?.cancel()
            eventTask = nil
            throw error
        }
        try await send(.hello(version: BattleEnvelope.version, playerID: transport.localPlayerID, displayName: GKLocalPlayer.local.displayName))
        // Only the inviter creates state. Guests wait for its complete snapshot.
        if localIsHost { try await beginHostedBattle() }
    }

    func beginBidding() async throws { guard localIsHost, var snapshot else { return }; snapshot = BattleSnapshot(hostID: snapshot.hostID, difficulty: snapshot.difficulty, seed: snapshot.seed, engine: snapshot.engine, stage: .bidding, winner: nil, winningBid: 0, hostBid: nil, guestBid: nil, deadline: Date().addingTimeInterval(20), forfeitWinnerID: nil, sequence: nextSequence); self.snapshot = snapshot; bids = [:]; try await publish(snapshot); scheduleBidTimeout(round: snapshot.engine.index) }
    func submitBid(_ amount: Int) async throws {
        guard let snapshot, snapshot.stage == .bidding else { return }
        if localIsHost { try await acceptBid(amount, from: transport.localPlayerID) }
        else { try await send(.bid(round: snapshot.engine.index, amount: amount)) }
    }
    func submitPick(_ playerID: String) async throws {
        guard let snapshot else { return }
        if localIsHost { try await acceptPick(playerID, from: transport.localPlayerID) }
        else { try await send(.pick(round: snapshot.engine.index, playerID: playerID)) }
    }
    func sendQuickChat(_ message: FiveAliveQuickChat) async throws {
        try await send(.quickChat(game: .fiveAlive, id: message.rawValue))
    }
    func advance() async throws {
        guard localIsHost, let snapshot else { return }
        switch snapshot.stage {
        case .lobby, .matchup, .revealing: try await beginBidding()
        case .bidResult:
            let next = FriendBattleStage.picking
            let state = BattleSnapshot(hostID: snapshot.hostID, difficulty: snapshot.difficulty, seed: snapshot.seed, engine: snapshot.engine, stage: next, winner: snapshot.winner, winningBid: snapshot.winningBid, hostBid: snapshot.hostBid, guestBid: snapshot.guestBid, deadline: Date().addingTimeInterval(20), forfeitWinnerID: nil, sequence: nextSequence)
            self.snapshot = state; try await publish(state); schedulePickTimeout(round: state.engine.index)
        case .draftReveal:
            if snapshot.engine.isComplete { try await end() }
            else { let state = BattleSnapshot(hostID: snapshot.hostID, difficulty: snapshot.difficulty, seed: snapshot.seed, engine: snapshot.engine, stage: .revealing, winner: nil, winningBid: 0, hostBid: nil, guestBid: nil, deadline: nil, forfeitWinnerID: nil, sequence: nextSequence); self.snapshot = state; try await publish(state) }
        default: break
        }
    }
    func forfeit() async {
        guard !isStopped else { return }
        try? await send(.forfeit)
        stop()
    }

    /// Cancels all session work and releases the match state. Safe to call from
    /// every navigation path, including deinitialization.
    func stop(disconnect: Bool = true) {
        guard !isStopped else { return }
        isStopped = true
        eventTask?.cancel(); eventTask = nil
        pauseTask?.cancel(); pauseTask = nil
        deadlineTask?.cancel(); deadlineTask = nil
        matchupTask?.cancel(); matchupTask = nil
        bids.removeAll(keepingCapacity: false)
        snapshot = nil
        connectionMessage = nil
        latestQuickChat = nil
        receivedQuickChatSequences.removeAll(keepingCapacity: false)
        if disconnect { transport.disconnect() }
    }

    private func beginHostedBattle() async throws {
        let seed = UInt64.random(in: 1...UInt64.max)
        let teams = try await BundledSeasonRepository.randomTeams(count: 10, seed: seed)
        guard let hostID else { return }
        let stage: FriendBattleStage = usesRankedMatchupIntro ? .matchup : .lobby
        let state = BattleSnapshot(hostID: hostID, difficulty: hostDifficulty, seed: seed, engine: AuctionEngine(teams: teams, seed: seed), stage: stage, winner: nil, winningBid: 0, hostBid: nil, guestBid: nil, deadline: nil, forfeitWinnerID: nil, sequence: nextSequence)
        snapshot = state
        try await publish(state)
        if usesRankedMatchupIntro { scheduleMatchupAdvance() }
    }
    private func receive(_ envelope: BattleEnvelope) async {
        guard envelope.version == BattleEnvelope.version else { connectionMessage = "Your friend is using an incompatible version."; return }
        switch envelope.event {
        case let .hello(_, playerID, _): peerID = playerID; if localIsHost, snapshot == nil { try? await beginHostedBattle() }
        case let .snapshot(state):
            guard state.hostID == peerID, !localIsHost, state.sequence > lastSequence else { return }
            hostID = state.hostID; lastSequence = state.sequence; snapshot = state; connectionMessage = nil
        case let .bid(round, amount): if localIsHost, snapshot?.engine.index == round { try? await acceptBid(amount, from: peerID) }
        case let .pick(round, playerID): if localIsHost, snapshot?.engine.index == round { try? await acceptPick(playerID, from: peerID) }
        case .temporaryDisconnect: pause()
        case .reconnect: connectionMessage = nil; pauseTask?.cancel(); if localIsHost, let snapshot { try? await publish(snapshot) }
        case .forfeit:
            connectionMessage = "Friend left the match. You win by forfeit."
            if localIsHost { try? await end(winnerID: transport.localPlayerID) }
            else { endLocallyForForfeit(winnerID: transport.localPlayerID) }
        case let .ended(winnerID):
            connectionMessage = winnerID == transport.localPlayerID ? "You win." : "Friend wins."
        case let .quickChat(game, id):
            guard game == .fiveAlive,
                  let message = FiveAliveQuickChat(rawValue: id),
                  receivedQuickChatSequences.insert(envelope.sequence).inserted else { return }
            latestQuickChat = ReceivedFiveAliveQuickChat(message: message)
        case .finalOutcome:
            // These are consumed by the competitive game layer. Friend Battle
            // intentionally has no ranked-result side effects.
            break
        case .boxWarsSnapshot, .boxWarsAnswer:
            break
        }
    }
    private func acceptBid(_ amount: Int, from playerID: String) async throws {
        guard let snapshot, let hostID, amount >= 0 else { return }
        let budget = playerID == hostID ? snapshot.engine.playerBudget : snapshot.engine.opponentBudget
        guard amount <= budget, bids[playerID] == nil else { return }
        bids[playerID] = amount
        guard let hostBid = bids[hostID], let guestBid = bids[peerID] else { return }
        var engine = snapshot.engine
        guard let outcome = engine.resolve(playerBid: hostBid, opponentBid: guestBid) else { return }
        let state = BattleSnapshot(hostID: snapshot.hostID, difficulty: snapshot.difficulty, seed: snapshot.seed, engine: engine, stage: .bidResult, winner: outcome.winner, winningBid: outcome.bid, hostBid: hostBid, guestBid: guestBid, deadline: nil, forfeitWinnerID: nil, sequence: nextSequence)
        deadlineTask?.cancel(); self.snapshot = state; try await publish(state)
    }
    private func acceptPick(_ playerID: String, from player: String) async throws {
        guard let snapshot, let hostID, snapshot.stage == .picking, let winner = snapshot.winner, (winner == .player ? hostID : peerID) == player, let record = snapshot.engine.current?.players.first(where: { $0.id == playerID }) else { return }
        var engine = snapshot.engine
        guard engine.select(record, for: winner, bid: snapshot.winningBid) else { return }
        deadlineTask?.cancel(); let state = BattleSnapshot(hostID: snapshot.hostID, difficulty: snapshot.difficulty, seed: snapshot.seed, engine: engine, stage: .draftReveal, winner: winner, winningBid: snapshot.winningBid, hostBid: snapshot.hostBid, guestBid: snapshot.guestBid, deadline: nil, forfeitWinnerID: nil, sequence: nextSequence)
        self.snapshot = state; try await publish(state)
    }
    private func pause() {
        connectionMessage = "Connection lost — waiting up to 60 seconds."
        pauseTask?.cancel(); pauseTask = Task { [weak self] in try? await Task.sleep(for: .seconds(60)); guard !Task.isCancelled, let self else { return }; self.connectionMessage = "Friend did not return. You win by forfeit."; if self.localIsHost { try? await self.end(winnerID: self.transport.localPlayerID) } else { self.endLocallyForForfeit(winnerID: self.transport.localPlayerID) } }
    }
    static func winnerID(for outcome: FiveAliveMatchOutcome, hostID: String, peerID: String) -> String {
        switch outcome {
        case .localWin: hostID
        case .opponentWin, .draw: peerID
        }
    }

    private func end() async throws {
        guard let snapshot, let hostID else { return }
        let outcome = TeamSimulator.matchOutcome(player: snapshot.engine.playerRoster, opponent: snapshot.engine.opponentRoster)
        let winner = Self.winnerID(for: outcome, hostID: hostID, peerID: peerID)
        try await end(winnerID: winner, isForfeit: false)
    }
    private func end(winnerID: String) async throws { try await end(winnerID: winnerID, isForfeit: true) }
    private func end(winnerID: String, isForfeit: Bool) async throws { guard let snapshot else { return }; let state = BattleSnapshot(hostID: snapshot.hostID, difficulty: snapshot.difficulty, seed: snapshot.seed, engine: snapshot.engine, stage: .ended, winner: snapshot.winner, winningBid: snapshot.winningBid, hostBid: snapshot.hostBid, guestBid: snapshot.guestBid, deadline: nil, forfeitWinnerID: isForfeit ? winnerID : nil, sequence: nextSequence); self.snapshot = state; try await publish(state); try await send(.ended(winnerID: winnerID)) }
    private func endLocallyForForfeit(winnerID: String) { guard let snapshot else { return }; self.snapshot = BattleSnapshot(hostID: snapshot.hostID, difficulty: snapshot.difficulty, seed: snapshot.seed, engine: snapshot.engine, stage: .ended, winner: snapshot.winner, winningBid: snapshot.winningBid, hostBid: snapshot.hostBid, guestBid: snapshot.guestBid, deadline: nil, forfeitWinnerID: winnerID, sequence: nextSequence) }
    private func scheduleBidTimeout(round: Int) {
        deadlineTask?.cancel(); deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20)); guard let self, !Task.isCancelled, self.localIsHost, self.snapshot?.stage == .bidding, self.snapshot?.engine.index == round else { return }
            guard let hostID = self.hostID else { return }
            try? await self.acceptBid(self.bids[hostID] ?? 0, from: hostID)
            try? await self.acceptBid(self.bids[self.peerID] ?? 0, from: self.peerID)
        }
    }
    private func scheduleMatchupAdvance() {
        matchupTask?.cancel()
        matchupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled, self.localIsHost, let snapshot = self.snapshot, snapshot.stage == .matchup else { return }
            let state = BattleSnapshot(hostID: snapshot.hostID, difficulty: snapshot.difficulty, seed: snapshot.seed, engine: snapshot.engine, stage: .revealing, winner: nil, winningBid: 0, hostBid: nil, guestBid: nil, deadline: nil, forfeitWinnerID: nil, sequence: self.nextSequence)
            self.snapshot = state
            try? await self.publish(state)
        }
    }
    private func schedulePickTimeout(round: Int) {
        deadlineTask?.cancel(); deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20)); guard let self, !Task.isCancelled, let snapshot = self.snapshot, self.localIsHost, snapshot.stage == .picking, snapshot.engine.index == round, let winner = snapshot.winner, let pick = snapshot.engine.current?.players.first(where: { !snapshot.engine.isPlayerSelected($0) }) else { return }
            guard let hostID = self.hostID else { return }
            try? await self.acceptPick(pick.id, from: winner == .player ? hostID : self.peerID)
        }
    }
    private func send(_ event: BattleEvent) async throws { try await transport.send(BattleEnvelope(sequence: nextSequence, event: event)); nextSequence += 1 }
    private func publish(_ snapshot: BattleSnapshot) async throws { try await send(.snapshot(snapshot)); nextSequence += 1 }
    deinit { eventTask?.cancel(); pauseTask?.cancel(); deadlineTask?.cancel(); matchupTask?.cancel() }
}
