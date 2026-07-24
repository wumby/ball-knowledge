import Foundation

protocol SeasonRepository { func randomTeams(count: Int, seed: UInt64) -> [TeamSeason] }

final class BundledSeasonRepository: SeasonRepository {
    static let allTeams: [TeamSeason] = {
        let resources = ["nba_historical_rosters", "nba_seasons"]
        for resource in resources {
            if let url = Bundle.main.url(forResource: resource, withExtension: "json"), let data = try? Data(contentsOf: url), let teams = try? JSONDecoder().decode([TeamSeason].self, from: data), !teams.isEmpty {
                return teams.map { team in TeamSeason(id: team.id, team: team.team, season: team.season, players: team.players.map { $0.recalibrated() }) }
            }
        }
        return []
    }()
    func randomTeams(count: Int, seed: UInt64) -> [TeamSeason] { var generator = SeededGenerator(seed: seed); return Array(Self.allTeams.shuffled(using: &generator).prefix(count)) }
}

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xA5A5A5A5 : seed }
    mutating func next() -> UInt64 { state &+= 0x9E3779B97F4A7C15; var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
}
