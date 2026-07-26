import Foundation

/// A deterministic, shareable career-history clue used on one axis of a Box Wars board.
enum GridPredicate: Codable, Hashable, Sendable {
    case team(String)
    case teammateOf(String)
    case position(String)

    var label: String {
        switch self {
        case let .team(value): value == "CHA" ? "HORNETS" : TeamBrand.name(for: value).uppercased()
        case let .teammateOf(star): "TEAMMATE OF \(star.uppercased())"
        case let .position(value): value
        }
    }
}

/// Career-wide eligibility for Box Wars. A profile is intentionally identified
/// by normalized name: the bundled archive gives each historical player-season
/// a distinct row ID, while this game needs a single player across a career.
struct GridCareerEligibilityIndex: Sendable {
    static let teammateStars = [
        "LeBron James", "Stephen Curry", "Kobe Bryant", "Michael Jordan",
        "Kevin Durant", "Tim Duncan", "Giannis Antetokounmpo", "Nikola Jokić",
        "Dwyane Wade", "Chris Paul", "Dirk Nowitzki", "James Harden",
        "Kawhi Leonard", "Russell Westbrook", "Anthony Davis", "Carmelo Anthony",
        "Dwight Howard", "Paul Pierce"
    ]

    let playerIDs: Set<String>
    private let playerIDsByTeam: [String: Set<String>]
    private let playerIDsByPosition: [String: Set<String>]
    private let playerIDsByTeammateStar: [String: Set<String>]
    private let representativeRecordByPlayerID: [String: SeasonRecord]

    init(archiveRows: [SeasonRecord]) {
        var teams: [String: Set<String>] = [:]
        var positions: [String: Set<String>] = [:]
        var representatives: [String: SeasonRecord] = [:]
        var rosterBySeasonAndFranchise: [String: Set<String>] = [:]
        var namesByPlayerID: [String: String] = [:]

        for record in archiveRows {
            let playerID = Self.playerID(for: record)
            let franchise = NBAStatsDatabase.franchiseCode(for: record.team)
            teams[franchise, default: []].insert(playerID)
            for position in record.position.split(separator: "-").map(String.init) {
                positions[position, default: []].insert(playerID)
            }
            let rosterKey = "\(record.season)|\(franchise)"
            rosterBySeasonAndFranchise[rosterKey, default: []].insert(playerID)
            namesByPlayerID[playerID] = record.playerName
            if let existing = representatives[playerID] {
                if record.playerName.localizedCaseInsensitiveCompare(existing.playerName) == .orderedAscending {
                    representatives[playerID] = record
                }
            } else {
                representatives[playerID] = record
            }
        }

        var teammateStars: [String: Set<String>] = [:]
        for star in Self.teammateStars {
            let starID = Self.playerID(forName: star)
            let rosterKeys = rosterBySeasonAndFranchise.compactMap { key, roster in roster.contains(starID) ? key : nil }
            let teammates = rosterKeys.reduce(into: Set<String>()) { result, key in
                result.formUnion(rosterBySeasonAndFranchise[key] ?? [])
            }.subtracting([starID])
            if !teammates.isEmpty { teammateStars[star] = teammates }
        }

        self.playerIDs = Set(representatives.keys)
        self.playerIDsByTeam = teams
        self.playerIDsByPosition = positions
        self.playerIDsByTeammateStar = teammateStars
        self.representativeRecordByPlayerID = representatives
    }

    static func playerID(for record: SeasonRecord) -> String { playerID(forName: record.playerName) }
    static func playerID(forName name: String) -> String { NBAStatsDatabase.normalize(name) }

    func eligiblePlayerIDs(for predicate: GridPredicate) -> Set<String> {
        switch predicate {
        case let .team(team): playerIDsByTeam[team] ?? []
        case let .teammateOf(star): playerIDsByTeammateStar[star] ?? []
        case let .position(position): playerIDsByPosition[position] ?? []
        }
    }

    func eligiblePlayerIDs(for first: GridPredicate, _ second: GridPredicate) -> Set<String> {
        eligiblePlayerIDs(for: first).intersection(eligiblePlayerIDs(for: second))
    }

    func representativeRecords(for playerIDs: Set<String>, query: String = "") -> [SeasonRecord] {
        let normalized = NBAStatsDatabase.normalize(query)
        return playerIDs.compactMap { representativeRecordByPlayerID[$0] }
            .filter { normalized.isEmpty || NBAStatsDatabase.normalize($0.playerName).contains(normalized) }
            .sorted { lhs, rhs in
                lhs.playerName.localizedCaseInsensitiveCompare(rhs.playerName) == .orderedAscending
            }
    }
}

