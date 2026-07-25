import Foundation

enum ArchiveLoadError: LocalizedError {
    case missingResource, invalidArchive
    var errorDescription: String? {
        switch self {
        case .missingResource: "The NBA archive is missing from this app build."
        case .invalidArchive: "The NBA archive could not be read."
        }
    }
}

/// A session-lifetime, offline database. Decoding and index construction happen in a
/// detached task; the immutable result is shared by gameplay and Stats.
actor NBAStatsStore {
    static let shared = NBAStatsStore()
    private var loadTask: Task<NBAStatsDatabase, Error>?

    func database() async throws -> NBAStatsDatabase {
        if let loadTask { return try await loadTask.value }
        guard let url = Bundle.main.url(forResource: "nba_historical_rosters", withExtension: "json") else {
            throw ArchiveLoadError.missingResource
        }
        let task = Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let teams: [TeamSeason]
            if let archive = try? decoder.decode(NBAArchive.self, from: data) {
                teams = archive.teamSeasons
            } else if let legacyTeams = try? decoder.decode([TeamSeason].self, from: data) {
                teams = legacyTeams
            } else {
                throw ArchiveLoadError.invalidArchive
            }
            guard !teams.isEmpty else { throw ArchiveLoadError.invalidArchive }
            return NBAStatsDatabase(teamSeasons: teams)
        }
        loadTask = task
        return try await task.value
    }
}

struct NBAPlayerProfile: Identifiable, Hashable, Sendable {
    let id: String
    let playerName: String
    let seasons: [SeasonRecord]
}

struct NBAFranchise: Identifiable, Hashable, Sendable {
    let id: String
    let teamCodes: [String]
    var name: String { TeamBrand.name(for: id) }
}

enum LeaderStat: String, CaseIterable, Identifiable, Sendable {
    case points = "Points", games = "Games", minutes = "Minutes", rebounds = "Rebounds", assists = "Assists"
    case steals = "Steals", blocks = "Blocks", fgPercent = "FG%", threePercent = "3P%", ftPercent = "FT%"

    var id: String { rawValue }
    var shortLabel: String {
        switch self {
        case .games: return "G"
        case .minutes: return "MPG"
        case .points: return "PPG"
        case .rebounds: return "RPG"
        case .assists: return "APG"
        case .steals: return "SPG"
        case .blocks: return "BPG"
        case .fgPercent: return "FG%"
        case .threePercent: return "3P%"
        case .ftPercent: return "FT%"
        }
    }
}

/// A player-season used in league leader lists. A record represents the combined
/// season when a player appeared for more than one team.
struct NBALeaderEntry: Identifiable, Hashable, Sendable {
    let record: SeasonRecord
    let teamLabel: String
    let stat: LeaderStat

    var id: String { "\(record.playerID)-\(record.season)-\(stat.rawValue)" }
    var value: Double {
        switch stat {
        case .games: Double(record.games)
        case .minutes: record.minutes
        case .points: record.points
        case .rebounds: record.rebounds
        case .assists: record.assists
        case .steals: record.steals
        case .blocks: record.blocks
        case .fgPercent: record.fgPercent
        case .threePercent: record.threePercent
        case .ftPercent: record.ftPercent
        }
    }
}

struct NBAStatsDatabase: Sendable {
    /// A small-sample guard for rate stats. Shot-attempt totals are not stored, so
    /// games played is the best available qualification proxy for percentages.
    static let leaderMinimumGames = 20
    let teamSeasons: [TeamSeason]
    let playerProfiles: [NBAPlayerProfile]
    let profilesByNormalizedName: [String: [NBAPlayerProfile]]
    let teamSeasonsByFranchise: [String: [TeamSeason]]
    let teamSeasonsBySeason: [String: [TeamSeason]]
    let franchises: [NBAFranchise]
    let seasons: [String]
    let positions: [String]

    init(teamSeasons: [TeamSeason]) {
        let recalibratedTeams = teamSeasons.map {
            TeamSeason(id: $0.id, team: $0.team, season: $0.season, players: $0.players.map { $0.recalibrated() })
        }
        self.teamSeasons = recalibratedTeams

        let allRows = recalibratedTeams.flatMap(\.players)
        let profiles = Dictionary(grouping: allRows, by: \.playerID).map { playerID, rows in
            NBAPlayerProfile(
                id: playerID,
                playerName: rows.first?.playerName ?? "Unknown Player",
                seasons: rows.sorted { seasonSortKey($0.season) > seasonSortKey($1.season) }
            )
        }.sorted { $0.playerName.localizedCaseInsensitiveCompare($1.playerName) == .orderedAscending }
        self.playerProfiles = profiles
        self.profilesByNormalizedName = Dictionary(grouping: profiles, by: { Self.normalize($0.playerName) })
        self.teamSeasonsByFranchise = Dictionary(grouping: recalibratedTeams, by: { Self.franchiseCode(for: $0.team) })
            .mapValues { $0.sorted { seasonSortKey($0.season) > seasonSortKey($1.season) } }
        self.teamSeasonsBySeason = Dictionary(grouping: recalibratedTeams, by: \.season)
            .mapValues { $0.sorted { $0.team < $1.team } }
        self.seasons = Array(Set(recalibratedTeams.map(\.season))).sorted { seasonSortKey($0) > seasonSortKey($1) }
        self.positions = ["PG", "SG", "SF", "PF", "C"]
        self.franchises = teamSeasonsByFranchise.map { code, rows in
            NBAFranchise(id: code, teamCodes: Array(Set(rows.map(\.team))).sorted())
        }.sorted { $0.name < $1.name }
    }

