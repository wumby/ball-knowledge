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
    func testCurrentTeamSlotsAreEmptyForAnEmptyRoster() {
        let slots = TeamSimulator.currentTeamSlots(for: [])
        XCTAssertEqual(slots.map(\.position), ["PG", "SG", "SF", "PF", "C"])
        XCTAssertTrue(slots.allSatisfy { $0.player == nil })
    }
    func testCurrentTeamSlotsPlaceAPartialRosterInAssignedSlots() {
        let point = DraftedPlayer(season: SeasonRecord(id: "point", playerName: "Point", season: "S", team: "T", position: "PG", overallRating: 80), bid: 1)
        let shootingGuard = DraftedPlayer(season: SeasonRecord(id: "guard", playerName: "Guard", season: "S", team: "T", position: "SG", overallRating: 80), bid: 1)
        let slots = TeamSimulator.currentTeamSlots(for: [point, shootingGuard])
        XCTAssertEqual(slots.map { $0.player?.season.playerName }, ["Point", "Guard", nil, nil, nil])
    }
    func testCurrentTeamSlotsKeepShootingGuardAndCenterInNaturalSlots() {
        let shootingGuard = DraftedPlayer(season: SeasonRecord(id: "sg", playerName: "Shooting Guard", season: "S", team: "T", position: "SG", overallRating: 80), bid: 1)
        let center = DraftedPlayer(season: SeasonRecord(id: "c", playerName: "Center", season: "S", team: "T", position: "C", overallRating: 80), bid: 1)
        let slots = TeamSimulator.currentTeamSlots(for: [shootingGuard, center])
        XCTAssertEqual(slots.map { $0.player?.season.playerName }, [nil, "Shooting Guard", nil, nil, "Center"])
    }
    func testCurrentTeamSlotsCompleteFivePlayerLineup() {
        let roster = ["PG", "SG", "SF", "PF", "C"].map { position in
            DraftedPlayer(season: SeasonRecord(id: position, playerName: "\(position) Player", season: "S", team: "T", position: position, overallRating: 80), bid: 1)
        }
        XCTAssertEqual(TeamSimulator.currentTeamSlots(for: roster).map { $0.player?.season.playerName }, ["PG Player", "SG Player", "SF Player", "PF Player", "C Player"])
    }
    func testCurrentTeamSlotsAssignAMultiPositionPlayerOnlyOnce() {
        let combo = DraftedPlayer(season: SeasonRecord(id: "combo", playerName: "Combo", season: "S", team: "T", position: "PG-SG", overallRating: 80), bid: 1)
        let shootingGuard = DraftedPlayer(season: SeasonRecord(id: "guard", playerName: "Guard", season: "S", team: "T", position: "SG", overallRating: 80), bid: 1)
        let assignedPlayers = TeamSimulator.currentTeamSlots(for: [combo, shootingGuard]).compactMap(\.player)
        XCTAssertEqual(assignedPlayers.filter { $0.id == combo.id }.count, 1)
        XCTAssertEqual(assignedPlayers.filter { $0.id == shootingGuard.id }.count, 1)
        XCTAssertEqual(assignedPlayers.map(\.season.playerName), ["Combo", "Guard"])
    }
    func testRepositoryProvidesTenDeterministicOffers() async throws {
        let first = try await BundledSeasonRepository.randomTeams(count: 10, seed: 4)
        let second = try await BundledSeasonRepository.randomTeams(count: 10, seed: 4)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }
    func testPlayerSearchUsesStableIDsAndRanksExactFirst() {
        let exact = SeasonRecord(id: "exact-row", playerID: "exact", playerName: "Chris Paul", season: "2024–25", team: "PHX", position: "PG", overallRating: 80)
        let sameName = SeasonRecord(id: "same-name-row", playerID: "same-name", playerName: "Chris Paul", season: "1984–85", team: "LAL", position: "SG", overallRating: 80)
        let prefix = SeasonRecord(id: "prefix-row", playerID: "prefix", playerName: "Chris Pauline", season: "2024–25", team: "PHX", position: "PG", overallRating: 80)
        let database = NBAStatsDatabase(teamSeasons: [TeamSeason(id: "a", team: "PHX", season: "2024–25", players: [exact, prefix]), TeamSeason(id: "b", team: "LAL", season: "1984–85", players: [sameName])])
        XCTAssertEqual(database.searchPlayers("Chris Paul").map(\.id), ["exact", "same-name", "prefix"])
        XCTAssertEqual(database.searchPlayers("Paul").count, 3)
    }
    func testPlayerFiltersIntersectAndFranchiseHistoryKeepsOriginalCodes() {
        let oldNet = SeasonRecord(id: "net", playerID: "player", playerName: "Test Player", season: "2011–12", team: "NJN", position: "PG-SG", overallRating: 80)
        let brooklyn = SeasonRecord(id: "brooklyn", playerID: "player", playerName: "Test Player", season: "2013–14", team: "BRK", position: "PG", overallRating: 80)
        let database = NBAStatsDatabase(teamSeasons: [TeamSeason(id: "nj", team: "NJN", season: "2011–12", players: [oldNet]), TeamSeason(id: "bk", team: "BRK", season: "2013–14", players: [brooklyn])])
        let profile = database.searchPlayers("Test Player")[0]
        XCTAssertEqual(database.teamSeasonsByFranchise["BRK"]?.map(\.team), ["BRK", "NJN"])
        XCTAssertEqual(database.rows(for: profile, season: "2011–12", franchise: "BRK", position: "SG").map(\.id), ["net"])
    }
    func testSeasonLeadersAggregateTradedPlayerAndOrderTopTen() {
        let tradedA = SeasonRecord(id: "trade-a", playerID: "traded", playerName: "Traded Star", season: "2020–21", team: "AAA", position: "PG", games: 20, minutes: 30, points: 20, rebounds: 4, assists: 8, steals: 1, blocks: 0.2, fgPercent: 40, threePercent: 30, ftPercent: 70, overallRating: 80)
        let tradedB = SeasonRecord(id: "trade-b", playerID: "traded", playerName: "Traded Star", season: "2020–21", team: "BBB", position: "PG", games: 40, minutes: 36, points: 30, rebounds: 6, assists: 10, steals: 2, blocks: 0.4, fgPercent: 50, threePercent: 40, ftPercent: 90, overallRating: 80)
        let scorer = SeasonRecord(id: "scorer", playerID: "scorer", playerName: "Scorer", season: "2020–21", team: "CCC", position: "SG", games: 70, points: 25, overallRating: 80)
        let database = NBAStatsDatabase(teamSeasons: [TeamSeason(id: "a", team: "AAA", season: "2020–21", players: [tradedA]), TeamSeason(id: "b", team: "BBB", season: "2020–21", players: [tradedB]), TeamSeason(id: "c", team: "CCC", season: "2020–21", players: [scorer])])
        let leaders = database.leaders(for: .points, season: "2020–21")
        XCTAssertEqual(leaders.map(\.record.playerID), ["traded", "scorer"])
        XCTAssertEqual(leaders[0].record.games, 60)
        XCTAssertEqual(leaders[0].teamLabel, "Multiple Teams")
        XCTAssertEqual(leaders[0].record.points, 80.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(leaders[0].record.minutes, 34, accuracy: 0.0001)
        XCTAssertEqual(leaders[0].record.fgPercent, 140.0 / 3.0, accuracy: 0.0001)
    }
    func testLeadersFilterSeasonAndAllTimeUsesBestSingleSeason() {
        let old = SeasonRecord(id: "old", playerID: "same", playerName: "Same Player", season: "2019–20", team: "AAA", position: "PG", games: 60, points: 31, overallRating: 80)
        let new = SeasonRecord(id: "new", playerID: "same", playerName: "Same Player", season: "2020–21", team: "AAA", position: "PG", games: 60, points: 29, overallRating: 80)
        let current = SeasonRecord(id: "current", playerID: "current", playerName: "Current", season: "2020–21", team: "BBB", position: "SG", games: 70, points: 30, overallRating: 80)
        let database = NBAStatsDatabase(teamSeasons: [TeamSeason(id: "old", team: "AAA", season: "2019–20", players: [old]), TeamSeason(id: "new", team: "AAA", season: "2020–21", players: [new]), TeamSeason(id: "current", team: "BBB", season: "2020–21", players: [current])])
        XCTAssertEqual(database.leaders(for: .points, season: "2020–21").map(\.record.playerName), ["Current", "Same Player"])
        let allTime = database.leaders(for: .points)
        XCTAssertEqual(allTime.first?.record.playerName, "Same Player")
        XCTAssertEqual(allTime.first?.record.season, "2019–20")
    }
    func testLeaderTiesUseGamesThenAlphabeticalName() {
        let alpha = SeasonRecord(id: "alpha", playerID: "alpha", playerName: "Alpha", season: "2020–21", team: "AAA", position: "PG", games: 70, points: 20, overallRating: 80)
        let bravo = SeasonRecord(id: "bravo", playerID: "bravo", playerName: "Bravo", season: "2020–21", team: "BBB", position: "PG", games: 75, points: 20, overallRating: 80)
        let charlie = SeasonRecord(id: "charlie", playerID: "charlie", playerName: "Charlie", season: "2020–21", team: "CCC", position: "PG", games: 70, points: 20, overallRating: 80)
        let database = NBAStatsDatabase(teamSeasons: [TeamSeason(id: "a", team: "AAA", season: "2020–21", players: [alpha]), TeamSeason(id: "b", team: "BBB", season: "2020–21", players: [bravo]), TeamSeason(id: "c", team: "CCC", season: "2020–21", players: [charlie])])
        XCTAssertEqual(database.leaders(for: .points, season: "2020–21").map(\.record.playerName), ["Bravo", "Alpha", "Charlie"])
    }
    func testRateStatLeadersRequireTwentyGamesButGamesLeadersDoNot() {
        let tinySample = SeasonRecord(id: "tiny", playerID: "tiny", playerName: "Tiny Sample", season: "2020–21", team: "AAA", position: "PG", games: 1, points: 50, fgPercent: 100, overallRating: 80)
        let qualified = SeasonRecord(id: "qualified", playerID: "qualified", playerName: "Qualified", season: "2020–21", team: "BBB", position: "PG", games: NBAStatsDatabase.leaderMinimumGames, points: 20, fgPercent: 60, overallRating: 80)
        let database = NBAStatsDatabase(teamSeasons: [TeamSeason(id: "a", team: "AAA", season: "2020–21", players: [tinySample]), TeamSeason(id: "b", team: "BBB", season: "2020–21", players: [qualified])])
        XCTAssertEqual(database.leaders(for: .fgPercent, season: "2020–21").map(\.record.playerName), ["Qualified"])
        XCTAssertEqual(database.leaders(for: .games, season: "2020–21").map(\.record.playerName), ["Qualified", "Tiny Sample"])
    }
    func testFinalRatingTotalDecidesWinner() {
        let strong = SeasonRecord(id: "strong", playerName: "Strong", season: "S", team: "T", position: "PG", points: 30, rebounds: 8, assists: 9, steals: 2, blocks: 1, fgPercent: 50, threePercent: 40, ftPercent: 90, overallRating: 80)
        let weak = SeasonRecord(id: "weak", playerName: "Weak", season: "S", team: "T", position: "PG", points: 5, rebounds: 1, assists: 1, steals: 0.2, blocks: 0.1, fgPercent: 35, threePercent: 25, ftPercent: 60, overallRating: 99)
        XCTAssertEqual(TeamSimulator.winner(player: [DraftedPlayer(season: strong, bid: 1)], opponent: [DraftedPlayer(season: weak, bid: 1)]), "OPPONENT WINS")
    }
    func testFinalRatingIsUnaffectedByLineupStatThresholds() {
        let positions = ["PG", "SG", "SF", "PF", "C"]
        let highStatLineup = positions.enumerated().map { index, position in
            SeasonRecord(id: "high-\(index)", playerName: "High \(index)", season: "S", team: "T", position: position, games: 82, points: 20, rebounds: 8, assists: 6, steals: 2, blocks: 2, fgPercent: 50, threePercent: 40, ftPercent: 90, overallRating: 80)
        }
        let lowStatLineup = positions.enumerated().map { index, position in
            SeasonRecord(id: "low-\(index)", playerName: "Low \(index)", season: "S", team: "T", position: position, games: 82, points: 2, rebounds: 1, assists: 1, steals: 0, blocks: 0, fgPercent: 30, threePercent: 20, ftPercent: 50, overallRating: 80)
        }

        let highBreakdown = TeamSimulator.ratingBreakdown(for: highStatLineup.map { DraftedPlayer(season: $0, bid: 1) })
        let lowBreakdown = TeamSimulator.ratingBreakdown(for: lowStatLineup.map { DraftedPlayer(season: $0, bid: 1) })

        XCTAssertEqual(highBreakdown.positionPenalty, 0)
        XCTAssertEqual(highBreakdown.finalRating, 400)
        XCTAssertEqual(highBreakdown.finalRating, lowBreakdown.finalRating)
    }
    func testNetRatingUsesOnlyPlayerStats() {
        let players = ["PG", "SG", "SF", "PF", "C"].enumerated().map { index, position in
            SeasonRecord(id: "player-\(index)", playerName: "Player \(index)", season: "S", team: "T", position: position, games: 82, points: 20, rebounds: 8, assists: 6, steals: 2, blocks: 2, fgPercent: 50, threePercent: 40, ftPercent: 90, overallRating: 80)
        }.map { DraftedPlayer(season: $0, bid: 1) }

        XCTAssertEqual(TeamSimulator.rating(for: players), TeamNetRating(offense: 121, defense: 100))
    }
    func testBestPossibleLineupUsesOnePlayerFromEveryWonTeamYear() {
        let teams = [
            TeamSeason(id: "a", team: "AAA", season: "S1", players: [SeasonRecord(id: "a-pg", playerName: "A Point", season: "S1", team: "AAA", position: "PG", overallRating: 99), SeasonRecord(id: "a-sg", playerName: "A Guard", season: "S1", team: "AAA", position: "SG", overallRating: 98)]),
            TeamSeason(id: "b", team: "BBB", season: "S1", players: [SeasonRecord(id: "b-sg", playerName: "B Guard", season: "S1", team: "BBB", position: "SG", overallRating: 80)]),
            TeamSeason(id: "c", team: "CCC", season: "S1", players: [SeasonRecord(id: "c-sf", playerName: "C Wing", season: "S1", team: "CCC", position: "SF", overallRating: 80)]),
            TeamSeason(id: "d", team: "DDD", season: "S1", players: [SeasonRecord(id: "d-pf", playerName: "D Forward", season: "S1", team: "DDD", position: "PF", overallRating: 80)]),
            TeamSeason(id: "e", team: "EEE", season: "S1", players: [SeasonRecord(id: "e-c", playerName: "E Center", season: "S1", team: "EEE", position: "C", overallRating: 80)])
        ]
        let lineup = TeamSimulator.bestPossibleLineup(from: teams)
        XCTAssertEqual(Set(lineup.map { player in teams.first { $0.players.contains(player.season) }!.id }), Set(teams.map(\.id)))
        XCTAssertEqual(lineup.count, teams.count)
    }
    func testBestPossibleLineupPrefersHighestRatedValidPositionalCombination() {
        let teams = [
            TeamSeason(id: "pg", team: "PG", season: "S", players: [SeasonRecord(id: "pg", playerName: "Point", season: "S", team: "PG", position: "PG", overallRating: 90)]),
            TeamSeason(id: "sg", team: "SG", season: "S", players: [SeasonRecord(id: "sg-low", playerName: "Guard", season: "S", team: "SG", position: "SG", overallRating: 80), SeasonRecord(id: "sg-high", playerName: "Combo", season: "S", team: "SG", position: "PG", overallRating: 84)]),
            TeamSeason(id: "sf", team: "SF", season: "S", players: [SeasonRecord(id: "sf", playerName: "Wing", season: "S", team: "SF", position: "SF", overallRating: 90)]),
            TeamSeason(id: "pf", team: "PF", season: "S", players: [SeasonRecord(id: "pf", playerName: "Forward", season: "S", team: "PF", position: "PF", overallRating: 90)]),
            TeamSeason(id: "c", team: "C", season: "S", players: [SeasonRecord(id: "c", playerName: "Center", season: "S", team: "C", position: "C", overallRating: 90)])
        ]
        let lineup = TeamSimulator.bestPossibleLineup(from: teams)
        XCTAssertTrue(lineup.contains { $0.season.id == "sg-low" })
        XCTAssertFalse(lineup.contains { $0.season.id == "sg-high" })
        XCTAssertEqual(TeamSimulator.ratingBreakdown(for: lineup).missingPositions, [])
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
