import XCTest
import GameKit
import Combine
@testable import BallKnowledge

final class AuctionEngineTests: XCTestCase {
    func testGameSpecificRankBadgeAssetsStayDistinct() {
        for tier in RankedTier.allCases {
            XCTAssertEqual(tier.badgeAssetName(for: .fiveAlive), "FiveAliveRank\(tier.assetSuffix)")
            XCTAssertEqual(tier.badgeAssetName(for: .boxWars), "BoxWarsRank\(tier.assetSuffix)")
        }
    }

    func testRankTransitionClassification() {
        XCTAssertEqual(RankTransition(result: .init(ratingBefore: 800, ratingAfter: 800, outcome: .draw), game: .fiveAlive).kind, .unchanged)
        XCTAssertEqual(RankTransition(result: .init(ratingBefore: 800, ratingAfter: 840, outcome: .win), game: .fiveAlive).kind, .divisionPromotion)
        XCTAssertEqual(RankTransition(result: .init(ratingBefore: 940, ratingAfter: 960, outcome: .win), game: .boxWars).kind, .tierPromotion)
        XCTAssertEqual(RankTransition(result: .init(ratingBefore: 960, ratingAfter: 940, outcome: .loss), game: .boxWars).kind, .demotion)
    }
    func testEdgeBackSwipeAcceptsRightwardSwipeFromLeftEdge() {
        XCTAssertTrue(EdgeBackSwipe.qualifies(
            startLocation: CGPoint(x: 12, y: 300),
            translation: CGSize(width: 90, height: 20)
        ))
    }

    func testEdgeBackSwipeRejectsInvalidDrags() {
        XCTAssertFalse(EdgeBackSwipe.qualifies(
            startLocation: CGPoint(x: 12, y: 300),
            translation: CGSize(width: 71, height: 0)
        ), "Short drags should not navigate back")
        XCTAssertFalse(EdgeBackSwipe.qualifies(
            startLocation: CGPoint(x: 12, y: 300),
            translation: CGSize(width: 80, height: 70)
        ), "Vertical drags should not navigate back")
        XCTAssertFalse(EdgeBackSwipe.qualifies(
            startLocation: CGPoint(x: 12, y: 300),
            translation: CGSize(width: -90, height: 0)
        ), "Leftward drags should not navigate back")
        XCTAssertFalse(EdgeBackSwipe.qualifies(
            startLocation: CGPoint(x: 25, y: 300),
            translation: CGSize(width: 90, height: 0)
        ), "Non-edge drags should not navigate back")
    }

    func testCurrentTeamCodesResolveToApprovedLogoAssets() {
        let currentTeamCodes = [
            "ATL", "BKN", "BOS", "CHA", "CHI", "CLE", "DAL", "DEN", "DET", "GSW",
            "HOU", "IND", "LAC", "LAL", "MEM", "MIA", "MIL", "MIN", "NYK", "OKC",
            "ORL", "PHI", "PHX", "POR", "SAC", "SAS", "TOR", "UTA", "WAS"
        ]

        for team in currentTeamCodes {
            XCTAssertNotNil(OfflineVisualCatalog.teamLogoName(team: team, season: "2020-21"), "Missing logo for \(team)")
        }
    }

    func testGridDuelNeverPlacesEraCluesOnBothAxes() {
        let records = [
            SeasonRecord(id: "alpha-2000", playerName: "Alpha", season: "2000-01", team: "LAL", position: "PG", overallRating: 80),
            SeasonRecord(id: "alpha-2010", playerName: "Alpha", season: "2010-11", team: "LAL", position: "PG", overallRating: 80),
            SeasonRecord(id: "beta-2000", playerName: "Beta", season: "2000-01", team: "BOS", position: "SF", overallRating: 80),
            SeasonRecord(id: "beta-2010", playerName: "Beta", season: "2010-11", team: "BOS", position: "SF", overallRating: 80)
        ]

        for seed in 0..<100 {
            guard let grid = GridDuelEngine.generate(from: records, seed: UInt64(seed)) else { continue }
            let rowsHaveEra = grid.rows.contains { if case .decade = $0 { true } else { false } }
            let columnsHaveEra = grid.columns.contains { if case .decade = $0 { true } else { false } }
            XCTAssertFalse(rowsHaveEra && columnsHaveEra, "Seed \(seed) placed era clues on both axes")
        }
    }

    func testGridDuelTeamClueEligibilityExcludesHistoricalLogoConflictFranchises() {
        let excluded: Set<String> = ["BKN", "CHA", "NOP", "OKC", "MEM", "SAC", "LAC", "WAS"]

        XCTAssertEqual(GridDuelEngine.excludedTeamClueFranchiseCodes, excluded)
        for franchise in excluded {
            XCTAssertFalse(GridDuelEngine.isEligibleTeamClue(for: franchise), "\(franchise) should not be a Box Wars team clue")
        }
        XCTAssertTrue(GridDuelEngine.isEligibleTeamClue(for: "PHX"))
    }

    func testGridDuelGeneratedBoardsExcludeHistoricalLogoConflictTeamClues() {
        let excluded = ["BKN", "CHA", "NOP", "OKC", "MEM", "SAC", "LAC", "WAS"]
        let teams = excluded + ["LAL", "BOS"]
        let records = teams.flatMap { team in
            [
                SeasonRecord(id: "\(team)-guard", playerName: "\(team) Guard", season: "2020-21", team: team, position: "PG", overallRating: 80),
                SeasonRecord(id: "\(team)-forward", playerName: "\(team) Forward", season: "2020-21", team: team, position: "PF", overallRating: 80)
            ]
        }
        let boards = (0..<100).compactMap { GridDuelEngine.generate(from: records, seed: UInt64($0)) }

        XCTAssertFalse(boards.isEmpty)
        for board in boards {
            XCTAssertTrue(board.cells.allSatisfy { $0.eligibleAnswerCount > 0 })
            for predicate in board.rows + board.columns {
                if case let .team(franchise) = predicate {
                    XCTAssertFalse(GridDuelEngine.excludedTeamClueFranchiseCodes.contains(franchise), "Generated excluded team clue \(franchise)")
                }
            }
        }
    }

    @MainActor
    func testGridDuelSelectingAnotherSquareKeepsTheNewSelection() async {
        let model = GridDuelViewModel(mode: .versusAI)
        await model.start()

        guard let first = model.engine?.grid.cells.first,
              let second = model.engine?.grid.cells.dropFirst().first else {
            return XCTFail("Expected a playable grid")
        }

        model.select(cell: first)
        XCTAssertEqual(model.selectedCellID, first.id)

        model.select(cell: second)
        XCTAssertEqual(model.selectedCellID, second.id)
    }

    @MainActor
    func testGridDuelRankedForfeitRecordsOnlyOneLoss() {
        let suiteName = "GridDuelLadderServiceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let ladder = GridDuelLadderService(defaults: defaults)
        let first = ladder.recordCompletedMatch(id: "grid-duel-test-forfeit", didWin: false)
        let second = ladder.recordCompletedMatch(id: "grid-duel-test-forfeit", didWin: false)

        XCTAssertEqual(first?.didWin, false)
        XCTAssertNil(second)
        XCTAssertEqual(ladder.rating, first?.ratingAfter)
    }

    @MainActor
    func testGridDuelRankedDrawKeepsRatingAndIsIdempotent() {
        let suiteName = "GridDuelLadderDrawTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let ladder = GridDuelLadderService(defaults: defaults)
        let first = ladder.recordCompletedMatch(id: "grid-duel-test-draw", outcome: .draw)
        let second = ladder.recordCompletedMatch(id: "grid-duel-test-draw", outcome: .draw)

        XCTAssertEqual(first?.outcome, .draw)
        XCTAssertTrue(first?.isDraw == true)
        XCTAssertEqual(first?.delta, 0)
        XCTAssertEqual(ladder.rating, GridDuelLadder.initialRating)
        XCTAssertNil(second)
    }

    @MainActor
    func testGridDuelPersistsLatestMMRForGameCenterSubmission() {
        let suiteName = "GridDuelLadderSubmissionTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let result = GridDuelLadderService(defaults: defaults).recordCompletedMatch(id: "grid-submission", didWin: true)

        XCTAssertEqual(defaults.object(forKey: "gridduel.monthly.pendingSubmissionScore") as? Int, result?.ratingAfter)
    }

