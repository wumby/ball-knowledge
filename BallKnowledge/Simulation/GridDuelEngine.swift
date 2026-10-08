import Foundation

/// A deterministic, shareable career-history clue used on one axis of a Box Wars board.
enum GridPredicate: Codable, Hashable, Sendable {
    case team(String)
    case teammateOf(GridTeammateClue)
    case position(String)
    case decade(Int)

    /// Keeps source-compatible construction for callers that only have a
    /// display name. Generated clues always supply the archive player ID.
    static func teammateOf(_ playerName: String) -> GridPredicate {
        .teammateOf(.init(playerName: playerName, playerID: GridCareerEligibilityIndex.playerID(forName: playerName)))
    }

    static func era(_ startingYear: Int) -> GridPredicate { .decade(startingYear) }

    var label: String {
        switch self {
        case let .team(value): value == "CHA" ? "HORNETS" : TeamBrand.name(for: value).uppercased()
        case let .teammateOf(star): "TEAMMATE OF \(star.playerName.uppercased())"
        case let .position(value): value
        case let .decade(startingYear): "\(startingYear)s"
        }
    }
}

/// Identity and presentation metadata for a teammate clue. `playerID` is the
/// archive identity consumed by `PlayerPortrait`, rather than a display-name
/// approximation.
struct GridTeammateClue: Codable, Hashable, Sendable {
    let playerName: String
    let playerID: String
}

/// Career-wide eligibility for Box Wars. A profile is intentionally identified
/// by normalized name: the bundled archive gives each historical player-season
/// a distinct row ID, while this game needs a single player across a career.
struct GridCareerEligibilityIndex: Sendable {
    private struct SearchableRepresentative: Sendable {
        let record: SeasonRecord
        let normalizedName: String
    }

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
    private let playerIDsByDecade: [Int: Set<String>]
    private let playerIDsByDecadeAndTeam: [String: Set<String>]
    private let representativeByPlayerID: [String: SearchableRepresentative]
    private let sortedRepresentatives: [SearchableRepresentative]
    private let careerRangeByPlayerID: [String: String]
    let availableTeammateClues: [GridTeammateClue]

