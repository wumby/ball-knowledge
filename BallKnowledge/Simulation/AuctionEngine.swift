import Foundation

struct DraftedPlayer: Identifiable, Codable, Hashable, Sendable { let id: UUID; let season: SeasonRecord; let bid: Int; init(season: SeasonRecord, bid: Int) { id = UUID(); self.season = season; self.bid = bid } }

enum AuctionWinner { case player, opponent }

enum BotPersonality: CaseIterable, Equatable {
    case starChaser
    case twoWayBuilder
    case floorGeneral

    static func forSeed(_ seed: UInt64) -> BotPersonality {
        allCases[Int(seed % UInt64(allCases.count))]
    }

    func value(of player: SeasonRecord) -> Double {
        switch self {
        case .starChaser:
            return Double(player.overallRating) * 1.2 + player.points * 1.5
        case .twoWayBuilder:
            return Double(player.overallRating) + player.rebounds * 1.2 + (player.steals + player.blocks) * 4
        case .floorGeneral:
            return Double(player.overallRating) + player.assists * 2.2
        }
    }
}

struct AuctionEngine {
    private static let botNames = ["Avery", "Blake", "Casey", "Drew", "Jordan", "Morgan", "Parker", "Quinn", "Reese"]
    private static let requiredPositions = ["PG", "SG", "SF", "PF", "C"]

    let teams: [TeamSeason]
    let seed: UInt64
    var index = 0
    var playerRoster: [DraftedPlayer] = []
    var opponentRoster: [DraftedPlayer] = []
    var playerWonTeams: [TeamSeason] = []
    var opponentWonTeams: [TeamSeason] = []
    var playerBudget = 100
    var opponentBudget = 100
    var lastWinner: AuctionWinner?
    private var submittedRounds: Set<Int> = []

    init(teams: [TeamSeason], seed: UInt64 = 1) { self.teams = teams; self.seed = seed }
    var botPersonality: BotPersonality { BotPersonality.forSeed(seed) }
    var opponentName: String { Self.botNames[Int((seed / 3) % UInt64(Self.botNames.count))] }
    var current: TeamSeason? { index < teams.count ? teams[index] : nil }
    var playerIsFull: Bool { playerRoster.count >= 5 }
    var opponentIsFull: Bool { opponentRoster.count >= 5 }
    var isComplete: Bool { index >= teams.count || (playerIsFull && opponentIsFull) }

    mutating func resolve(playerBid: Int, opponentBid: Int) -> (winner: AuctionWinner, bid: Int)? {
        guard current != nil, !submittedRounds.contains(index) else { return nil }
        let winner: AuctionWinner
        let bid: Int
        if playerIsFull { winner = .opponent; bid = 0 }
        else if opponentIsFull { winner = .player; bid = 0 }
        else {
            guard playerBid >= 0, opponentBid >= 0, playerBid <= playerBudget, opponentBid <= opponentBudget else { return nil }
            var tieGenerator = SeededGenerator(seed: seed &+ UInt64(index))
            winner = playerBid == opponentBid ? (tieGenerator.next() % 2 == 0 ? .player : .opponent) : (playerBid > opponentBid ? .player : .opponent)
            bid = winner == .player ? playerBid : opponentBid
        }
        submittedRounds.insert(index); lastWinner = winner
        if winner == .player { playerBudget -= bid } else { opponentBudget -= bid }
        return (winner, bid)
    }

    mutating func select(_ season: SeasonRecord, for winner: AuctionWinner, bid: Int) -> Bool {
        guard let team = current, team.players.contains(season), !isPlayerSelected(season), !(winner == .player ? playerIsFull : opponentIsFull) else { return false }
        let drafted = DraftedPlayer(season: season, bid: bid)
        if winner == .player {
            playerRoster.append(drafted)
            playerWonTeams.append(team)
        } else {
            opponentRoster.append(drafted)
            opponentWonTeams.append(team)
        }
        index += 1; lastWinner = nil
        return true
    }