    @MainActor
    func testGridDuelRepairsLegacyZeroEvenWhenMigrationMarkerIsCurrent() {
        let suiteName = "GridDuelLegacyZeroTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return XCTFail("Could not create isolated defaults") }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let date = Date(timeIntervalSince1970: 1_784_358_400)
        defaults.set(0, forKey: "gridduel.monthly.rating")
        defaults.set("box-wars-781-v2", forKey: "gridduel.monthly.baselineVersion")
        defaults.set("2026-07", forKey: "gridduel.monthly.season")

        let ladder = GridDuelLadderService(defaults: defaults, now: { date })

        XCTAssertEqual(ladder.rating, 781)
        XCTAssertEqual(ladder.pendingSubmissionScore, 781)
        XCTAssertEqual(ladder.leaderboardSubmissionStatus, .pending(score: 781))
    }

    @MainActor
    func testGridDuelPreservesLegitimatelyEarnedZeroRating() {
        let suiteName = "GridDuelEarnedZeroTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return XCTFail("Could not create isolated defaults") }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let date = Date(timeIntervalSince1970: 1_784_358_400)
        defaults.set(0, forKey: "gridduel.monthly.rating")
        defaults.set(date, forKey: "gridduel.monthly.lastLocalMutation")
        defaults.set("box-wars-781-v2", forKey: "gridduel.monthly.baselineVersion")
        defaults.set("2026-07", forKey: "gridduel.monthly.season")

        let ladder = GridDuelLadderService(defaults: defaults, now: { date })

        XCTAssertEqual(ladder.rating, 0)
        XCTAssertNil(ladder.pendingSubmissionScore)
    }

    func testGridDuelEqualAggregateScoreIsAlwaysADraw() {
        let records = [
            SeasonRecord(id: "alpha", playerName: "Alpha", season: "S", team: "AAA", position: "PG", games: 20, points: 25, overallRating: 80),
            SeasonRecord(id: "beta", playerName: "Beta", season: "S", team: "AAA", position: "PG", games: 20, points: 25, overallRating: 80),
            SeasonRecord(id: "gamma", playerName: "Gamma", season: "S", team: "AAA", position: "PG", games: 20, points: 25, overallRating: 80),
            SeasonRecord(id: "delta", playerName: "Delta", season: "S", team: "AAA", position: "PG", games: 20, points: 25, overallRating: 80)
        ]
        let grid = GridDuelGrid(rows: [.team("AAA"), .position("PG")], columns: [.position("PG"), .team("AAA")], archiveRows: records)
        var engine = GridDuelEngine(grid: grid, archiveRows: records)
        XCTAssertTrue(engine.submit(records[0], to: "0-0", forLocalPlayer: true, at: Date(timeIntervalSince1970: 50)))
        XCTAssertTrue(engine.submit(records[1], to: "0-1", forLocalPlayer: true, at: Date(timeIntervalSince1970: 60)))
        XCTAssertTrue(engine.submit(records[2], to: "1-0", forLocalPlayer: false, at: Date(timeIntervalSince1970: 1)))
        XCTAssertTrue(engine.submit(records[3], to: "1-1", forLocalPlayer: false, at: Date(timeIntervalSince1970: 2)))

        let result = engine.resolve()
        XCTAssertEqual(result.localScore, result.opponentScore)
        XCTAssertEqual(result.winner, .draw)
    }

    func testGridDuelContestedSquareAwardsBothPlayersTheirRarityPoints() {
        let uncommon = SeasonRecord(id: "uncommon", playerName: "Uncommon", season: "S", team: "AAA", position: "PG", games: 20, points: 20, rebounds: 0, assists: 0, steals: 0, blocks: 0, overallRating: 80)
        let rare = SeasonRecord(id: "rare", playerName: "Rare", season: "S", team: "AAA", position: "PG", games: 20, points: 15, rebounds: 0, assists: 0, steals: 0, blocks: 0, overallRating: 80)
        let records = [uncommon, rare]
        let grid = GridDuelGrid(rows: [.team("AAA"), .position("PG")], columns: [.position("PG"), .team("AAA")], archiveRows: records)
        var engine = GridDuelEngine(grid: grid, archiveRows: records)

        XCTAssertTrue(engine.submit(uncommon, to: "0-0", forLocalPlayer: true))
        XCTAssertTrue(engine.submit(rare, to: "0-0", forLocalPlayer: false))

        let result = engine.resolve()
        XCTAssertEqual(result.cells[0].localPoints, 2)
        XCTAssertEqual(result.cells[0].opponentPoints, 3)
        XCTAssertEqual(result.localScore, 2)
        XCTAssertEqual(result.opponentScore, 3)
        XCTAssertEqual(result.winner, .opponent)
    }

    func testGridDuelCareerWideEligibilityAndAnswerReplacement() {
        let records = [
            SeasonRecord(id: "lebron-lal", playerName: "LeBron James", season: "2020-21", team: "LAL", position: "SF", overallRating: 80),
            SeasonRecord(id: "alpha-lal", playerName: "Alpha", season: "2020-21", team: "LAL", position: "PG", overallRating: 80),
            SeasonRecord(id: "alpha-sac", playerName: "Alpha", season: "2021-22", team: "SAC", position: "PG", overallRating: 80),
            SeasonRecord(id: "beta-sac", playerName: "Beta", season: "2021-22", team: "SAC", position: "PG", overallRating: 80)
        ]
        let grid = GridDuelGrid(rows: [.teammateOf("LeBron James"), .team("SAC")], columns: [.team("SAC"), .position("PG")], archiveRows: records)
        var engine = GridDuelEngine(grid: grid, archiveRows: records)
        XCTAssertTrue(grid.cell(row: 0, column: 0).eligiblePlayerIDs.contains("alpha"))
        XCTAssertFalse(grid.cell(row: 0, column: 0).eligiblePlayerIDs.contains("lebronjames"))
        XCTAssertFalse(engine.submit(records[3], to: "0-0", forLocalPlayer: true))
        XCTAssertTrue(engine.submit(records[1], to: "0-0", forLocalPlayer: true, at: Date(timeIntervalSince1970: 10)))
        XCTAssertTrue(engine.submit(records[2], to: "0-0", forLocalPlayer: true, at: Date(timeIntervalSince1970: 11)))
        XCTAssertEqual(engine.localAnswers["0-0"]?.playerName, "Alpha")
    }

    func testGridDuelCareerRangeUsesStartAndEndYearsForMultiSeasonCareer() {
        let records = [
            SeasonRecord(id: "alpha-2011", playerName: "Alpha", season: "2011-2012", team: "LAL", position: "PG", overallRating: 80),
            SeasonRecord(id: "alpha-2020", playerName: "Alpha", season: "2020-2021", team: "LAL", position: "PG", overallRating: 80)
        ]
        let grid = GridDuelGrid(rows: [.team("LAL"), .position("PG")], columns: [.position("PG"), .team("LAL")], archiveRows: records)
        let engine = GridDuelEngine(grid: grid, archiveRows: records)

        XCTAssertEqual(engine.careerRange(for: records[0]), "2011 – 2021")
    }

    func testGridDuelCareerRangeExpandsAbbreviatedCurrentSeasonEndYear() {
        let records = [
            SeasonRecord(id: "alpha-2024", playerName: "Alpha", season: "2024-25", team: "LAL", position: "PG", overallRating: 80),
            SeasonRecord(id: "alpha-2025", playerName: "Alpha", season: "2025-26", team: "LAL", position: "PG", overallRating: 80)
        ]
        let grid = GridDuelGrid(rows: [.team("LAL"), .position("PG")], columns: [.position("PG"), .team("LAL")], archiveRows: records)
        let engine = GridDuelEngine(grid: grid, archiveRows: records)

        XCTAssertEqual(engine.careerRange(for: records[0]), "2024 – 2026")
    }

