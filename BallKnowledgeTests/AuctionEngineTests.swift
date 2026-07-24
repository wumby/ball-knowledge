import XCTest
@testable import BallKnowledge

final class AuctionEngineTests: XCTestCase {
    private let team = TeamSeason(id: "test", team: "TST", season: "2024–25", players: [
        SeasonRecord(id: "p1", playerName: "Point", season: "2024–25", team: "TST", position: "PG", overallRating: 90),
        SeasonRecord(id: "p2", playerName: "Wing", season: "2024–25", team: "TST", position: "SF", overallRating: 85),
        SeasonRecord(id: "p3", playerName: "Big", season: "2024–25", team: "TST", position: "C", overallRating: 80)
    ])
    func testHigherBidWinsAndSalaryChanges() { var engine = AuctionEngine(teams: [team]); let result = engine.resolve(playerBid: 31, opponentBid: 12); XCTAssertEqual(result?.winner, .player); XCTAssertEqual(engine.playerBudget, 69) }
    func testTieIsDeterministic() { var a = AuctionEngine(teams: [team], seed: 99); var b = AuctionEngine(teams: [team], seed: 99); XCTAssertEqual(a.resolve(playerBid: 20, opponentBid: 20)?.winner, b.resolve(playerBid: 20, opponentBid: 20)?.winner) }
    func testPickCompletesAuction() { var engine = AuctionEngine(teams: [team]); let outcome = engine.resolve(playerBid: 10, opponentBid: 1)!; XCTAssertTrue(engine.select(team.players[0], for: outcome.winner, bid: outcome.bid)); XCTAssertEqual(engine.index, 1); XCTAssertEqual(engine.playerRoster.count, 1); XCTAssertEqual(engine.playerWonTeams, [team]) }
    func testBotFillsAnOpenPositionWhenRatingGapIsTenOrLess() {
        let offer = TeamSeason(id: "fit", team: "FIT", season: "S", players: [
            SeasonRecord(id: "duplicate", playerName: "Another Point", season: "S", team: "FIT", position: "PG", overallRating: 90),
            SeasonRecord(id: "need", playerName: "Shooting Guard", season: "S", team: "FIT", position: "SG", overallRating: 80)
        ])
        var engine = AuctionEngine(teams: [offer])
        engine.opponentRoster = [DraftedPlayer(season: SeasonRecord(id: "existing", playerName: "Existing Point", season: "S", team: "OPP", position: "PG", overallRating: 82), bid: 1)]
        XCTAssertEqual(engine.botPick()?.playerName, "Shooting Guard")
    }
    func testBotLetsExceptionalStarOverridePositionNeed() {
        let offer = TeamSeason(id: "star", team: "STR", season: "S", players: [
            SeasonRecord(id: "star", playerName: "Elite Point", season: "S", team: "STR", position: "PG", overallRating: 96),
            SeasonRecord(id: "need", playerName: "Average Guard", season: "S", team: "STR", position: "SG", overallRating: 85)
        ])
        var engine = AuctionEngine(teams: [offer])
        engine.opponentRoster = [DraftedPlayer(season: SeasonRecord(id: "existing", playerName: "Existing Point", season: "S", team: "OPP", position: "PG", overallRating: 82), bid: 1)]
        XCTAssertEqual(engine.botPick()?.playerName, "Elite Point")
    }
    func testBotPersonalitiesPreferDifferentPlayerProfiles() {
        let offer = TeamSeason(id: "styles", team: "STY", season: "S", players: [
            SeasonRecord(id: "scorer", playerName: "Scorer", season: "S", team: "STY", position: "PG", points: 30, overallRating: 90),
            SeasonRecord(id: "defender", playerName: "Defender", season: "S", team: "STY", position: "SG", rebounds: 10, steals: 2, blocks: 3, overallRating: 90),
            SeasonRecord(id: "creator", playerName: "Creator", season: "S", team: "STY", position: "SF", assists: 10, overallRating: 90)
        ])
        XCTAssertEqual(AuctionEngine(teams: [offer], seed: 0).botPick()?.playerName, "Scorer")
        XCTAssertEqual(AuctionEngine(teams: [offer], seed: 1).botPick()?.playerName, "Defender")
        XCTAssertEqual(AuctionEngine(teams: [offer], seed: 2).botPick()?.playerName, "Creator")
    }
    func testBotBidRespectsBudgetAndExistingCap() {
        var engine = AuctionEngine(teams: [team], seed: 0)
        engine.opponentBudget = 12
        XCTAssertLessThanOrEqual(engine.botBid(), 12)
        XCTAssertLessThanOrEqual(engine.botBid(), 26)
    }
    func testBotBidsVaryAcrossOffers() {
        let teams = (0..<5).map { index in TeamSeason(id: "offer\(index)", team: "T\(index)", season: "S", players: [SeasonRecord(id: "p\(index)", playerName: "P\(index)", season: "S", team: "T\(index)", position: "PG", overallRating: 88)]) }
        let bids = (0..<teams.count).map { index -> Int in
            var engine = AuctionEngine(teams: teams, seed: 42)
            engine.index = index
            return engine.botBid()
        }
        XCTAssertGreaterThan(Set(bids).count, 1)
    }
    func testBotNameAndPersonalityAreDeterministicForSeed() {
        let a = AuctionEngine(teams: [team], seed: 123)
        let b = AuctionEngine(teams: [team], seed: 123)
        XCTAssertEqual(a.opponentName, b.opponentName)
        XCTAssertEqual(a.botPersonality, b.botPersonality)
    }
    func testPlayerDisplayOrderIsDeterministicForMatchSeed() {
        let a = AuctionEngine(teams: [team], seed: 123)
        let b = AuctionEngine(teams: [team], seed: 123)
        XCTAssertEqual(a.randomizedDisplayOrder(for: team.players).map(\.id), b.randomizedDisplayOrder(for: team.players).map(\.id))
        XCTAssertNotEqual(a.randomizedDisplayOrder(for: team.players).first?.id, "p1")
    }
    func testRepositoryProvidesTenDeterministicOffers() { let repo = BundledSeasonRepository(); XCTAssertEqual(repo.randomTeams(count: 10, seed: 4).map(\.id), repo.randomTeams(count: 10, seed: 4).map(\.id)) }
    func testFinalRatingTotalDecidesWinner() {
        let strong = SeasonRecord(id: "strong", playerName: "Strong", season: "S", team: "T", position: "PG", points: 30, rebounds: 8, assists: 9, steals: 2, blocks: 1, fgPercent: 50, threePercent: 40, ftPercent: 90, overallRating: 80)
        let weak = SeasonRecord(id: "weak", playerName: "Weak", season: "S", team: "T", position: "PG", points: 5, rebounds: 1, assists: 1, steals: 0.2, blocks: 0.1, fgPercent: 35, threePercent: 25, ftPercent: 60, overallRating: 99)
        XCTAssertEqual(TeamSimulator.winner(player: [DraftedPlayer(season: strong, bid: 1)], opponent: [DraftedPlayer(season: weak, bid: 1)]), "OPPONENT WINS")
    }
    func testRatingScaleDoesNotMakePureScorersAutomatic99s() {
        let gervin = SeasonRecord(id: "gervin", playerName: "George Gervin", season: "1979–80", team: "SAS", position: "SG", games: 78, minutes: 37, points: 33, rebounds: 5, assists: 2, steals: 1.4, blocks: 0.8, fgPercent: 52, threePercent: 0, ftPercent: 85, overallRating: 99)
        XCTAssertLessThan(SeasonRecord.calibratedRating(for: gervin), 99)
        XCTAssertEqual(SeasonRecord.calibratedRating(for: gervin), 92)
    }
    func testFullRosterVoidsLaterBidsForTheOtherSide() {
        let teams = (0..<6).map { index in TeamSeason(id: "t\(index)", team: "T\(index)", season: "S", players: [SeasonRecord(id: "p\(index)", playerName: "P\(index)", season: "S", team: "T\(index)", position: "PG", overallRating: 80)]) }
        var engine = AuctionEngine(teams: teams)
        for _ in 0..<5 { let result = engine.resolve(playerBid: 10, opponentBid: 0)!; XCTAssertEqual(result.winner, .player); XCTAssertTrue(engine.select(engine.current!.players[0], for: result.winner, bid: result.bid)) }
        let forced = engine.resolve(playerBid: 100, opponentBid: 100)
        XCTAssertEqual(forced?.winner, .opponent)
        XCTAssertEqual(forced?.bid, 0)
    }
}