    func botBid() -> Int {
        guard let current, !opponentIsFull else { return 0 }
        let offeredPlayers = current.players.filter { !isPlayerSelected($0) }
        guard !offeredPlayers.isEmpty else { return 0 }
        let preferredPlayer = botPreferredPick(from: offeredPlayers) ?? offeredPlayers[0]
        let valueBid = 8 + max(0, preferredPlayer.overallRating - 75) / 2
            + personalityBidAdjustment(for: preferredPlayer)
            + bidVolatility()
            + (opponentRoster.count >= 3 ? 2 : 0)
        return min(opponentBudget, max(3, min(26, valueBid)))
    }
    func botPick() -> SeasonRecord? {
        guard let current else { return nil }
        return botPreferredPick(from: current.players.filter { !isPlayerSelected($0) })
    }
    func randomizedDisplayOrder(for players: [SeasonRecord]) -> [SeasonRecord] {
        var generator = SeededGenerator(seed: seed &+ UInt64(index) &* 0x9E3779B97F4A7C15)
        var orderedPlayers = players.shuffled(using: &generator)
        guard orderedPlayers.count > 1,
              let bestRating = orderedPlayers.map(\.overallRating).max(),
              orderedPlayers[0].overallRating == bestRating,
              let replacementIndex = orderedPlayers.indices.dropFirst().first(where: { orderedPlayers[$0].overallRating < bestRating }) else {
            return orderedPlayers
        }
        orderedPlayers.swapAt(0, replacementIndex)
        return orderedPlayers
    }
    func isPlayerSelected(_ player: SeasonRecord) -> Bool { (playerRoster + opponentRoster).contains { $0.season.id == player.id } }

    private func botPreferredPick(from players: [SeasonRecord]) -> SeasonRecord? {
        guard let bestOverall = players.map(\.overallRating).max() else { return nil }
        let viablePlayers = players.filter { bestOverall - $0.overallRating <= 10 }
        let openPositions = missingPositions(in: opponentRoster)
        let positionFits = viablePlayers.filter { fillsAnOpenPosition($0, openPositions: openPositions) }
        let candidates = positionFits.isEmpty ? players.filter { $0.overallRating == bestOverall } : positionFits
        return candidates.max { candidateValue($0, fillsNeed: fillsAnOpenPosition($0, openPositions: openPositions)) < candidateValue($1, fillsNeed: fillsAnOpenPosition($1, openPositions: openPositions)) }
    }

    private func missingPositions(in roster: [DraftedPlayer]) -> Set<String> {
        let filled = Set(roster.flatMap { player in Self.requiredPositions.filter { player.season.position.contains($0) } })
        return Set(Self.requiredPositions).subtracting(filled)
    }

    private func fillsAnOpenPosition(_ player: SeasonRecord, openPositions: Set<String>) -> Bool {
        Self.requiredPositions.contains { openPositions.contains($0) && player.position.contains($0) }
    }

    private func candidateValue(_ player: SeasonRecord, fillsNeed: Bool) -> Double {
        botPersonality.value(of: player) + (fillsNeed ? 1 : 0)
    }

    private func personalityBidAdjustment(for player: SeasonRecord) -> Int {
        switch botPersonality {
        case .starChaser: return player.points >= 25 ? 2 : 0
        case .twoWayBuilder: return player.rebounds + player.steals + player.blocks >= 12 ? 2 : 0
        case .floorGeneral: return player.assists >= 8 ? 2 : 0
        }
    }
    private func bidVolatility() -> Int {
        var generator = SeededGenerator(seed: seed &+ UInt64(index) &* 0xD1B54A32D192ED03)
        let roll = Int(generator.next() % 100)
        switch roll {
        case 0..<16: return -6       // cautious round
        case 16..<65: return Int(generator.next() % 7) - 3
        case 65..<90: return 4       // assertive round
        default: return 8            // occasional splash bid
        }
    }
}

struct TeamNetRating: Equatable {
    let offense: Int
    let defense: Int
    var net: Int { offense - defense }
}

struct TeamStatLine: Equatable {
    let points: Double
    let rebounds: Double
    let assists: Double
    let steals: Double
    let blocks: Double
    let fgPercent: Double
    let threePercent: Double
}

struct LineupRole: Identifiable, Equatable {
    let title: String
    let player: String
    let strength: Int
    var id: String { title }
}

struct LineupRatingBreakdown: Equatable {
    let playerTotal: Double
    let positionPenalty: Int
    let missingPositions: [String]
    let assignments: [PositionAssignment]
    var finalRating: Double { playerTotal + Double(positionPenalty) }
}

struct PositionAssignment: Identifiable, Equatable {
    let slot: String
    let playerID: UUID?
    let isOutOfPosition: Bool
    var id: String { slot }
}

/// A display-ready fixed lineup slot for roster views.
struct CurrentTeamSlot: Identifiable, Equatable {
    let position: String
    let player: DraftedPlayer?
    var id: String { position }
}