    func testGridDuelCareerRangeCachesMixedSeasonFormats() {
        let records = [
            SeasonRecord(id: "alpha-2019", playerName: "Alpha", season: "2019-20", team: "LAL", position: "PG", overallRating: 80),
            SeasonRecord(id: "alpha-2024", playerName: "Alpha", season: "2024-2025", team: "LAL", position: "PG", overallRating: 80)
        ]
        let grid = GridDuelGrid(rows: [.team("LAL"), .position("PG")], columns: [.position("PG"), .team("LAL")], archiveRows: records)
        let engine = GridDuelEngine(grid: grid, archiveRows: records)

        XCTAssertEqual(engine.careerRange(for: records[0]), "2019 – 2025")
    }

    func testGridDuelCareerRangePreservesSingleSeasonDisplay() {
        let record = SeasonRecord(id: "alpha-2011", playerName: "Alpha", season: "2011-2012", team: "LAL", position: "PG", overallRating: 80)
        let grid = GridDuelGrid(rows: [.team("LAL"), .position("PG")], columns: [.position("PG"), .team("LAL")], archiveRows: [record])
        let engine = GridDuelEngine(grid: grid, archiveRows: [record])

        XCTAssertEqual(engine.careerRange(for: record), "2011-2012")
    }

    func testGridDuelDecadeLabelAndTeamIntersectionRequireTheSameSeason() {
        let records = [
            SeasonRecord(id: "alpha-2003-lal", playerID: "alpha01", playerName: "Alpha", season: "2003–04", team: "LAL", position: "PG", overallRating: 80),
            SeasonRecord(id: "alpha-2013-bos", playerID: "alpha01", playerName: "Alpha", season: "2013–14", team: "BOS", position: "PG", overallRating: 80),
            SeasonRecord(id: "beta-2013-lal", playerID: "beta01", playerName: "Beta", season: "2013–14", team: "LAL", position: "PG", overallRating: 80)
        ]
        let grid = GridDuelGrid(rows: [.decade(2000), .decade(2010)], columns: [.team("LAL"), .team("BOS")], archiveRows: records)

        XCTAssertEqual(GridPredicate.decade(2000).label, "2000s")
        XCTAssertEqual(grid.cell(row: 0, column: 0).eligiblePlayerIDs, ["alpha"])
        XCTAssertTrue(grid.cell(row: 0, column: 1).eligiblePlayerIDs.isEmpty) // Alpha's BOS season is not in the 2000s.
        XCTAssertEqual(grid.cell(row: 1, column: 0).eligiblePlayerIDs, ["beta"])
        XCTAssertEqual(grid.cell(row: 1, column: 1).eligiblePlayerIDs, ["alpha"])
    }

    func testGridDuelGeneratedTeammateClueRetainsArchivePortraitIdentity() {
        let records = [
            SeasonRecord(id: "lebron-2012", playerID: "jamesle01", playerName: "LeBron James", season: "2012–13", team: "MIA", position: "SF", overallRating: 80),
            SeasonRecord(id: "wade-2012", playerID: "wadedw01", playerName: "Dwyane Wade", season: "2012–13", team: "MIA", position: "SG", overallRating: 80)
        ]
        let index = GridCareerEligibilityIndex(archiveRows: records)
        guard let clue = index.availableTeammateClues.first(where: { $0.playerName == "LeBron James" }) else {
            return XCTFail("Expected LeBron teammate clue")
        }

        XCTAssertEqual(clue.playerID, "jamesle01")
        XCTAssertEqual(OfflineVisualCatalog.portraitAssetName(for: clue.playerID), "player_jamesle01")
    }

    func testGridDuelGenerationCanPublishAnswerableDecadeClues() {
        let records = [
            SeasonRecord(id: "alpha", playerName: "Alpha", season: "1999–00", team: "LAL", position: "PG", overallRating: 80),
            SeasonRecord(id: "beta", playerName: "Beta", season: "2003–04", team: "LAL", position: "SF", overallRating: 80),
            SeasonRecord(id: "gamma", playerName: "Gamma", season: "2013–14", team: "LAL", position: "PG", overallRating: 80)
        ]
        let boards = (0..<100).compactMap { GridDuelEngine.generate(from: records, seed: UInt64($0)) }

        XCTAssertTrue(boards.allSatisfy { $0.cells.allSatisfy { $0.eligibleAnswerCount > 0 } })
        XCTAssertTrue(boards.contains { ($0.rows + $0.columns).contains { if case .decade = $0 { true } else { false } } })
    }

    func testGridDuelBroadPositionCluesAcceptTheirHistoricalGroups() {
        let records = [
            SeasonRecord(id: "point", playerName: "Point", season: "S", team: "AAA", position: "PG", overallRating: 80),
            SeasonRecord(id: "shooting", playerName: "Shooting", season: "S", team: "AAA", position: "SG", overallRating: 80),
            SeasonRecord(id: "wing", playerName: "Wing", season: "S", team: "AAA", position: "SF", overallRating: 80),
            SeasonRecord(id: "forward", playerName: "Forward", season: "S", team: "AAA", position: "PF", overallRating: 80),
            SeasonRecord(id: "center", playerName: "Center", season: "S", team: "AAA", position: "C", overallRating: 80),
            SeasonRecord(id: "combo", playerName: "Combo", season: "S", team: "AAA", position: "PG-SF", overallRating: 80)
        ]
        let grid = GridDuelGrid(rows: [.position("G"), .position("F/C")], columns: [.team("AAA"), .team("AAA")], archiveRows: records)

        let guards = grid.cell(row: 0, column: 0).eligiblePlayerIDs
        XCTAssertTrue(guards.isSuperset(of: ["point", "shooting", "combo"]))
        XCTAssertFalse(guards.contains("wing"))
        XCTAssertFalse(guards.contains("forward"))
        XCTAssertFalse(guards.contains("center"))

        let frontcourt = grid.cell(row: 1, column: 0).eligiblePlayerIDs
        XCTAssertTrue(frontcourt.isSuperset(of: ["wing", "forward", "center", "combo"]))
        XCTAssertFalse(frontcourt.contains("point"))
        XCTAssertFalse(frontcourt.contains("shooting"))
    }

    func testGridDuelExactPositionCluesRemainCompatible() {
        let records = [
            SeasonRecord(id: "point", playerName: "Point", season: "S", team: "AAA", position: "PG", overallRating: 80),
            SeasonRecord(id: "shooting", playerName: "Shooting", season: "S", team: "AAA", position: "SG", overallRating: 80),
            SeasonRecord(id: "combo", playerName: "Combo", season: "S", team: "AAA", position: "PG-SF", overallRating: 80)
        ]
        let grid = GridDuelGrid(rows: [.position("PG"), .position("SF")], columns: [.team("AAA"), .team("AAA")], archiveRows: records)

        XCTAssertEqual(grid.cell(row: 0, column: 0).eligiblePlayerIDs, ["point", "combo"])
        XCTAssertEqual(grid.cell(row: 1, column: 0).eligiblePlayerIDs, ["combo"])
    }

    func testGridDuelGlobalSearchCanShowAnIneligiblePlayerButSubmissionRejectsIt() {
        let records = [
            SeasonRecord(id: "lebron-lal", playerName: "LeBron James", season: "2020-21", team: "LAL", position: "SF", overallRating: 80),
            SeasonRecord(id: "wizards-center", playerName: "Wizards Center", season: "2020-21", team: "WAS", position: "C", overallRating: 80),
            SeasonRecord(id: "wizards-guard", playerName: "Wizards Guard", season: "2020-21", team: "WAS", position: "PG", overallRating: 80)
        ]
        let grid = GridDuelGrid(rows: [.team("WAS"), .position("PG")], columns: [.position("C"), .team("WAS")], archiveRows: records)
        var engine = GridDuelEngine(grid: grid, archiveRows: records)

        XCTAssertEqual(engine.searchRecords(query: "lebron").map(\.playerName), ["LeBron James"])
        XCTAssertFalse(engine.submit(records[0], to: "0-0", forLocalPlayer: true))
        XCTAssertNil(engine.localAnswers["0-0"])
        XCTAssertTrue(engine.submit(records[1], to: "0-0", forLocalPlayer: true))
    }

