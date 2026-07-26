import Foundation
import GameKit

/// Wire format for private battles.  `sequence` lets clients safely ignore replayed
/// Game Center packets; only the host emits authoritative snapshots.
enum BattleEvent: Codable, Sendable {
    case hello(version: Int, playerID: String, displayName: String)
    case snapshot(BattleSnapshot)
    case bid(round: Int, amount: Int)
    case pick(round: Int, playerID: String)
    case pause
    case reconnect
    case forfeit
    case ended(winnerID: String)
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
        let event: BattleEvent = state == .connected ? .reconnect : .forfeit
        Task { @MainActor [weak self] in self?.continuation?.yield(BattleEnvelope(sequence: 0, event: event)) }
    }
    nonisolated func match(_ match: GKMatch, didFailWithError error: Error?) {
        Task { @MainActor [weak self] in self?.continuation?.yield(BattleEnvelope(sequence: 0, event: .forfeit)) }
    }
}

enum BotDifficulty: String, CaseIterable, Identifiable { case easy = "Easy", normal = "Normal", hard = "Hard"; var id: String { rawValue } }

enum FriendBattleStage: String, Codable, Sendable { case lobby, revealing, bidding, bidResult, picking, draftReveal, paused, ended }

/// The host sends this complete, versioned state after every authoritative change.
/// It makes reconnects and duplicate packets harmless: clients only render snapshots.
struct BattleSnapshot: Codable, Sendable {
    /// The inviter is authoritative for the entire private match.
    let hostID: String
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
    let transport: MatchTransport
    let opponentName: String
    var localPlayerID: String { transport.localPlayerID }
    private var nextSequence = 1
    private var lastSequence = 0
    private var bids: [String: Int] = [:]
    private var eventTask: Task<Void, Never>?
    private var pauseTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?

    init(transport: MatchTransport, hostID: String? = nil, difficulty: MatchDifficulty = .easy) {
        self.transport = transport
        self.opponentName = transport.opponentName
        self.peerID = transport.opponentPlayerID
        self.hostID = hostID
        self.hostDifficulty = difficulty
    }

    /// The inviter supplies this before opening the matchmaker. Guests learn it
    /// from the first complete host snapshot.
    private var hostID: String?
    private let hostDifficulty: MatchDifficulty
    private var peerID: String
    var localIsHost: Bool { transport.localPlayerID == hostID }

    func start() async throws {
        try await transport.connect()
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await envelope in self.transport.events { await self.receive(envelope) }
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
    func advance() async throws {
        guard localIsHost, let snapshot else { return }
        switch snapshot.stage {
        case .lobby, .revealing: try await beginBidding()
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
    func forfeit() async { try? await send(.forfeit); transport.disconnect() }

    private func beginHostedBattle() async throws {
        let seed = UInt64.random(in: 1...UInt64.max)
        let teams = try await BundledSeasonRepository.randomTeams(count: 10, seed: seed)
        guard let hostID else { return }
        let state = BattleSnapshot(hostID: hostID, difficulty: hostDifficulty, seed: seed, engine: AuctionEngine(teams: teams, seed: seed), stage: .lobby, winner: nil, winningBid: 0, hostBid: nil, guestBid: nil, deadline: nil, forfeitWinnerID: nil, sequence: nextSequence)
        snapshot = state
        try await publish(state)
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
        case .pause: pause()
        case .reconnect: connectionMessage = nil; pauseTask?.cancel(); if localIsHost, let snapshot { try? await publish(snapshot) }
        case .forfeit:
            connectionMessage = "Friend left the match. You win by forfeit."
            if localIsHost { try? await end(winnerID: transport.localPlayerID) }
            else { endLocallyForForfeit(winnerID: transport.localPlayerID) }
        case let .ended(winnerID):
            connectionMessage = winnerID == transport.localPlayerID ? "You win." : "Friend wins."
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
    private func end() async throws { guard let snapshot, let hostID else { return }; let winner = TeamSimulator.winner(player: snapshot.engine.playerRoster, opponent: snapshot.engine.opponentRoster) == "PLAYER WINS" ? hostID : peerID; try await end(winnerID: winner, isForfeit: false) }
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
    private func schedulePickTimeout(round: Int) {
        deadlineTask?.cancel(); deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20)); guard let self, !Task.isCancelled, let snapshot = self.snapshot, self.localIsHost, snapshot.stage == .picking, snapshot.engine.index == round, let winner = snapshot.winner, let pick = snapshot.engine.current?.players.first(where: { !snapshot.engine.isPlayerSelected($0) }) else { return }
            guard let hostID = self.hostID else { return }
            try? await self.acceptPick(pick.id, from: winner == .player ? hostID : self.peerID)
        }
    }
    private func send(_ event: BattleEvent) async throws { try await transport.send(BattleEnvelope(sequence: nextSequence, event: event)); nextSequence += 1 }
    private func publish(_ snapshot: BattleSnapshot) async throws { try await send(.snapshot(snapshot)); nextSequence += 1 }
    deinit { eventTask?.cancel(); pauseTask?.cancel(); deadlineTask?.cancel() }
}