enum GridRarityTier: String, Codable, CaseIterable, Sendable {
    case common = "COMMON", uncommon = "UNCOMMON", rare = "RARE", legendary = "LEGENDARY", mythic = "MYTHIC"

    /// Lower-production qualifying seasons are harder answers and therefore score more.
    init(lowestQualifyingPerformance score: Double?) {
        guard let score else { self = .mythic; return }
        switch score {
        case ..<10: self = .mythic
        case ..<16: self = .legendary
        case ..<22: self = .rare
        case ..<29: self = .uncommon
        default: self = .common
        }
    }

    var points: Int { switch self { case .common: 1; case .uncommon: 2; case .rare: 3; case .legendary: 4; case .mythic: 5 } }
}

struct GridDuelCell: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let row: Int
    let column: Int
    let rowPredicate: GridPredicate
    let columnPredicate: GridPredicate
    let eligiblePlayerIDs: Set<String>

    var eligibleAnswerCount: Int { eligiblePlayerIDs.count }
}

struct GridDuelGrid: Codable, Hashable, Sendable {
    let id: UUID
    let rows: [GridPredicate]
    let columns: [GridPredicate]
    let cells: [GridDuelCell]

    init(id: UUID = UUID(), rows: [GridPredicate], columns: [GridPredicate], archiveRows: [SeasonRecord]) {
        precondition(rows.count == 2 && columns.count == 2)
        let index = GridCareerEligibilityIndex(archiveRows: archiveRows)
        self.id = id; self.rows = rows; self.columns = columns
        self.cells = (0..<2).flatMap { row in
            (0..<2).map { column in
                GridDuelCell(id: "\(row)-\(column)", row: row, column: column, rowPredicate: rows[row], columnPredicate: columns[column], eligiblePlayerIDs: index.eligiblePlayerIDs(for: rows[row], columns[column]))
            }
        }
    }

    func cell(row: Int, column: Int) -> GridDuelCell { cells[row * 2 + column] }
}

struct GridAnswer: Codable, Hashable, Sendable {
    let playerID: String
    let playerName: String
    let recordID: String
    let submittedAt: Date
}

enum GridCellWinner: Codable, Equatable, Sendable { case local, opponent, split, unclaimed }

struct GridDuelCellResult: Codable, Identifiable, Sendable {
    let cell: GridDuelCell
    let localAnswer: GridAnswer?
    let opponentAnswer: GridAnswer?
    let localRarity: GridRarityTier?
    let opponentRarity: GridRarityTier?
    let winner: GridCellWinner
    let localPoints: Double
    let opponentPoints: Double
    var id: String { cell.id }
}

struct GridDuelResult: Codable, Sendable {
    let cells: [GridDuelCellResult]
    let localScore: Double
    let opponentScore: Double
    let localCellsWon: Int
    let opponentCellsWon: Int
    let localSubmissionTime: TimeInterval
    let opponentSubmissionTime: TimeInterval
    let winner: GridCellWinner
}

struct GridDuelEngine: Sendable {
    static let duration: TimeInterval = 90
    let grid: GridDuelGrid
    let archiveRows: [SeasonRecord]
    private let careerIndex: GridCareerEligibilityIndex
    private(set) var localAnswers: [String: GridAnswer] = [:]
    private(set) var opponentAnswers: [String: GridAnswer] = [:]

    init(grid: GridDuelGrid, archiveRows: [SeasonRecord]) {
        self.grid = grid; self.archiveRows = archiveRows; self.careerIndex = GridCareerEligibilityIndex(archiveRows: archiveRows)
    }

    static func generate(from archiveRows: [SeasonRecord], seed: UInt64) -> GridDuelGrid? {
        let index = GridCareerEligibilityIndex(archiveRows: archiveRows)
        let franchises = Array(Set(archiveRows.map { NBAStatsDatabase.franchiseCode(for: $0.team) })).sorted()
        let positions = ["PG", "SG", "SF", "PF", "C"]
        let teammates = GridCareerEligibilityIndex.teammateStars.filter { !index.eligiblePlayerIDs(for: .teammateOf($0)).isEmpty }
        let pool = franchises.map(GridPredicate.team) + teammates.map(GridPredicate.teammateOf) + positions.map(GridPredicate.position)
        guard pool.count >= 4 else { return nil }
        var generator = SeededGenerator(seed: seed)
        for _ in 0..<250 {
            let choices = pool.shuffled(using: &generator)
            let grid = GridDuelGrid(rows: Array(choices.prefix(2)), columns: Array(choices.dropFirst(2).prefix(2)), archiveRows: archiveRows)
            if grid.cells.allSatisfy({ !$0.eligiblePlayerIDs.isEmpty }) { return grid }
        }
        return nil
    }