    func testGridDuelGlobalSearchIsAlphabeticalAndLimitedToThirtyResults() {
        let records = (0..<35).map { index in
            SeasonRecord(
                id: "match-\(index)",
                playerName: String(format: "Match %02d", 34 - index),
                season: "2020-21",
                team: "LAL",
                position: "PG",
                overallRating: 80
            )
        }
        let grid = GridDuelGrid(rows: [.team("LAL"), .position("PG")], columns: [.position("PG"), .team("LAL")], archiveRows: records)
        let engine = GridDuelEngine(grid: grid, archiveRows: records)

        let matches = engine.searchRecords(query: "MATCH")
        XCTAssertEqual(matches.count, 30)
        XCTAssertEqual(matches.map(\.playerName), (0..<30).map { String(format: "Match %02d", $0) })
    }

    func testGridDuelRarityUsesPeakTwentyGameSeasonThresholds() {
        func rarity(points: Double, games: Int = 20) -> GridRarityTier {
            let record = SeasonRecord(id: "player-\(points)-\(games)", playerName: "Player \(points)", season: "2020-21", team: "LAL", position: "PG", games: games, points: points, rebounds: 0, assists: 0, steals: 0, blocks: 0, overallRating: 80)
            let grid = GridDuelGrid(rows: [.team("LAL"), .position("PG")], columns: [.position("PG"), .team("LAL")], archiveRows: [record])
            var engine = GridDuelEngine(grid: grid, archiveRows: [record])
            XCTAssertTrue(engine.submit(record, to: "0-0", forLocalPlayer: true))
            return engine.rarity(for: engine.localAnswers["0-0"])!
        }
        XCTAssertEqual(rarity(points: 5.4), .mythic)
        XCTAssertEqual(rarity(points: 5.5), .legendary)
        XCTAssertEqual(rarity(points: 9.3), .rare)
        XCTAssertEqual(rarity(points: 16.1), .uncommon)
        XCTAssertEqual(rarity(points: 24.6), .common)
        XCTAssertEqual(rarity(points: 30), .common) // Harden-equivalent
        XCTAssertEqual(rarity(points: 33), .common) // Curry-equivalent
        XCTAssertEqual(rarity(points: 40, games: 19), .mythic)
    }

    func testGridDuelRarityUsesPeakCareerSeasonRatherThanSubmittedSeason() {
        let records = [
            SeasonRecord(id: "alpha-high", playerName: "Alpha", season: "2020-21", team: "LAL", position: "PG", games: 60, points: 31, rebounds: 6, assists: 7, steals: 1, blocks: 0, overallRating: 80),
            SeasonRecord(id: "alpha-low", playerName: "Alpha", season: "2021-22", team: "SAC", position: "PG", games: 22, points: 11, rebounds: 2, assists: 2, steals: 0, blocks: 0, overallRating: 80)
        ]
        let grid = GridDuelGrid(rows: [.team("SAC"), .position("PG")], columns: [.position("PG"), .team("SAC")], archiveRows: records)
        var engine = GridDuelEngine(grid: grid, archiveRows: records)
        XCTAssertTrue(engine.submit(records[1], to: "0-0", forLocalPlayer: true))
        XCTAssertEqual(engine.rarity(for: engine.localAnswers["0-0"]), .common)
    }

    func testGridDuelBestGridUsesHighestRarityAndAlphabeticalTies() {
        let records = [
            SeasonRecord(id: "zeta", playerName: "Zeta", season: "2020-21", team: "LAL", position: "PG", games: 40, points: 5, rebounds: 0, assists: 0, steals: 0, blocks: 0, overallRating: 80),
            SeasonRecord(id: "alpha", playerName: "Alpha", season: "2020-21", team: "LAL", position: "PG", games: 40, points: 5, rebounds: 0, assists: 0, steals: 0, blocks: 0, overallRating: 80),
            SeasonRecord(id: "beta", playerName: "Beta", season: "2020-21", team: "LAL", position: "PG", games: 40, points: 6, rebounds: 0, assists: 0, steals: 0, blocks: 0, overallRating: 80)
        ]
        let grid = GridDuelGrid(rows: [.team("LAL"), .position("PG")], columns: [.position("PG"), .team("LAL")], archiveRows: records)
        let engine = GridDuelEngine(grid: grid, archiveRows: records)

        XCTAssertEqual(engine.bestValidAnswers().count, 4)
        XCTAssertEqual(engine.bestValidAnswer(for: grid.cell(row: 0, column: 0))?.playerName, "Alpha")
        XCTAssertEqual(engine.bestValidAnswer(for: grid.cell(row: 0, column: 0))?.points, 5)
    }

    func testGridDuelGenerationOnlyPublishesAnswerableCells() {
        let rows = [
            SeasonRecord(id: "a", playerName: "Alpha", season: "2020-21", team: "LAL", position: "PG", points: 21, rebounds: 9, assists: 8, overallRating: 80),
            SeasonRecord(id: "b", playerName: "Beta", season: "2021-22", team: "BOS", position: "SG", points: 20, rebounds: 8, assists: 7, overallRating: 80),
            SeasonRecord(id: "c", playerName: "Gamma", season: "2022-23", team: "MIA", position: "SF", points: 19, rebounds: 8, assists: 7, overallRating: 80)
        ]
        // A sparse archive may not yield a board; a yielded board must never
        // contain a dead cell.
        if let grid = GridDuelEngine.generate(from: rows, seed: 42) {
            XCTAssertEqual(grid.rows.count, 2)
            XCTAssertEqual(grid.columns.count, 2)
            XCTAssertEqual(grid.cells.count, 4)
            XCTAssertTrue(grid.cells.allSatisfy { $0.eligibleAnswerCount > 0 })
            XCTAssertEqual(Set(grid.rows + grid.columns).count, 4)
            for predicate in grid.rows + grid.columns {
                switch predicate {
                case .position(let value): XCTAssertTrue(["G", "F/C"].contains(value))
                case .team, .teammateOf, .decade: break
                }
            }
        }
    }
    func testRankedDifficultyCannotInheritPracticeOrFriendScoutingLevel() {
        XCTAssertEqual(RankedMatchSetup.difficulty(afterSelecting: .easy), .ballKnowledge)
        XCTAssertEqual(RankedMatchSetup.difficulty(afterSelecting: .medium), .ballKnowledge)
    }

    func testRankedSearchStagesExpandAtTenSecondBoundaries() {
        XCTAssertEqual(RankedSearchStage.forElapsedSeconds(0), .closeMatch)
        XCTAssertEqual(RankedSearchStage.forElapsedSeconds(9), .closeMatch)
        XCTAssertEqual(RankedSearchStage.forElapsedSeconds(10), .expanded)
        XCTAssertEqual(RankedSearchStage.forElapsedSeconds(19), .expanded)
        XCTAssertEqual(RankedSearchStage.forElapsedSeconds(20), .wide)
        XCTAssertEqual(RankedSearchStage.forElapsedSeconds(29), .wide)
        XCTAssertEqual(RankedSearchStage.duration, 30)
    }

    func testRankedSearchStagesUseSpecifiedFairMatchRanges() {
        XCTAssertEqual(RankedSearchStage.closeMatch.acceptedMMRRange, 100)
        XCTAssertEqual(RankedSearchStage.expanded.acceptedMMRRange, 250)
        XCTAssertEqual(RankedSearchStage.wide.acceptedMMRRange, 500)
    }

    func testRankedSearchCopyUsesPlainLanguage() {
        XCTAssertEqual(RankedSearchStage.closeMatch.playerMessage, "Looking for a player close to your skill level…")
        XCTAssertTrue(RankedSearchStage.expanded.playerMessage.contains("fair match"))
        XCTAssertTrue(RankedSearchStage.wide.playerMessage.contains("wider range"))
    }

    func testRankedEloStartsAtSilverEntryBaselineAndAwardsNineteenForAWinAgainstTheDefaultOpponent() {
        XCTAssertEqual(RankedLadder.initialRating, 781)
        XCTAssertEqual(RankedLadder.rating(afterWin: true, rating: RankedLadder.initialRating), 800)
        XCTAssertEqual(RankedLadder.rating(afterWin: false, rating: RankedLadder.initialRating), 776)
    }