    init(archiveRows: [SeasonRecord]) {
        var teams: [String: Set<String>] = [:]
        var positions: [String: Set<String>] = [:]
        var decades: [Int: Set<String>] = [:]
        var decadesAndTeams: [String: Set<String>] = [:]
        var representatives: [String: SeasonRecord] = [:]
        var seasonsByPlayerID: [String: Set<String>] = [:]
        var rosterBySeasonAndFranchise: [String: Set<String>] = [:]
        var namesByPlayerID: [String: String] = [:]

        for record in archiveRows {
            let playerID = Self.playerID(for: record)
            seasonsByPlayerID[playerID, default: []].insert(record.season)
            let franchise = NBAFranchiseIdentity.canonicalCode(for: record.team)
            teams[franchise, default: []].insert(playerID)
            if let decade = Self.decade(for: record.season) {
                decades[decade, default: []].insert(playerID)
                decadesAndTeams["\(decade)|\(franchise)", default: []].insert(playerID)
            }
            for position in record.position.split(separator: "-").map(String.init) {
                positions[position, default: []].insert(playerID)
                for broadPosition in Self.broadPositionGroups(for: position) {
                    positions[broadPosition, default: []].insert(playerID)
                }
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
        var teammateClues: [GridTeammateClue] = []
        for star in Self.teammateStars {
            let starID = Self.playerID(forName: star)
            let rosterKeys = rosterBySeasonAndFranchise.compactMap { key, roster in roster.contains(starID) ? key : nil }
            let teammates = rosterKeys.reduce(into: Set<String>()) { result, key in
                result.formUnion(rosterBySeasonAndFranchise[key] ?? [])
            }.subtracting([starID])
            if !teammates.isEmpty {
                teammateStars[star] = teammates
                let archivePlayerID = archiveRows.first(where: { Self.playerID(for: $0) == starID })?.playerID ?? starID
                teammateClues.append(.init(playerName: star, playerID: archivePlayerID))
            }
        }

        self.playerIDs = Set(representatives.keys)
        self.playerIDsByTeam = teams
        self.playerIDsByPosition = positions
        self.playerIDsByTeammateStar = teammateStars
        self.playerIDsByDecade = decades
        self.playerIDsByDecadeAndTeam = decadesAndTeams
        let searchableRepresentatives = representatives.mapValues {
            SearchableRepresentative(record: $0, normalizedName: NBAStatsDatabase.normalize($0.playerName))
        }
        self.representativeByPlayerID = searchableRepresentatives
        self.sortedRepresentatives = searchableRepresentatives.values.sorted(by: Self.sortRepresentatives)
        self.careerRangeByPlayerID = seasonsByPlayerID.reduce(into: [:]) { ranges, entry in
            let seasons = entry.value.sorted()
            guard let first = seasons.first else { return }
            guard let last = seasons.last, last != first else {
                ranges[entry.key] = first
                return
            }
            ranges[entry.key] = "\(first.prefix(4)) – \(Self.seasonEndYear(last))"
        }
        self.availableTeammateClues = teammateClues
    }

    static func playerID(for record: SeasonRecord) -> String { playerID(forName: record.playerName) }
    static func playerID(forName name: String) -> String { NBAStatsDatabase.normalize(name) }
    static func decade(for season: String) -> Int? {
        guard let startingYear = Int(season.prefix(4)) else { return nil }
        return (startingYear / 10) * 10
    }

    private static func sortRepresentatives(_ lhs: SearchableRepresentative, _ rhs: SearchableRepresentative) -> Bool {
        let nameOrder = lhs.record.playerName.localizedCaseInsensitiveCompare(rhs.record.playerName)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.record.id < rhs.record.id
    }

    private static func seasonEndYear(_ season: String) -> String {
        let normalizedSeason = season.replacingOccurrences(of: "–", with: "-")
        let years = normalizedSeason.split(separator: "-", maxSplits: 1).map(String.init)
        guard years.count == 2 else { return String(normalizedSeason.suffix(4)) }

        let endYear = years[1]
        if endYear.count == 4, Int(endYear) != nil { return endYear }
        guard let startYear = Int(years[0].prefix(4)), let abbreviatedEndYear = Int(endYear) else {
            return String(normalizedSeason.suffix(4))
        }

        var fullEndYear = (startYear / 100) * 100 + abbreviatedEndYear
        if fullEndYear < startYear { fullEndYear += 100 }
        return String(fullEndYear)
    }

    /// Broad Box Wars clues intentionally accept every historical position in
    /// their group, while the exact-position entries above remain available for
    /// already serialized boards and direct callers.
    private static func broadPositionGroups(for position: String) -> [String] {
        switch position {
        case "PG", "SG": ["G"]
        case "SF", "PF", "C": ["F/C"]
        default: []
        }
    }

    func eligiblePlayerIDs(for predicate: GridPredicate) -> Set<String> {
        switch predicate {
        case let .team(team): playerIDsByTeam[team] ?? []
        case let .teammateOf(star): playerIDsByTeammateStar[star.playerName] ?? []
        case let .position(position): playerIDsByPosition[position] ?? []
        case let .decade(startingYear): playerIDsByDecade[startingYear] ?? []
        }
    }

    func eligiblePlayerIDs(for first: GridPredicate, _ second: GridPredicate) -> Set<String> {
        // Era + franchise is a deliberately same-player-season constraint.
        // Other Box Wars intersections continue to use career-wide eligibility.
        switch (first, second) {
        case let (.decade(decade), .team(team)), let (.team(team), .decade(decade)):
            return playerIDsByDecadeAndTeam["\(decade)|\(team)"] ?? []
        default:
            return eligiblePlayerIDs(for: first).intersection(eligiblePlayerIDs(for: second))
        }
    }

    func representativeRecords(for playerIDs: Set<String>, query: String = "") -> [SeasonRecord] {
        let normalized = NBAStatsDatabase.normalize(query)
        return playerIDs.compactMap { representativeByPlayerID[$0] }
            .filter { normalized.isEmpty || $0.normalizedName.contains(normalized) }
            .sorted(by: Self.sortRepresentatives)
            .map(\.record)
    }

    /// The global player picker follows this pre-sorted list, so a query does
    /// not re-sort the entire archive on every keystroke.
    func searchRecords(query: String, limit: Int) -> [SeasonRecord] {
        guard limit > 0 else { return [] }
        let normalized = NBAStatsDatabase.normalize(query)
        var matches: [SeasonRecord] = []
        matches.reserveCapacity(min(limit, sortedRepresentatives.count))
        for representative in sortedRepresentatives where normalized.isEmpty || representative.normalizedName.contains(normalized) {
            matches.append(representative.record)
            if matches.count == limit { break }
        }
        return matches
    }

    func careerRange(for record: SeasonRecord) -> String {
        careerRangeByPlayerID[Self.playerID(for: record)] ?? record.season
    }
}

enum GridRarityTier: String, Codable, CaseIterable, Sendable {
    case common = "COMMON", uncommon = "UNCOMMON", rare = "RARE", legendary = "LEGENDARY", mythic = "MYTHIC"

    /// Career peak production determines rarity. Players who never sustained a
    /// high-production 20-game season remain the hardest Box Wars answers.
    init(peakQualifyingPerformance score: Double?) {
        guard let score else { self = .mythic; return }
        switch score {
        case ..<5.5: self = .mythic
        case ..<9.3: self = .legendary
        case ..<16.1: self = .rare
        case ..<24.6: self = .uncommon
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

enum GridDuelWinner: Codable, Equatable, Sendable { case local, opponent, draw }

struct GridDuelCellResult: Codable, Identifiable, Sendable {
    let cell: GridDuelCell
    let localAnswer: GridAnswer?
    let opponentAnswer: GridAnswer?
    let localRarity: GridRarityTier?
    let opponentRarity: GridRarityTier?
    let localPoints: Double
    let opponentPoints: Double
    var id: String { cell.id }
}

struct GridDuelResult: Codable, Sendable {
    let cells: [GridDuelCellResult]
    let localScore: Double
    let opponentScore: Double
    let localSubmissionTime: TimeInterval
    let opponentSubmissionTime: TimeInterval
    let winner: GridDuelWinner
}

/// The ideal answer for one Box Wars intersection, independent of either
/// competitor's submitted answer.
struct GridBestAnswer: Identifiable, Equatable, Sendable {
    let cell: GridDuelCell
    let portraitPlayerID: String
    let playerName: String
    let rarity: GridRarityTier
    let points: Int
    var id: String { cell.id }
}

struct GridDuelEngine: Codable, Sendable {
    static let duration: TimeInterval = 90

    /// These canonical franchises include historical names or locations that
    /// cannot be represented by one reliable team-logo clue.
    static let excludedTeamClueFranchiseCodes: Set<String> = [
        "BKN", "CHA", "NOP", "OKC", "MEM", "SAC", "LAC", "WAS"
    ]

    let grid: GridDuelGrid
    let archiveRows: [SeasonRecord]
    private let careerIndex: GridCareerEligibilityIndex
    private(set) var localAnswers: [String: GridAnswer] = [:]
    private(set) var opponentAnswers: [String: GridAnswer] = [:]

    init(grid: GridDuelGrid, archiveRows: [SeasonRecord]) {
        self.grid = grid; self.archiveRows = archiveRows; self.careerIndex = GridCareerEligibilityIndex(archiveRows: archiveRows)
    }

    private enum CodingKeys: String, CodingKey { case grid, archiveRows, localAnswers, opponentAnswers }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        grid = try container.decode(GridDuelGrid.self, forKey: .grid)
        archiveRows = try container.decode([SeasonRecord].self, forKey: .archiveRows)
        careerIndex = GridCareerEligibilityIndex(archiveRows: archiveRows)
        localAnswers = try container.decode([String: GridAnswer].self, forKey: .localAnswers)
        opponentAnswers = try container.decode([String: GridAnswer].self, forKey: .opponentAnswers)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(grid, forKey: .grid)
        try container.encode(archiveRows, forKey: .archiveRows)
        try container.encode(localAnswers, forKey: .localAnswers)
        try container.encode(opponentAnswers, forKey: .opponentAnswers)
    }

    /// Team-clue eligibility is intentionally narrower than the archive's
    /// franchise identity rules. This affects generated Box Wars clues only.
    static func isEligibleTeamClue(for team: String) -> Bool {
        !excludedTeamClueFranchiseCodes.contains(NBAFranchiseIdentity.canonicalCode(for: team))
    }

    static func generate(from archiveRows: [SeasonRecord], seed: UInt64) -> GridDuelGrid? {
        let index = GridCareerEligibilityIndex(archiveRows: archiveRows)
        let franchises = Array(Set(archiveRows.map { NBAFranchiseIdentity.canonicalCode(for: $0.team) }))
            .filter(isEligibleTeamClue)
            .sorted()
        let positions = ["G", "F/C"]
        let teammates = index.availableTeammateClues
        let decades = Array(Set(archiveRows.compactMap { GridCareerEligibilityIndex.decade(for: $0.season) })).sorted()
        let pool = franchises.map(GridPredicate.team) + teammates.map(GridPredicate.teammateOf) + positions.map(GridPredicate.position) + decades.map(GridPredicate.decade)
        guard pool.count >= 4 else { return nil }
        var generator = SeededGenerator(seed: seed)
        for _ in 0..<250 {
            let choices = pool.shuffled(using: &generator)
            let rows = Array(choices.prefix(2))
            let columns = Array(choices.dropFirst(2).prefix(2))
            let hasEraRow = rows.contains { if case .decade = $0 { true } else { false } }
            let hasEraColumn = columns.contains { if case .decade = $0 { true } else { false } }
            guard !(hasEraRow && hasEraColumn) else { continue }

            let grid = GridDuelGrid(rows: rows, columns: columns, archiveRows: archiveRows)
            if grid.cells.allSatisfy({ !$0.eligiblePlayerIDs.isEmpty }) { return grid }
        }
        return nil
    }

    /// Search returns one record per eligible career profile; callers only display its player name.
    func validRecords(for cell: GridDuelCell, query: String = "") -> [SeasonRecord] {
        careerIndex.representativeRecords(for: cell.eligiblePlayerIDs, query: query)
    }

    /// Searches the complete career archive. Eligibility deliberately remains enforced by `submit`;
    /// this lets players try an answer without revealing the solution set in the search UI.
    func searchRecords(query: String = "", limit: Int = 30) -> [SeasonRecord] {
        careerIndex.searchRecords(query: query, limit: limit)
    }

    /// A player picker result represents a career, even though it is backed by
    /// one archive record. Show the first season's start year and the last
    /// season's end year for multi-season careers.
    func careerRange(for record: SeasonRecord) -> String {
        careerIndex.careerRange(for: record)
    }

    func rarity(for answer: GridAnswer?) -> GridRarityTier? {
        guard let answer else { return nil }
        let performances = archiveRows.filter { GridCareerEligibilityIndex.playerID(for: $0) == answer.playerID && $0.games >= 20 }
            .map { $0.points + $0.rebounds + $0.assists + $0.steals + $0.blocks }
        return GridRarityTier(peakQualifyingPerformance: performances.max())
    }

    /// Finds the highest-value valid career answer for a cell. Names break
    /// equal-point ties alphabetically so a shared grid always resolves alike.
    func bestValidAnswer(for cell: GridDuelCell) -> GridBestAnswer? {
        validRecords(for: cell)
            .compactMap { record -> GridBestAnswer? in
                let answer = GridAnswer(playerID: GridCareerEligibilityIndex.playerID(for: record), playerName: record.playerName, recordID: record.id, submittedAt: .distantPast)
                guard let rarity = rarity(for: answer) else { return nil }
                return GridBestAnswer(cell: cell, portraitPlayerID: record.playerID, playerName: record.playerName, rarity: rarity, points: rarity.points)
            }
            .sorted {
                if $0.points != $1.points { return $0.points > $1.points }
                return $0.playerName.localizedCaseInsensitiveCompare($1.playerName) == .orderedAscending
            }
            .first
    }

    func bestValidAnswers() -> [GridBestAnswer] {
        grid.cells.compactMap(bestValidAnswer(for:))
    }

    /// Selects a predictable ranked AI answer. A point ceiling never leaves a
    /// cell unanswered: sparse boards fall back to their weakest valid answer.
    func rankedAIAnswer(for cell: GridDuelCell, profile: BoxWarsAIProfile) -> SeasonRecord? {
        let rankedAnswers = validRecords(for: cell).compactMap { record -> (record: SeasonRecord, points: Int)? in
            let answer = GridAnswer(playerID: GridCareerEligibilityIndex.playerID(for: record), playerName: record.playerName, recordID: record.id, submittedAt: .distantPast)
            guard let rarity = rarity(for: answer) else { return nil }
            return (record, rarity.points)
        }

        let weakest = rankedAnswers.sorted(by: rankedAIAnswerOrder(ascending: true)).first
        switch profile.answerStrategy {
        case .weakest:
            return weakest?.record
        case .strongest:
            return rankedAnswers.sorted(by: rankedAIAnswerOrder(ascending: false)).first?.record
        case .highestWithinCeiling:
            return rankedAnswers
                .filter { $0.points <= profile.maximumAnswerPoints }
                .sorted(by: rankedAIAnswerOrder(ascending: false))
                .first?
                .record ?? weakest?.record
        }
    }

    func rankedAIAnswers(profile: BoxWarsAIProfile) -> [(cell: GridDuelCell, answer: SeasonRecord)] {
        grid.cells.prefix(profile.filledCellCount).compactMap { cell in
            rankedAIAnswer(for: cell, profile: profile).map { (cell, $0) }
        }
    }

    private func rankedAIAnswerOrder(ascending: Bool) -> ((record: SeasonRecord, points: Int), (record: SeasonRecord, points: Int)) -> Bool {
        { lhs, rhs in
            if lhs.points != rhs.points { return ascending ? lhs.points < rhs.points : lhs.points > rhs.points }
            return lhs.record.playerName.localizedCaseInsensitiveCompare(rhs.record.playerName) == .orderedAscending
        }
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
            return .init(
                cell: cell,
                localAnswer: local,
                opponentAnswer: opponent,
                localRarity: localRarity,
                opponentRarity: opponentRarity,
                localPoints: Double(localRarity?.points ?? 0),
                opponentPoints: Double(opponentRarity?.points ?? 0)
            )
        }
        let localScore = cellResults.reduce(0) { $0 + $1.localPoints }; let opponentScore = cellResults.reduce(0) { $0 + $1.opponentPoints }
        let localTime = localAnswers.values.reduce(0) { $0 + $1.submittedAt.timeIntervalSince1970 }; let opponentTime = opponentAnswers.values.reduce(0) { $0 + $1.submittedAt.timeIntervalSince1970 }
        let winner: GridDuelWinner = localScore == opponentScore ? .draw : (localScore > opponentScore ? .local : .opponent)
        return .init(cells: cellResults, localScore: localScore, opponentScore: opponentScore, localSubmissionTime: localTime, opponentSubmissionTime: opponentTime, winner: winner)
    }
}