    /// Search returns one record per eligible career profile; callers only display its player name.
    func validRecords(for cell: GridDuelCell, query: String = "") -> [SeasonRecord] {
        careerIndex.representativeRecords(for: cell.eligiblePlayerIDs, query: query)
    }

    func rarity(for answer: GridAnswer?) -> GridRarityTier? {
        guard let answer else { return nil }
        let performances = archiveRows.filter { GridCareerEligibilityIndex.playerID(for: $0) == answer.playerID && $0.games >= 20 }
            .map { $0.points + $0.rebounds + $0.assists + $0.steals + $0.blocks }
        return GridRarityTier(lowestQualifyingPerformance: performances.min())
    }

    mutating func submit(_ record: SeasonRecord, to cellID: String, forLocalPlayer: Bool, at date: Date = Date(), deadline: Date? = nil) -> Bool {
        let playerID = GridCareerEligibilityIndex.playerID(for: record)
        guard deadline.map({ date <= $0 }) ?? true,
              archiveRows.contains(where: { $0.id == record.id }),
              let cell = grid.cells.first(where: { $0.id == cellID }),
              cell.eligiblePlayerIDs.contains(playerID) else { return false }
        let answer = GridAnswer(playerID: playerID, playerName: record.playerName, recordID: record.id, submittedAt: date)
        if forLocalPlayer { localAnswers[cellID] = answer } else { opponentAnswers[cellID] = answer }
        return true
    }

    func resolve() -> GridDuelResult {
        let cellResults = grid.cells.map { cell -> GridDuelCellResult in
            let local = localAnswers[cell.id]; let opponent = opponentAnswers[cell.id]
            let localRarity = rarity(for: local); let opponentRarity = rarity(for: opponent)
            switch (local, opponent) {
            case (.none, .none): return .init(cell: cell, localAnswer: nil, opponentAnswer: nil, localRarity: nil, opponentRarity: nil, winner: .unclaimed, localPoints: 0, opponentPoints: 0)
            case (.some, .none): return .init(cell: cell, localAnswer: local, opponentAnswer: nil, localRarity: localRarity, opponentRarity: nil, winner: .local, localPoints: Double(localRarity!.points), opponentPoints: 0)
            case (.none, .some): return .init(cell: cell, localAnswer: nil, opponentAnswer: opponent, localRarity: nil, opponentRarity: opponentRarity, winner: .opponent, localPoints: 0, opponentPoints: Double(opponentRarity!.points))
            case (.some, .some):
                let localValue = Double(localRarity!.points); let opponentValue = Double(opponentRarity!.points)
                if localValue > opponentValue { return .init(cell: cell, localAnswer: local, opponentAnswer: opponent, localRarity: localRarity, opponentRarity: opponentRarity, winner: .local, localPoints: localValue, opponentPoints: 0) }
                if opponentValue > localValue { return .init(cell: cell, localAnswer: local, opponentAnswer: opponent, localRarity: localRarity, opponentRarity: opponentRarity, winner: .opponent, localPoints: 0, opponentPoints: opponentValue) }
                return .init(cell: cell, localAnswer: local, opponentAnswer: opponent, localRarity: localRarity, opponentRarity: opponentRarity, winner: .split, localPoints: localValue / 2, opponentPoints: opponentValue / 2)
            }
        }
        let localScore = cellResults.reduce(0) { $0 + $1.localPoints }; let opponentScore = cellResults.reduce(0) { $0 + $1.opponentPoints }
        let localWins = cellResults.filter { $0.winner == .local }.count; let opponentWins = cellResults.filter { $0.winner == .opponent }.count
        let localTime = localAnswers.values.reduce(0) { $0 + $1.submittedAt.timeIntervalSince1970 }; let opponentTime = opponentAnswers.values.reduce(0) { $0 + $1.submittedAt.timeIntervalSince1970 }
        let winner: GridCellWinner
        if localScore != opponentScore { winner = localScore > opponentScore ? .local : .opponent }
        else if localWins != opponentWins { winner = localWins > opponentWins ? .local : .opponent }
        else if localTime != opponentTime { winner = localTime < opponentTime ? .local : .opponent }
        else { winner = .split }
        return .init(cells: cellResults, localScore: localScore, opponentScore: opponentScore, localCellsWon: localWins, opponentCellsWon: opponentWins, localSubmissionTime: localTime, opponentSubmissionTime: opponentTime, winner: winner)
    }
}