    @MainActor
    func testFiveAliveFreshLadderStartsBronzeAtSeasonBaseline() {
        let suiteName = "RankedLadderFreshTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return XCTFail("Could not create isolated defaults") }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let ladder = RankedLadderService(defaults: defaults, now: { Date(timeIntervalSince1970: 1_784_358_400) })
        XCTAssertEqual(ladder.rating, 781)
        XCTAssertEqual(ladder.tier, .bronze)
    }

    @MainActor
    func testFiveAliveReleaseMigrationResetsExistingRatingAndMatchJournal() {
        let suiteName = "RankedLadderMigrationTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return XCTFail("Could not create isolated defaults") }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(1_200, forKey: "ranked.monthly.rating")
        defaults.set(["old-match"], forKey: "ranked.monthly.submittedMatchIDs")

        let ladder = RankedLadderService(defaults: defaults, now: { Date(timeIntervalSince1970: 1_784_358_400) })
        XCTAssertEqual(ladder.rating, 781)
        XCTAssertNil(defaults.stringArray(forKey: "ranked.monthly.submittedMatchIDs"))
        XCTAssertEqual(ladder.recordCompletedMatch(id: "old-match", didWin: true)?.ratingAfter, 800)
    }

    @MainActor
    func testFiveAliveNewUTCMonthResetsRatingAndJournal() {
        let suiteName = "RankedLadderSeasonTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return XCTFail("Could not create isolated defaults") }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var date = Date(timeIntervalSince1970: 1_784_358_400)
        let ladder = RankedLadderService(defaults: defaults, now: { date })
        XCTAssertNotNil(ladder.recordCompletedMatch(id: "match", didWin: true))
        XCTAssertEqual(ladder.rating, 800)

        date = Date(timeIntervalSince1970: 1_787_036_800)
        XCTAssertEqual(ladder.rating, 781)
        XCTAssertEqual(ladder.recordCompletedMatch(id: "match", didWin: true)?.ratingAfter, 800)
    }

    @MainActor
    func testFiveAliveRepeatedSameSeasonAccessPreservesRatingAndJournal() {
        let suiteName = "RankedLadderSameSeasonTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return XCTFail("Could not create isolated defaults") }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let date = Date(timeIntervalSince1970: 1_784_358_400)
        let first = RankedLadderService(defaults: defaults, now: { date })
        XCTAssertEqual(first.recordCompletedMatch(id: "match", didWin: true)?.ratingAfter, 800)

        let second = RankedLadderService(defaults: defaults, now: { date })
        XCTAssertEqual(second.rating, 800)
        XCTAssertNil(second.recordCompletedMatch(id: "match", didWin: true))
    }

    @MainActor
    func testFiveAlivePersistsLatestMMRForGameCenterSubmission() {
        let suiteName = "RankedLadderSubmissionTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return XCTFail("Could not create isolated defaults") }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let result = RankedLadderService(defaults: defaults).recordCompletedMatch(id: "five-submission", didWin: true)

        XCTAssertEqual(defaults.object(forKey: "ranked.monthly.pendingSubmissionScore") as? Int, result?.ratingAfter)
    }

    @MainActor
    func testFiveAliveForfeitQueuesLatestLowerMMRForLeaderboardSubmission() {
        let suiteName = "RankedLadderForfeitSubmissionTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return XCTFail("Could not create isolated defaults") }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let ladder = RankedLadderService(defaults: defaults)
        let result = ladder.recordCompletedMatch(id: "five-forfeit", didWin: false)

        XCTAssertEqual(result?.ratingAfter, 776)
        XCTAssertEqual(ladder.rating, 776)
        XCTAssertEqual(ladder.pendingSubmissionScore, 776)
        XCTAssertEqual(ladder.leaderboardSubmissionStatus, .pending(score: 776))
    }

    @MainActor
    func testFiveAliveLeaderboardSubmissionAcknowledgementFailureAndRetry() async {
        let suiteName = "RankedLadderSubmissionRetryTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return XCTFail("Could not create isolated defaults") }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var callbacks: [(Error?) -> Void] = []
        var submittedScores: [Int] = []
        let ladder = RankedLadderService(
            defaults: defaults,
            isGameCenterAuthenticated: { true },
            submitScore: { score, completion in
                submittedScores.append(score)
                callbacks.append(completion)
            }
        )

        XCTAssertEqual(ladder.recordCompletedMatch(id: "five-submission-retry", didWin: false)?.ratingAfter, 776)
        XCTAssertEqual(submittedScores, [776])
        callbacks.removeFirst()(NSError(domain: "GameCenterTests", code: 7))
        await Task.yield()
        XCTAssertEqual(ladder.pendingSubmissionScore, 776)
        guard case let .failed(score, message) = ladder.leaderboardSubmissionStatus else {
            return XCTFail("Expected a visible leaderboard submission failure")
        }
        XCTAssertEqual(score, 776)
        XCTAssertFalse(message.isEmpty)

        ladder.retryPendingLeaderboardSubmission()
        XCTAssertEqual(submittedScores, [776, 776])
        callbacks.removeFirst()(nil)
        await Task.yield()
        XCTAssertNil(ladder.pendingSubmissionScore)
        XCTAssertEqual(ladder.leaderboardSubmissionStatus, .synced)
    }

    @MainActor
    func testGridDuelBaselineMatchesFiveAlive() {
        let suiteName = "GridDuelBaselineTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return XCTFail("Could not create isolated defaults") }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let ladder = GridDuelLadderService(defaults: defaults)
        XCTAssertEqual(ladder.rating, 781)
        XCTAssertEqual(ladder.recordCompletedMatch(id: "match", didWin: true)?.ratingAfter, 800)
    }

    func testBoxWarsRankedAIProfilesIncreaseCoverageAndAnswerStrength() {
        let expected: [(RankedTier, Int, Int)] = [
            (.bronze, 1, 1), (.silver, 2, 2), (.gold, 3, 3),
            (.platinum, 4, 4), (.goat, 4, 5)
        ]

        for (tier, filledCellCount, maximumAnswerPoints) in expected {
            let profile = tier.boxWarsAIProfile
            XCTAssertEqual(profile.filledCellCount, filledCellCount, "\(tier) coverage")
            XCTAssertEqual(profile.maximumAnswerPoints, maximumAnswerPoints, "\(tier) point ceiling")
        }
    }

    func testBoxWarsBronzeAIUsesTheWeakestValidAnswer() {
        let engine = boxWarsDifficultyEngine()
        let answers = engine.rankedAIAnswers(profile: RankedTier.bronze.boxWarsAIProfile)
        XCTAssertEqual(answers.count, 1)
        XCTAssertEqual(answers.first?.answer.playerName, "One Point")
    }

    func testBoxWarsRankedAIAnswersNeverRegressAcrossTiersAndGOATUsesBest() {
        let engine = boxWarsDifficultyEngine()
        let cell = engine.grid.cells[0]
        let selectedPoints = RankedTier.allCases.map { tier -> Int in
            let answer = engine.rankedAIAnswer(for: cell, profile: tier.boxWarsAIProfile)
            XCTAssertNotNil(answer)
            let gridAnswer = GridAnswer(playerID: GridCareerEligibilityIndex.playerID(for: answer!), playerName: answer!.playerName, recordID: answer!.id, submittedAt: .distantPast)
            return engine.rarity(for: gridAnswer)!.points
        }

        XCTAssertEqual(selectedPoints, [1, 2, 3, 4, 5])
        XCTAssertEqual(engine.rankedAIAnswer(for: cell, profile: RankedTier.goat.boxWarsAIProfile)?.playerName, "Five Points")
    }

    private func boxWarsDifficultyEngine() -> GridDuelEngine {
        let records = [
            ("One Point", 25.0), ("Two Points", 17.0), ("Three Points", 10.0),
            ("Four Points", 7.0), ("Five Points", 5.0)
        ].enumerated().map { index, value in
            SeasonRecord(id: "difficulty-\(index)", playerName: value.0, season: "2020-21", team: "LAL", position: "PG", games: 40, points: value.1, rebounds: 0, assists: 0, steals: 0, blocks: 0, overallRating: 80)
        }
        let grid = GridDuelGrid(rows: [.team("LAL"), .position("PG")], columns: [.position("PG"), .team("LAL")], archiveRows: records)
        return GridDuelEngine(grid: grid, archiveRows: records)
    }