enum TeamSimulator {
    /// Builds a five-player report lineup by taking one player from every won team-year.
    /// TeamSeason IDs (rather than franchise IDs) are deliberately used so separate
    /// historical seasons of the same franchise remain separate offers.
    static func bestPossibleLineup(from teams: [TeamSeason]) -> [DraftedPlayer] {
        let slots = ["PG", "SG", "SF", "PF", "C"]
        let orderedTeams = teams.sorted { $0.id < $1.id }
        guard !orderedTeams.isEmpty else { return [] }

        var bestLineup: [DraftedPlayer] = []
        var bestRating = -Double.infinity

        func tieBreakKey(for lineup: [DraftedPlayer]) -> [String] {
            lineup.map { $0.season.id }.sorted()
        }

        func isBetter(_ lineup: [DraftedPlayer], than current: [DraftedPlayer], rating: Double) -> Bool {
            guard rating == bestRating else { return rating > bestRating }
            return tieBreakKey(for: lineup).lexicographicallyPrecedes(tieBreakKey(for: current))
        }

        func search(slotIndex: Int, remainingTeams: [TeamSeason], lineup: [DraftedPlayer]) {
            if remainingTeams.isEmpty || slotIndex == slots.count {
                let rating = ratingBreakdown(for: lineup).finalRating
                if isBetter(lineup, than: bestLineup, rating: rating) {
                    bestRating = rating
                    bestLineup = lineup
                }
                return
            }

            let slot = slots[slotIndex]
            let positionMatches = remainingTeams.flatMap { team in
                team.players.filter { $0.position.contains(slot) }.map { (team, $0) }
            }
            let candidates = positionMatches.isEmpty
                ? remainingTeams.flatMap { team in team.players.map { (team, $0) } }
                : positionMatches

            for (team, season) in candidates.sorted(by: { lhs, rhs in
                lhs.0.id == rhs.0.id ? lhs.1.id < rhs.1.id : lhs.0.id < rhs.0.id
            }) {
                search(
                    slotIndex: slotIndex + 1,
                    remainingTeams: remainingTeams.filter { $0.id != team.id },
                    lineup: lineup + [DraftedPlayer(season: season, bid: 0)]
                )
            }
        }

        search(slotIndex: 0, remainingTeams: orderedTeams, lineup: [])
        return bestLineup
    }