    func searchPlayers(_ query: String, limit: Int = 50) -> [NBAPlayerProfile] {
        let normalizedQuery = Self.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }
        var rankedProfiles: [(rank: Int, profile: NBAPlayerProfile)] = []
        for profile in playerProfiles {
            let name = Self.normalize(profile.playerName)
            if name == normalizedQuery { rankedProfiles.append((0, profile)) }
            else if name.hasPrefix(normalizedQuery) { rankedProfiles.append((1, profile)) }
            else if name.contains(normalizedQuery) { rankedProfiles.append((2, profile)) }
        }
        rankedProfiles.sort {
            $0.rank == $1.rank
                ? $0.profile.playerName.localizedCaseInsensitiveCompare($1.profile.playerName) == .orderedAscending
                : $0.rank < $1.rank
        }
        return Array(rankedProfiles.prefix(limit).map(\.profile))
    }

    func rows(for profile: NBAPlayerProfile, season: String? = nil, franchise: String? = nil, position: String? = nil) -> [SeasonRecord] {
        profile.seasons.filter { row in
            (season == nil || row.season == season!)
                && (franchise == nil || Self.franchiseCode(for: row.team) == franchise!)
                && (position == nil || row.position.split(separator: "-").contains(Substring(position!)))
        }
    }

    /// Returns the top player-seasons for a stat. `nil` includes every archived
    /// season, so All Time compares single-season performances rather than careers.
    func leaders(for stat: LeaderStat, season: String? = nil, limit: Int = 10) -> [NBALeaderEntry] {
        let rows = teamSeasons.flatMap(\.players).filter { season == nil || $0.season == season }
        let combined = Dictionary(grouping: rows, by: { "\($0.playerID)|\($0.season)" }).map { _, stints in
            NBALeaderEntry(record: Self.combinedSeason(stints), teamLabel: Set(stints.map(\.team)).count == 1 ? stints[0].team : "Multiple Teams", stat: stat)
        }
        let eligible = stat == .games ? combined : combined.filter { $0.record.games >= Self.leaderMinimumGames }
        return Array(eligible.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            if lhs.record.games != rhs.record.games { return lhs.record.games > rhs.record.games }
            let nameOrder = lhs.record.playerName.localizedCaseInsensitiveCompare(rhs.record.playerName)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.record.playerID < rhs.record.playerID
        }.prefix(limit))
    }

    private static func combinedSeason(_ stints: [SeasonRecord]) -> SeasonRecord {
        precondition(!stints.isEmpty)
        let first = stints[0]
        let games = stints.reduce(0) { $0 + $1.games }
        let weighted: (KeyPath<SeasonRecord, Double>) -> Double = { keyPath in
            guard games > 0 else { return 0 }
            return stints.reduce(0) { $0 + $1[keyPath: keyPath] * Double($1.games) } / Double(games)
        }
        let teams = Set(stints.map(\.team))
        let positions = Array(Set(stints.map(\.position))).sorted()
        return SeasonRecord(
            id: "\(first.playerID)-\(first.season)-leaders",
            playerID: first.playerID,
            playerName: first.playerName,
            season: first.season,
            team: teams.count == 1 ? first.team : "Multiple Teams",
            position: positions.joined(separator: "/"),
            games: games,
            minutes: weighted(\.minutes), points: weighted(\.points), rebounds: weighted(\.rebounds),
            assists: weighted(\.assists), steals: weighted(\.steals), blocks: weighted(\.blocks),
            fgPercent: weighted(\.fgPercent), threePercent: weighted(\.threePercent), ftPercent: weighted(\.ftPercent),
            overallRating: first.overallRating
        )
    }

    static func franchiseCode(for team: String) -> String {
        ["NJN": "BRK", "VAN": "MEM", "SEA": "OKC", "KCK": "SAC", "SDC": "LAC", "WSB": "WAS", "NOH": "NOP", "NOK": "NOP", "PHO": "PHX"][team] ?? team
    }

    static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}

private func seasonSortKey(_ season: String) -> Int {
    Int(season.prefix(4)) ?? 0
}

enum BundledSeasonRepository {
    static func loadTeams() async throws -> [TeamSeason] {
        try await NBAStatsStore.shared.database().teamSeasons
    }

    static func randomTeams(count: Int, seed: UInt64) async throws -> [TeamSeason] {
        var generator = SeededGenerator(seed: seed)
        return Array(try await loadTeams().shuffled(using: &generator).prefix(count))
    }
}

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xA5A5A5A5 : seed }
    mutating func next() -> UInt64 { state &+= 0x9E3779B97F4A7C15; var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
}