    func testRankedTiersIncludeGOATAsTheUniqueHighestRank() {
        XCTAssertEqual(RankedTier.forRating(799), .bronze)
        XCTAssertEqual(RankedTier.forRating(800), .silver)
        XCTAssertEqual(RankedTier.forRating(950), .gold)
        XCTAssertEqual(RankedTier.forRating(1_100), .platinum)
        XCTAssertEqual(RankedTier.forRating(1_250), .goat)
    }

    func testEveryRankedTierMapsToItsMatchingAIProfile() {
        XCTAssertEqual(RankedAIProfile(tier: .bronze), .bronze)
        XCTAssertEqual(RankedAIProfile(tier: .silver), .silver)
        XCTAssertEqual(RankedAIProfile(tier: .gold), .gold)
        XCTAssertEqual(RankedAIProfile(tier: .platinum), .platinum)
        XCTAssertEqual(RankedAIProfile(tier: .goat), .goat)
        XCTAssertEqual(RankedAIProfile.goat.tier, .goat)
    }

    func testRankedFallbackCapturesProfileFromRatingAtFallbackBoundary() {
        XCTAssertEqual(GameCenterCoordinator.fallbackProfile(forRating: 799), .bronze)
        XCTAssertEqual(GameCenterCoordinator.fallbackProfile(forRating: 800), .silver)
        XCTAssertEqual(GameCenterCoordinator.fallbackProfile(forRating: 950), .gold)
        XCTAssertEqual(GameCenterCoordinator.fallbackProfile(forRating: 1_100), .platinum)
        XCTAssertEqual(GameCenterCoordinator.fallbackProfile(forRating: 1_250), .goat)
    }

    func testRankedSearchRecognizesAnUnconfiguredGameCenterQueue() {
        let error = NSError(domain: GKErrorDomain, code: 5003)
        XCTAssertTrue(GameCenterCoordinator.isMissingQueueError(error))
        XCTAssertFalse(GameCenterCoordinator.isMissingQueueError(NSError(domain: GKErrorDomain, code: 1)))
    }

    func testRankedRatingClampsToConfiguredBounds() {
        XCTAssertEqual(RankedLadder.rating(afterWin: false, rating: 0, opponentRating: 3_000), 0)
        XCTAssertEqual(RankedLadder.rating(afterWin: true, rating: 3_000, opponentRating: 0), 3_000)
    }

    func testLeaderboardRowsDeriveTierAndKeepDisplaySafeValues() {
        let row = RankedLeaderboardService.row(placement: 17, playerID: "player-17", displayName: "Sky Hook", mmr: 1_250, isLocalPlayer: false)
        XCTAssertEqual(row.placement, 17)
        XCTAssertEqual(row.displayName, "Sky Hook")
        XCTAssertEqual(row.mmr, 1_250)
        XCTAssertEqual(row.tier, .goat)
    }

    func testLeaderboardLocalPlayerRowCanBeIdentifiedForPinning() {
        let row = RankedLeaderboardService.row(placement: 126, playerID: "me", displayName: "My Name", mmr: 800, isLocalPlayer: true)
        XCTAssertTrue(row.isLocalPlayer)
        XCTAssertEqual(row.tier, .silver)
    }

    func testRankedMatchupUsesLeaderboardRankWhenItIsAvailable() {
        let opponent = RankedLeaderboardRow(placement: 4, playerID: "opponent", displayName: "Sky Hook", mmr: 1_100, isLocalPlayer: false)
        let matchup = RankedMatchup.pvp(localName: "Me", localRating: 975, opponentName: "Fallback", opponentRow: opponent)
        XCTAssertEqual(matchup.local.tier, .gold)
        XCTAssertEqual(matchup.local.mmr, 975)
        XCTAssertEqual(matchup.opponent.displayName, "Sky Hook")
        XCTAssertEqual(matchup.opponent.tier, .platinum)
        XCTAssertEqual(matchup.opponent.mmr, 1_100)
    }

    func testRankedMatchupShowsSafeUnavailableRankFallback() {
        let matchup = RankedMatchup.pvp(localName: "Me", localRating: 1_000, opponentName: "New Player", opponentRow: nil)
        XCTAssertEqual(matchup.opponent.displayName, "New Player")
        XCTAssertNil(matchup.opponent.tier)
        XCTAssertNil(matchup.opponent.mmr)
        XCTAssertEqual(matchup.opponent.rankLabel, "RANK UNAVAILABLE")
    }

    func testRankedAIMatchupUsesProfileTierWithoutInventingMMR() {
        let matchup = RankedMatchup.aiFallback(localName: "Me", localRating: 800, profile: .goat)
        XCTAssertEqual(matchup.kind, .aiFallback)
        XCTAssertEqual(matchup.opponent.displayName, "RANKED AI")
        XCTAssertEqual(matchup.opponent.tier, .goat)
        XCTAssertNil(matchup.opponent.mmr)
    }

    func testRankedMatchupStageIsDistinctFromTheTeamRevealStage() {
        XCTAssertNotEqual(FriendBattleStage.matchup, .revealing)
    }