    static func bestPossibleLineup(from players: [DraftedPlayer]) -> [DraftedPlayer] {
        let slots = ["PG", "SG", "SF", "PF", "C"]
        guard !players.isEmpty else { return [] }
        var bestLineup: [DraftedPlayer] = []
        var bestRating = -Double.infinity

        func search(slotIndex: Int, available: [DraftedPlayer], lineup: [DraftedPlayer]) {
            if slotIndex == slots.count || available.isEmpty {
                let rating = ratingBreakdown(for: lineup).finalRating
                if rating > bestRating {
                    bestRating = rating
                    bestLineup = lineup
                }
                return
            }

            let positionMatches = available.filter { $0.season.position.contains(slots[slotIndex]) }
            let candidates = positionMatches.isEmpty ? available : positionMatches
            for candidate in candidates {
                search(slotIndex: slotIndex + 1, available: available.filter { $0.id != candidate.id }, lineup: lineup + [candidate])
            }
        }

        search(slotIndex: 0, available: players, lineup: [])
        return bestLineup
    }
    static func lineupRating(for roster: [DraftedPlayer]) -> Double {
        roster.reduce(0) { $0 + Double($1.season.overallRating) }
    }
    static func averageLineupRating(for roster: [DraftedPlayer]) -> Double {
        guard !roster.isEmpty else { return 0 }
        return lineupRating(for: roster) / Double(roster.count)
    }
    static func ratingBreakdown(for roster: [DraftedPlayer]) -> LineupRatingBreakdown {
        let assignments = positionAssignments(for: roster)
        let missing = assignments.filter(\.isOutOfPosition).map(\.slot)
        return LineupRatingBreakdown(playerTotal: lineupRating(for: roster), positionPenalty: -7 * missing.count, missingPositions: missing, assignments: assignments)
    }
    static func positionAssignments(for roster: [DraftedPlayer]) -> [PositionAssignment] {
        let requiredPositions = ["PG", "SG", "SF", "PF", "C"]
        var unassigned = roster.map(\.season)
        var assignments: [PositionAssignment] = []
        for position in requiredPositions {
            if let index = unassigned.firstIndex(where: { $0.position.contains(position) }) {
                assignments.append(PositionAssignment(slot: position, playerID: roster.first(where: { $0.season.id == unassigned[index].id })?.id, isOutOfPosition: false))
                unassigned.remove(at: index)
            } else if let player = unassigned.first {
                assignments.append(PositionAssignment(slot: position, playerID: roster.first(where: { $0.season.id == player.id })?.id, isOutOfPosition: true))
                unassigned.removeFirst()
            } else {
                assignments.append(PositionAssignment(slot: position, playerID: nil, isOutOfPosition: true))
            }
        }
        return assignments
    }
    static func currentTeamSlots(for roster: [DraftedPlayer]) -> [CurrentTeamSlot] {
        let positions = ["PG", "SG", "SF", "PF", "C"]
        var unassigned = roster
        var slots = positions.map { CurrentTeamSlot(position: $0, player: nil) }

        // Keep natural position matches in their home slots before filling any
        // gaps with duplicate or out-of-position players.
        for index in slots.indices {
            if let playerIndex = unassigned.firstIndex(where: { $0.season.position.contains(slots[index].position) }) {
                slots[index] = CurrentTeamSlot(position: slots[index].position, player: unassigned.remove(at: playerIndex))
            }
        }

        for index in slots.indices where slots[index].player == nil && !unassigned.isEmpty {
            slots[index] = CurrentTeamSlot(position: slots[index].position, player: unassigned.removeFirst())
        }
        return slots
    }
    static func roleAssignments(for roster: [DraftedPlayer]) -> [LineupRole] {
        guard !roster.isEmpty else { return [] }
        let players = roster.map(\.season)
        func role(_ title: String, _ keyPath: KeyPath<SeasonRecord, Double>, multiplier: Double) -> LineupRole {
            let player = players.max { $0[keyPath: keyPath] < $1[keyPath: keyPath] }!
            return LineupRole(title: title, player: player.playerName, strength: Int((player[keyPath: keyPath] * multiplier).rounded()))
        }
        return [role("SCORER", \.points, multiplier: 1), role("PLAYMAKER", \.assists, multiplier: 2), role("GLASS", \.rebounds, multiplier: 1), role("STOPPER", \.steals, multiplier: 10), role("RIM PROTECTOR", \.blocks, multiplier: 10)]
    }
    static func playerImpact(_ player: SeasonRecord) -> Double { player.points + player.assists * 1.4 + player.rebounds * 0.8 + player.steals * 2.5 + player.blocks * 2.5 }
    static func stats(for roster: [DraftedPlayer]) -> TeamStatLine {
        let players = roster.map(\.season)
        return TeamStatLine(
            points: players.reduce(0) { $0 + $1.points },
            rebounds: players.reduce(0) { $0 + $1.rebounds },
            assists: players.reduce(0) { $0 + $1.assists },
            steals: players.reduce(0) { $0 + $1.steals },
            blocks: players.reduce(0) { $0 + $1.blocks },
            fgPercent: players.isEmpty ? 0 : players.reduce(0) { $0 + $1.fgPercent } / Double(players.count),
            threePercent: players.isEmpty ? 0 : players.reduce(0) { $0 + $1.threePercent } / Double(players.count)
        )
    }
    static func rating(for roster: [DraftedPlayer]) -> TeamNetRating {
        guard !roster.isEmpty else { return TeamNetRating(offense: 100, defense: 114) }
        let players = roster.map(\.season)
        let offensiveImpact = players.reduce(0.0) { total, player in
            total + player.points * 0.55 + player.assists * 0.70 + player.fgPercent * 0.04 + player.threePercent * 0.02 + player.ftPercent * 0.01
        } / Double(players.count)
        let defensiveImpact = players.reduce(0.0) { total, player in
            total + player.rebounds * 0.45 + player.steals * 2.5 + player.blocks * 2.5 + (Double(player.games) / 82.0) * 0.5
        } / Double(players.count)
        return TeamNetRating(offense: Int((102 + offensiveImpact).rounded()), defense: Int((114 - defensiveImpact).rounded()))
    }
    static func winner(player: [DraftedPlayer], opponent: [DraftedPlayer]) -> String {
        let p = ratingBreakdown(for: player).finalRating
        let o = ratingBreakdown(for: opponent).finalRating
        return p == o ? "TIE GAME" : p > o ? "YOU WIN" : "OPPONENT WINS"
    }
}
