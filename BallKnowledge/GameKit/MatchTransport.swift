import Foundation
import GameKit

enum MatchEvent: Codable, Equatable {
    case bid(round: Int, amount: Int)
    case ready
    case draft(round: Int, winner: Int, amount: Int)
    case disconnect
    case reconnect
}

@MainActor protocol MatchTransport: AnyObject {
    var events: AsyncStream<MatchEvent> { get }
    func connect(seed: UInt64) async throws
    func send(_ event: MatchEvent) async throws
    func disconnect()
}

@MainActor final class LocalBotMatchTransport: MatchTransport {
    let difficulty: BotDifficulty
    private var continuation: AsyncStream<MatchEvent>.Continuation?
    lazy var events: AsyncStream<MatchEvent> = AsyncStream { self.continuation = $0 }
    init(difficulty: BotDifficulty = .normal) { self.difficulty = difficulty }
    func connect(seed: UInt64) async throws { }
    func send(_ event: MatchEvent) async throws {
        guard case let .bid(round, amount) = event else { return }
        let range: ClosedRange<Int> = difficulty == .easy ? 0...25 : difficulty == .hard ? 18...65 : 8...42
        var g = SeededGenerator(seed: 0xB07 &+ UInt64(round) &+ UInt64(amount))
        continuation?.yield(.bid(round: round, amount: Int.random(in: range, using: &g)))
    }
    func disconnect() { continuation?.yield(.disconnect) }
}

@MainActor final class MockMatchTransport: MatchTransport {
    private(set) var sent: [MatchEvent] = []
    private let scripted: [MatchEvent]
    private var continuation: AsyncStream<MatchEvent>.Continuation?
    lazy var events: AsyncStream<MatchEvent> = AsyncStream { self.continuation = $0 }
    init(scripted: [MatchEvent] = []) { self.scripted = scripted }
    func connect(seed: UInt64) async throws { scripted.forEach { continuation?.yield($0) } }
    func send(_ event: MatchEvent) async throws { sent.append(event) }
    func disconnect() { continuation?.yield(.disconnect) }
    func reconnect() { continuation?.yield(.reconnect) }
}

@MainActor final class GameKitMatchTransport: NSObject, MatchTransport {
    private let match: GKMatch?
    private var continuation: AsyncStream<MatchEvent>.Continuation?
    lazy var events: AsyncStream<MatchEvent> = AsyncStream { self.continuation = $0 }
    init(match: GKMatch? = nil) { self.match = match }
    func connect(seed: UInt64) async throws { }
    func send(_ event: MatchEvent) async throws {
        guard let match else { return }
        let data = try JSONEncoder().encode(event)
        try match.sendData(toAllPlayers: data, with: .reliable)
    }
    func disconnect() { continuation?.yield(.disconnect) }
}

enum BotDifficulty: String, CaseIterable, Identifiable { case easy = "Easy", normal = "Normal", hard = "Hard"; var id: String { rawValue } }