    private let team = TeamSeason(id: "test", team: "TST", season: "2024–25", players: [
        SeasonRecord(id: "p1", playerName: "Point", season: "2024–25", team: "TST", position: "PG", overallRating: 90),
        SeasonRecord(id: "p2", playerName: "Wing", season: "2024–25", team: "TST", position: "SF", overallRating: 85),
        SeasonRecord(id: "p3", playerName: "Big", season: "2024–25", team: "TST", position: "C", overallRating: 80)
    ])
    func testHigherBidWinsAndSalaryChanges() { var engine = AuctionEngine(teams: [team]); let result = engine.resolve(playerBid: 31, opponentBid: 12); XCTAssertEqual(result?.winner, .player); XCTAssertEqual(engine.playerBudget, 69) }
    func testTieIsDeterministic() { var a = AuctionEngine(teams: [team], seed: 99); var b = AuctionEngine(teams: [team], seed: 99); XCTAssertEqual(a.resolve(playerBid: 20, opponentBid: 20)?.winner, b.resolve(playerBid: 20, opponentBid: 20)?.winner) }
    func testFriendPerspectiveSwapsHostAndGuestState() {
        var engine = AuctionEngine(teams: [team])
        let outcome = engine.resolve(playerBid: 20, opponentBid: 2)!
        XCTAssertTrue(engine.select(team.players[0], for: outcome.winner, bid: outcome.bid))
        let guestView = engine.withSidesSwapped()
        XCTAssertEqual(guestView.playerRoster, engine.opponentRoster)
        XCTAssertEqual(guestView.opponentRoster, engine.playerRoster)
        XCTAssertEqual(guestView.playerBudget, engine.opponentBudget)
        XCTAssertEqual(guestView.opponentBudget, engine.playerBudget)
    }
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
    func testRankedBotDecisionsAreDeterministicForSeedAndProfile() {
        let a = AuctionEngine(teams: [team], seed: 456, rankedAIProfile: .gold)
        let b = AuctionEngine(teams: [team], seed: 456, rankedAIProfile: .gold)
        XCTAssertEqual(a.botBid(), b.botBid())
        XCTAssertEqual(a.botPick(), b.botPick())
    }
    func testPlatinumAndGOATAlwaysUseOptimalSelectionPath() {
        let offer = TeamSeason(id: "ranked-fit", team: "FIT", season: "S", players: [
            SeasonRecord(id: "best", playerName: "Best Fit", season: "S", team: "FIT", position: "SG", overallRating: 90),
            SeasonRecord(id: "weak", playerName: "Weak", season: "S", team: "FIT", position: "PG", overallRating: 76)
        ])
        for seed in UInt64(0)..<100 {
            XCTAssertEqual(AuctionEngine(teams: [offer], seed: seed, rankedAIProfile: .platinum).botPick()?.id, "best")
            XCTAssertEqual(AuctionEngine(teams: [offer], seed: seed, rankedAIProfile: .goat).botPick()?.id, "best")
        }
    }
    func testLowerRankedProfilesCanMakeDeterministicWeakSelections() {
        let offer = TeamSeason(id: "ranked-weak", team: "WEK", season: "S", players: [
            SeasonRecord(id: "best", playerName: "Best", season: "S", team: "WEK", position: "SG", overallRating: 95),
            SeasonRecord(id: "weak", playerName: "Weak", season: "S", team: "WEK", position: "PG", overallRating: 70)
        ])
        for profile in [RankedAIProfile.bronze, .silver, .gold] {
            XCTAssertTrue((UInt64(0)..<2_000).contains { seed in
                AuctionEngine(teams: [offer], seed: seed, rankedAIProfile: profile).botPick()?.id == "weak"
            }, "\(profile) should have a permitted weak-selection roll")
        }
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
    func testCollapsedCurrentTeamPanelStateKeepsPositionOrderedSlots() {
        let center = DraftedPlayer(season: SeasonRecord(id: "center", playerName: "Center", season: "S", team: "T", position: "C", overallRating: 80), bid: 1)
        let state = CurrentTeamPanelState(roster: [center], isExpanded: false)

        XCTAssertFalse(state.isExpanded)
        XCTAssertEqual(state.slots.map(\.position), ["PG", "SG", "SF", "PF", "C"])
        XCTAssertEqual(state.slots.map { $0.player?.season.playerName }, [nil, nil, nil, nil, "Center"])
    }
    func testExpandedCurrentTeamPanelStateShowsAllFiveSlots() {
        let shootingGuard = DraftedPlayer(season: SeasonRecord(id: "guard", playerName: "Guard", season: "S", team: "T", position: "SG", overallRating: 80), bid: 1)
        let state = CurrentTeamPanelState(roster: [shootingGuard], isExpanded: true)

        XCTAssertTrue(state.isExpanded)
        XCTAssertEqual(state.slots.count, 5)
        XCTAssertEqual(state.slots[1].player?.season.playerName, "Guard")
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
    func testOfflineVisualCatalogUsesOneStablePortraitKeyAndHistoricalLogoEras() {
        XCTAssertEqual(OfflineVisualCatalog.expectedTeamLogoName(team: "NJN", season: "2011–12"), "team_njn_1997_2011")
        XCTAssertEqual(OfflineVisualCatalog.expectedTeamLogoName(team: "BRK", season: "2012–13"), "team_brk_2012_2025")
        XCTAssertEqual(OfflineVisualCatalog.expectedTeamLogoName(team: "SEA", season: "2007–08"), "team_sea_2001_2007")
        XCTAssertEqual(OfflineVisualCatalog.expectedTeamLogoName(team: "OKC", season: "2008–09"), "team_okc_2008_2025")
        XCTAssertNil(OfflineVisualCatalog.expectedTeamLogoName(team: "TST", season: "2024–25"))
        XCTAssertEqual(OfflineVisualCatalog.portraitAssetName(for: "lebronj01"), OfflineVisualCatalog.portraitAssetName(for: "LEBRONJ01"))
    }
    func testDraftPortraitCoverageUsesStrictMoreThanHalfThreshold() {
        XCTAssertFalse(OfflineVisualCatalog.shouldSuppressDraftPortraits(missingHeadshots: 2, rosterCount: 4))
        XCTAssertTrue(OfflineVisualCatalog.shouldSuppressDraftPortraits(missingHeadshots: 3, rosterCount: 4))
    }
    func testDraftPortraitPolicyHidesCoveredPlayerOnlyForSuppressedTeamSeason() {
        let covered = OfflineVisualCatalog.TeamSeasonPortraitCoverage(team: "COV", season: "2024–25", rosterCount: 4, availableHeadshots: 2, missingHeadshots: 2, suppressDraftPortraits: false)
        let suppressed = OfflineVisualCatalog.TeamSeasonPortraitCoverage(team: "SUP", season: "2024–25", rosterCount: 4, availableHeadshots: 1, missingHeadshots: 3, suppressDraftPortraits: true)
        XCTAssertEqual(OfflineVisualCatalog.portraitPresentation(team: "COV", season: "2024–25", context: .draftSelection, hasAvailableHeadshot: true, coverage: covered), .realHeadshot)
        XCTAssertEqual(OfflineVisualCatalog.portraitPresentation(team: "SUP", season: "2024–25", context: .draftSelection, hasAvailableHeadshot: true, coverage: suppressed), .generatedAvatar)
    }
    func testStandardPortraitPolicyStillUsesAvailableHeadshotForSuppressedTeamSeason() {
        let suppressed = OfflineVisualCatalog.TeamSeasonPortraitCoverage(team: "SUP", season: "2024–25", rosterCount: 4, availableHeadshots: 1, missingHeadshots: 3, suppressDraftPortraits: true)
        XCTAssertEqual(OfflineVisualCatalog.portraitPresentation(team: "SUP", season: "2024–25", context: .standard, hasAvailableHeadshot: true, coverage: suppressed), .realHeadshot)
        XCTAssertEqual(OfflineVisualCatalog.portraitPresentation(team: "SUP", season: "2024–25", context: .standard, hasAvailableHeadshot: false, coverage: suppressed), .generatedAvatar)
    }
    func testHistoricalLogoTransitionsUseTheDisplayedSeason() {
        XCTAssertEqual(OfflineVisualCatalog.expectedTeamLogoName(team: "VAN", season: "2000–01"), "team_van_1995_2000")
        XCTAssertEqual(OfflineVisualCatalog.expectedTeamLogoName(team: "MEM", season: "2001–02"), "team_mem_2001_2003")
        XCTAssertEqual(OfflineVisualCatalog.expectedTeamLogoName(team: "CHH", season: "2001–02"), "team_chh_1988_2001")
        XCTAssertEqual(OfflineVisualCatalog.expectedTeamLogoName(team: "NOH", season: "2002–03"), "team_noh_2002_2004")
        XCTAssertEqual(OfflineVisualCatalog.expectedTeamLogoName(team: "NOK", season: "2005–06"), "team_nok_2005_2006")
        XCTAssertEqual(OfflineVisualCatalog.expectedTeamLogoName(team: "NOP", season: "2013–14"), "team_nop_2013_2025")
        XCTAssertEqual(OfflineVisualCatalog.expectedTeamLogoName(team: "WSB", season: "1996–97"), "team_wsb_1987_1996")
        XCTAssertEqual(OfflineVisualCatalog.expectedTeamLogoName(team: "WAS", season: "1997–98"), "team_was_1997_2006")
        XCTAssertEqual(OfflineVisualCatalog.expectedTeamLogoName(team: "CHA", season: "2013–14"), "team_cha_2012_2013")
        XCTAssertEqual(OfflineVisualCatalog.expectedTeamLogoName(team: "CHO", season: "2014–15"), "team_cho_2014_2025")
    }
    func testSameCodeRebrandUsesDifferentEraAssets() {
        XCTAssertNotEqual(
            OfflineVisualCatalog.expectedTeamLogoName(team: "PHO", season: "1991–92"),
            OfflineVisualCatalog.expectedTeamLogoName(team: "PHO", season: "1992–93")
        )
    }
    func testArchiveDerivedLakersAndWizardsBoundaries() {
        XCTAssertNotEqual(OfflineVisualCatalog.expectedTeamLogoName(team: "LAL", season: "2000–01"),
                          OfflineVisualCatalog.expectedTeamLogoName(team: "LAL", season: "2001–02"))
        XCTAssertNotEqual(OfflineVisualCatalog.expectedTeamLogoName(team: "WAS", season: "2006–07"),
                          OfflineVisualCatalog.expectedTeamLogoName(team: "WAS", season: "2007–08"))
        XCTAssertNotEqual(OfflineVisualCatalog.expectedTeamLogoName(team: "WAS", season: "2010–11"),
                          OfflineVisualCatalog.expectedTeamLogoName(team: "WAS", season: "2011–12"))
        XCTAssertNotEqual(OfflineVisualCatalog.expectedTeamLogoName(team: "WAS", season: "2014–15"),
                          OfflineVisualCatalog.expectedTeamLogoName(team: "WAS", season: "2015–16"))
    }
    func testPlayerFiltersIntersectAcrossCanonicalFranchiseHistory() {
        let oldNet = SeasonRecord(id: "net", playerID: "player", playerName: "Test Player", season: "2011–12", team: "NJN", position: "PG-SG", overallRating: 80)
        let brooklyn = SeasonRecord(id: "brooklyn", playerID: "player", playerName: "Test Player", season: "2013–14", team: "BRK", position: "PG", overallRating: 80)
        let database = NBAStatsDatabase(teamSeasons: [TeamSeason(id: "nj", team: "NJN", season: "2011–12", players: [oldNet]), TeamSeason(id: "bk", team: "BRK", season: "2013–14", players: [brooklyn])])
        let profile = database.searchPlayers("Test Player")[0]
        XCTAssertEqual(database.teamSeasonsByFranchise["BKN"]?.map(\.team), ["BRK", "NJN"])
        XCTAssertEqual(database.rows(for: profile, season: "2011–12", franchise: "BKN", position: "SG").map(\.id), ["net"])
    }
    func testHornetsCodesGroupIntoTheirActualFranchiseHistories() {
        XCTAssertEqual(NBAStatsDatabase.franchiseCode(for: "CHO"), "CHA")
        XCTAssertEqual(NBAStatsDatabase.franchiseCode(for: "CHA"), "CHA")
        XCTAssertEqual(NBAStatsDatabase.franchiseCode(for: "CHH"), "NOP")
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

    func testFiveAliveLocalWinUsesTypedOutcomeAndDisplayLabel() {
        let local = SeasonRecord(id: "local", playerName: "Local", season: "S", team: "T", position: "PG", overallRating: 99)
        let opponent = SeasonRecord(id: "opponent", playerName: "Opponent", season: "S", team: "T", position: "PG", overallRating: 80)

        let outcome = TeamSimulator.matchOutcome(player: [DraftedPlayer(season: local, bid: 1)], opponent: [DraftedPlayer(season: opponent, bid: 1)])

        XCTAssertEqual(outcome, .localWin)
        XCTAssertTrue(outcome.didLocalPlayerWin)
        XCTAssertEqual(outcome.displayLabel, "YOU WIN")
    }

    @MainActor
    func testRankedLocalWinAtZeroMMRGainsPoints() {
        let suiteName = "RankedFiveAliveWinTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(0, forKey: "ranked.monthly.rating")

        let result = RankedLadderService(defaults: defaults).recordCompletedMatch(id: "five-alive-local-win", didWin: FiveAliveMatchOutcome.localWin.didLocalPlayerWin)

        XCTAssertEqual(result?.outcome, .win)
        XCTAssertEqual(result?.ratingBefore, 0)
        XCTAssertEqual(result?.delta, 24)
        XCTAssertEqual(result?.ratingAfter, 24)
    }

    @MainActor
    func testFriendBattleCompletionAwardsHostForLocalWin() {
        XCTAssertEqual(FriendBattleSession.winnerID(for: .localWin, hostID: "host", peerID: "guest"), "host")
    }

    func testFiveAliveQuickChatPresetsHaveStableCodableIdentifiersAndDisplayText() throws {
        let expected: [(FiveAliveQuickChat, String, String)] = [
            (.goodLuck, "good_luck", "Good luck!"),
            (.niceBid, "nice_bid", "Nice bid."),
            (.yourTurn, "your_turn", "Your turn!"),
            (.thinking, "thinking", "Thinking…"),
            (.gg, "gg", "Good game!")
        ]

        XCTAssertEqual(FiveAliveQuickChat.allCases.count, expected.count)
        for (message, identifier, text) in expected {
            XCTAssertEqual(message.rawValue, identifier)
            XCTAssertEqual(message.text, text)
            XCTAssertEqual(try JSONDecoder().decode(FiveAliveQuickChat.self, from: JSONEncoder().encode(message)), message)
        }
    }

    func testBoxWarsQuickChatPresetsHaveStableCodableIdentifiersAndDisplayText() throws {
        let expected: [(BoxWarsQuickChat, String, String)] = [
            (.goodLuck, "good_luck", "Good luck!"),
            (.niceFind, "nice_find", "Nice find!"),
            (.gg, "gg", "Good game!")
        ]

        XCTAssertEqual(BoxWarsQuickChat.allCases.count, expected.count)
        for (message, identifier, text) in expected {
            XCTAssertEqual(message.rawValue, identifier)
            XCTAssertEqual(message.text, text)
            XCTAssertEqual(try JSONDecoder().decode(BoxWarsQuickChat.self, from: JSONEncoder().encode(message)), message)
        }
    }

    @MainActor
    func testBoxWarsFriendChatSendsAndReceivesOnlyBoxWarsMessagesOnce() async throws {
        let transport = MockMatchTransport(localPlayerID: "guest", opponentPlayerID: "host", opponentName: "Jordan")
        let session = BoxWarsFriendChatSession(transport: transport)
        defer { session.stop() }

        try await session.start()
        try await session.sendQuickChat(.niceFind)
        guard case let .quickChat(game, id)? = transport.sent.last?.event else {
            return XCTFail("Expected a Box Wars quick-chat envelope")
        }
        XCTAssertEqual(game, .boxWars)
        XCTAssertEqual(id, BoxWarsQuickChat.niceFind.rawValue)

        let chat = BattleEnvelope(sequence: 42, event: .quickChat(game: .boxWars, id: BoxWarsQuickChat.goodLuck.rawValue))
        let received = expectation(description: "immediately delivered Box Wars quick chat")
        var observation: AnyCancellable? = session.$latestQuickChat.dropFirst().sink { quickChat in
            if quickChat?.message == .goodLuck { received.fulfill() }
        }
        transport.receive(chat)
        await fulfillment(of: [received], timeout: 1)
        observation = nil
        XCTAssertEqual(session.latestQuickChat?.message, .goodLuck)
        let receivedID = session.latestQuickChat?.id

        transport.receive(chat)
        transport.receive(BattleEnvelope(sequence: 43, event: .quickChat(game: .fiveAlive, id: FiveAliveQuickChat.gg.rawValue)))
        await Task.yield()
        XCTAssertEqual(session.latestQuickChat?.id, receivedID)
    }

    @MainActor
    func testBoxWarsLocalQuickChatPresentsImmediateYouToast() {
        let model = GridDuelViewModel(mode: .versusAI)
        model.sendQuickChat(.niceFind)
        XCTAssertEqual(model.quickChatToast?.sender, "YOU")
        XCTAssertEqual(model.quickChatToast?.text, BoxWarsQuickChat.niceFind.text)
    }

    @MainActor
    func testFiveAliveLocalQuickChatPresentsImmediateYouToast() {
        let model = GameViewModel(difficulty: .easy, matchMode: .versusAI)
        model.sendQuickChat(.goodLuck)
        XCTAssertEqual(model.quickChatToast?.sender, "YOU")
        XCTAssertEqual(model.quickChatToast?.text, FiveAliveQuickChat.goodLuck.text)
    }

    @MainActor
    func testFriendBattleReceivesEachQuickChatEnvelopeOnlyOnce() async throws {
        let transport = MockMatchTransport(localPlayerID: "guest", opponentPlayerID: "host")
        let session = FriendBattleSession(transport: transport, hostID: "host")
        defer { session.stop() }

        try await session.start()
        let quickChat = BattleEnvelope(sequence: 42, event: .quickChat(game: .fiveAlive, id: FiveAliveQuickChat.yourTurn.rawValue))
        let received = expectation(description: "immediately delivered Five Alive quick chat")
        var observation: AnyCancellable? = session.$latestQuickChat.dropFirst().sink { chat in
            if chat?.message == .yourTurn { received.fulfill() }
        }
        transport.receive(quickChat)
        await fulfillment(of: [received], timeout: 1)
        observation = nil

        XCTAssertEqual(session.latestQuickChat?.message, .yourTurn)
        let receivedID = session.latestQuickChat?.id
        transport.receive(quickChat)
        await Task.yield()
        XCTAssertEqual(session.latestQuickChat?.message, .yourTurn)
        XCTAssertEqual(session.latestQuickChat?.id, receivedID)
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
