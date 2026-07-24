import Foundation
import SwiftData

@Model
final class PlayerSeason {
    var id: String; var playerName: String; var season: String; var team: String; var position: String
    var games: Int; var minutes: Double; var points: Double; var rebounds: Double; var assists: Double
    var steals: Double; var blocks: Double; var fgPercent: Double; var threePercent: Double; var ftPercent: Double; var overallRating: Int
    init(id: String, playerName: String, season: String, team: String, position: String, games: Int = 75, minutes: Double = 30, points: Double = 15, rebounds: Double = 5, assists: Double = 3, steals: Double = 1, blocks: Double = 0.5, fgPercent: Double = 45, threePercent: Double = 35, ftPercent: Double = 75, overallRating: Int) {
        self.id = id; self.playerName = playerName; self.season = season; self.team = team; self.position = position; self.games = games; self.minutes = minutes; self.points = points; self.rebounds = rebounds; self.assists = assists; self.steals = steals; self.blocks = blocks; self.fgPercent = fgPercent; self.threePercent = threePercent; self.ftPercent = ftPercent; self.overallRating = overallRating
    }
}

struct SeasonRecord: Codable, Identifiable, Hashable {
    let id: String; let playerName: String; let season: String; let team: String; let position: String
    let games: Int; let minutes: Double; let points: Double; let rebounds: Double; let assists: Double
    let steals: Double; let blocks: Double; let fgPercent: Double; let threePercent: Double; let ftPercent: Double; let overallRating: Int

    init(id: String, playerName: String, season: String, team: String, position: String, games: Int = 75, minutes: Double = 30, points: Double = 15, rebounds: Double = 5, assists: Double = 3, steals: Double = 1, blocks: Double = 0.5, fgPercent: Double = 45, threePercent: Double = 35, ftPercent: Double = 75, overallRating: Int) {
        self.id = id; self.playerName = playerName; self.season = season; self.team = team; self.position = position; self.games = games; self.minutes = minutes; self.points = points; self.rebounds = rebounds; self.assists = assists; self.steals = steals; self.blocks = blocks; self.fgPercent = fgPercent; self.threePercent = threePercent; self.ftPercent = ftPercent; self.overallRating = overallRating
    }

    /// Tough 2K-style rating scale. A 99 requires elite scoring, playmaking,
    /// defense, and efficiency—not simply a huge scoring average.
    static func calibratedRating(for player: SeasonRecord) -> Int {
        let efficiency = max(0, player.fgPercent - 45) * 0.18
            + max(0, player.threePercent - 33) * 0.08
            + max(0, player.ftPercent - 75) * 0.06
        let value = 60
            + player.points * 0.65
            + player.rebounds * 0.70
            + player.assists * 0.75
            + player.steals * 1.50
            + player.blocks * 1.50
            + efficiency
        return min(96, max(60, Int(value.rounded())))
    }

    func recalibrated() -> SeasonRecord {
        SeasonRecord(id: id, playerName: playerName, season: season, team: team, position: position, games: games, minutes: minutes, points: points, rebounds: rebounds, assists: assists, steals: steals, blocks: blocks, fgPercent: fgPercent, threePercent: threePercent, ftPercent: ftPercent, overallRating: Self.calibratedRating(for: self))
    }
}

struct TeamSeason: Codable, Identifiable, Hashable {
    let id: String
    let team: String
    let season: String
    let players: [SeasonRecord]

    init(id: String, team: String, season: String, players: [SeasonRecord]) { self.id = id; self.team = team; self.season = season; self.players = players }
}

enum MatchDifficulty: String, CaseIterable, Identifiable, Codable {
    case easy = "Casual", medium = "2K Player", ballKnowledge = "Ball Knower"
    var id: String { rawValue }
    var subtitle: String { switch self { case .easy: "Players + stats"; case .medium: "Players, no stats"; case .ballKnowledge: "Team-year only" } }
}
