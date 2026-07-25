import SwiftUI

struct StatsView: View {
    private enum TeamSeasonSource {
        case franchise(NBAFranchise)
        case season(String)

        var previousScreen: Screen {
            switch self {
            case .franchise(let franchise): .franchise(franchise)
            case .season(let season): .season(season)
            }
        }
    }

    private enum Screen {
        case landing, players, teams, seasons, leaders, leaderBoard(String?), franchise(NBAFranchise), season(String), roster(TeamSeason, TeamSeasonSource), profile(NBAPlayerProfile)
    }

    @State private var screen: Screen = .landing
    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var selectedSeasonFilter: String?
    @State private var selectedFranchiseFilter: String?
    @State private var selectedPositionFilter: String?
    @State private var selectedLeaderStat: LeaderStat = .points
    @State private var selected: SeasonRecord?
    @State private var database: NBAStatsDatabase?
    @State private var loadError: String?
    @FocusState private var isPlayerSearchFocused: Bool

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView("NBA ARCHIVE UNAVAILABLE", systemImage: "exclamationmark.triangle", description: Text(loadError)).foregroundStyle(.white)
            } else if let database {
                content(database)
            } else {
                ProgressView("LOADING NBA ARCHIVE…").tint(Color.accent)
            }
        }
        .sheet(item: $selected) { PlayerStatDetail(player: $0) }
        .task {
            guard database == nil, loadError == nil else { return }
            do { database = try await NBAStatsStore.shared.database() }
            catch { loadError = error.localizedDescription }
        }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            debouncedQuery = query
        }
    }

    @ViewBuilder private func content(_ database: NBAStatsDatabase) -> some View {
        switch screen {
        case .landing: landing
        case .players: players(database)
        case .teams: franchises(database)
        case .seasons: seasons(database)
        case .leaders: leaderSeasons(database)
        case .leaderBoard(let season): leaderBoard(database, season: season)
        case .franchise(let franchise):
            teamSeasons(
                database.teamSeasonsByFranchise[franchise.id] ?? [],
                title: franchise.name,
                subtitle: "FRANCHISE HISTORY",
                back: { screen = .teams },
                openRoster: { screen = .roster($0, .franchise(franchise)) }
            )
        case .season(let season):
            teamSeasons(
                database.teamSeasonsBySeason[season] ?? [],
                title: season,
                subtitle: "TEAM SEASONS",
                back: { screen = .seasons },
                openRoster: { screen = .roster($0, .season(season)) }
            )
        case .roster(let teamSeason, let source):
            roster(teamSeason, back: { screen = source.previousScreen })
        case .profile(let profile): profileView(profile, database: database)
        }
    }

    private var landing: some View {
        VStack(alignment: .leading, spacing: 14) {
            header(title: "STAT DATABASE", subtitle: "NBA PLAYER DATA · 1979–80 TO 2025–26")
            Text("Find a player, trace a franchise, or jump to any season.").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.68)).padding(.horizontal, 20)
            browseCard("Players", subtitle: "SEARCH PLAYER PROFILES", icon: "magnifyingglass") { screen = .players }
            browseCard("Teams", subtitle: "BROWSE FRANCHISE HISTORY", icon: "building.2.fill") { screen = .teams }
            browseCard("Seasons", subtitle: "BROWSE TEAM-YEARS", icon: "calendar") { screen = .seasons }
            browseCard("Leaders", subtitle: "SEASON + ALL-TIME TOP 10", icon: "list.number") { screen = .leaders }
            Spacer()
        }
        .padding(.top, 10)
    }

    private func players(_ database: NBAStatsDatabase) -> some View {
        let results = database.searchPlayers(debouncedQuery)
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                header(title: "PLAYERS", subtitle: "SEARCH EVERY PLAYER", back: leavePlayers)
                playerSearch
            }

            Group {
                ScrollView {
                    if debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView("SEARCH FOR A PLAYER", systemImage: "magnifyingglass", description: Text("Results are grouped into one profile per person."))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 64)
                    } else {
                        HStack { Text("PLAYER RESULTS"); Spacer(); Text("\(results.count)") }
                            .scoreLabel()
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                        LazyVStack(spacing: 9) { ForEach(results) { profile in
                            Button { screen = .profile(profile) } label: { profileRow(profile) }.buttonStyle(.plain)
                        } }
                        .padding(20)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func franchises(_ database: NBAStatsDatabase) -> some View {
        VStack(spacing: 0) {
            header(title: "TEAMS", subtitle: "BROWSE FRANCHISE HISTORY", back: { screen = .landing })
            ScrollView { LazyVStack(spacing: 9) { ForEach(database.franchises) { franchise in
                Button { screen = .franchise(franchise) } label: {
                    HStack(spacing: 13) { TeamBadge(team: franchise.id, size: 48); VStack(alignment: .leading, spacing: 3) { Text(franchise.name).font(.headline.weight(.black)); Text("\(franchise.teamCodes.joined(separator: ", ")) · \(database.teamSeasonsByFranchise[franchise.id]?.count ?? 0) TEAM-YEARS").scoreLabel() }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.38)) }.cardStyle()
                }.buttonStyle(.plain)
            } }.padding(20) }.scrollIndicators(.hidden)
        }
    }

    private func seasons(_ database: NBAStatsDatabase) -> some View {
        VStack(spacing: 0) {
            header(title: "SEASONS", subtitle: "BROWSE EVERY TEAM-YEAR", back: { screen = .landing })
            ScrollView { LazyVStack(spacing: 9) { ForEach(database.seasons, id: \.self) { season in
                Button { screen = .season(season) } label: { HStack { VStack(alignment: .leading, spacing: 3) { Text(season).font(.headline.weight(.black)); Text("\(database.teamSeasonsBySeason[season]?.count ?? 0) TEAMS AVAILABLE").scoreLabel() }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.38)) }.cardStyle() }.buttonStyle(.plain)
            } }.padding(20) }.scrollIndicators(.hidden)
        }
    }

    private func leaderSeasons(_ database: NBAStatsDatabase) -> some View {
        VStack(spacing: 0) {
            header(title: "LEADERS", subtitle: "TOP 10 BY STAT", back: { screen = .landing })
            ScrollView {
                LazyVStack(spacing: 9) {
                    Button { openLeaderBoard(season: nil) } label: {
                        HStack {
                            Image(systemName: "trophy.fill").font(.title3.weight(.black)).foregroundStyle(Color.accent).frame(width: 34)
                            VStack(alignment: .leading, spacing: 3) { Text("All Time").font(.headline.weight(.black)); Text("BEST SINGLE-SEASON PERFORMANCES").scoreLabel() }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.38))
                        }.cardStyle()
                    }.buttonStyle(.plain)
                    ForEach(database.seasons, id: \.self) { season in
                        Button { openLeaderBoard(season: season) } label: {
                            HStack { VStack(alignment: .leading, spacing: 3) { Text(season).font(.headline.weight(.black)); Text("SEASON LEADERS").scoreLabel() }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.38)) }.cardStyle()
                        }.buttonStyle(.plain)
                    }
                }.padding(20)
            }.scrollIndicators(.hidden)
        }
    }

    private func leaderBoard(_ database: NBAStatsDatabase, season: String?) -> some View {
        let leaders = database.leaders(for: selectedLeaderStat, season: season)
        return VStack(spacing: 0) {
            header(title: season ?? "ALL TIME", subtitle: "\(selectedLeaderStat.rawValue.uppercased()) LEADERS", back: { screen = .leaders })
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(LeaderStat.allCases) { stat in
                        Button { selectedLeaderStat = stat } label: {
                            Text(stat.rawValue).font(.caption.weight(.black)).padding(.horizontal, 14).padding(.vertical, 9)
                                .background(selectedLeaderStat == stat ? Color.accent : .white.opacity(0.08))
                                .foregroundStyle(selectedLeaderStat == stat ? .black : .white).clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 20).padding(.vertical, 4)
            }.scrollIndicators(.hidden)
            HStack { Text("TOP 10"); Spacer(); Text(selectedLeaderStat.shortLabel) }.scoreLabel().padding(.horizontal, 20).padding(.top, 10)
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(Array(leaders.enumerated()), id: \.element.id) { index, entry in
                        Button { selected = entry.record } label: { leaderRow(entry, rank: index + 1, showsSeason: season == nil) }.buttonStyle(.plain)
                    }
                }.padding(20)
            }.scrollIndicators(.hidden)
        }
    }

    private func teamSeasons(_ rows: [TeamSeason], title: String, subtitle: String, back: @escaping () -> Void, openRoster: @escaping (TeamSeason) -> Void) -> some View {
        VStack(spacing: 0) {
            header(title: title, subtitle: subtitle, back: back)
            ScrollView { LazyVStack(spacing: 9) { ForEach(rows) { row in
                Button { openRoster(row) } label: { teamSeasonCard(row) }.buttonStyle(.plain)
            } }.padding(20) }.scrollIndicators(.hidden)
        }
    }

    private func roster(_ teamSeason: TeamSeason, back: @escaping () -> Void) -> some View {
        let players = teamSeason.players.sorted { $0.points > $1.points }
        return VStack(spacing: 0) {
            header(
                title: "\(TeamBrand.name(for: teamSeason.team)) · \(teamSeason.season)",
                subtitle: "FULL ROSTER · \(players.count) PLAYERS",
                back: back
            )
            ScrollView { LazyVStack(spacing: 9) { ForEach(players) { player in
                Button { selected = player } label: { PlayerStatRow(player: player) }.buttonStyle(.plain)
            } }.padding(20) }.scrollIndicators(.hidden)
        }
    }

    private func profileView(_ profile: NBAPlayerProfile, database: NBAStatsDatabase) -> some View {
        let rows = database.rows(for: profile, season: selectedSeasonFilter, franchise: selectedFranchiseFilter, position: selectedPositionFilter)
        return VStack(spacing: 0) {
            header(title: profile.playerName, subtitle: "\(profile.seasons.count) AVAILABLE PLAYER-SEASONS", back: { clearFilters(); screen = .players })
            filters(database)
            HStack { Text("PLAYER-SEASONS"); Spacer(); Text("\(rows.count)") }.scoreLabel().padding(.horizontal, 20).padding(.top, 4)
            ScrollView { LazyVStack(spacing: 9) { ForEach(rows) { player in Button { selected = player } label: { PlayerStatRow(player: player) }.buttonStyle(.plain) } }.padding(20) }.scrollIndicators(.hidden)
        }
    }

    private func filters(_ database: NBAStatsDatabase) -> some View {
        ScrollView(.horizontal) { HStack(spacing: 8) {
            filterMenu("Season", selection: $selectedSeasonFilter, options: database.seasons)
            filterMenu("Franchise", selection: $selectedFranchiseFilter, options: database.franchises.map(\.id))
            filterMenu("Position", selection: $selectedPositionFilter, options: database.positions)
        }.padding(.horizontal, 20).padding(.vertical, 12) }.scrollIndicators(.hidden)
    }

    private func filterMenu(_ title: String, selection: Binding<String?>, options: [String]) -> some View {
        Menu { Button("All \(title)s") { selection.wrappedValue = nil }; ForEach(options, id: \.self) { value in Button(value) { selection.wrappedValue = value } } } label: { Text(selection.wrappedValue ?? title).font(.caption.weight(.black)).padding(.horizontal, 14).padding(.vertical, 9).background(selection.wrappedValue == nil ? .white.opacity(0.08) : Color.accent).foregroundStyle(selection.wrappedValue == nil ? .white : .black).clipShape(Capsule()) }
    }

    private var playerSearch: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.48))
                TextField("Search for a player", text: $query)
                    .focused($isPlayerSearchFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.48))
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Button("Cancel", action: cancelPlayerSearch)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.accent)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
    private func teamSeasonCard(_ row: TeamSeason) -> some View { HStack(spacing: 12) { TeamBadge(team: row.team, size: 42); VStack(alignment: .leading, spacing: 3) { Text(TeamBrand.name(for: row.team)).font(.subheadline.weight(.black)); Text(row.team).scoreLabel() }; Spacer(); VStack(alignment: .trailing, spacing: 3) { Text(row.season).font(.subheadline.weight(.black)); Text("\(row.players.count) PLAYERS").scoreLabel() }; Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.38)) }.cardStyle() }
    private func leaderRow(_ entry: NBALeaderEntry, rank: Int, showsSeason: Bool) -> some View { HStack(spacing: 12) { Text("\(rank)").font(.title3.weight(.black)).foregroundStyle(rank <= 3 ? Color.accent : .white.opacity(0.65)).frame(width: 24); TeamBadge(team: entry.record.team == "Multiple Teams" ? "NBA" : entry.record.team, size: 38); VStack(alignment: .leading, spacing: 3) { Text(entry.record.playerName).font(.subheadline.weight(.black)).lineLimit(1); Text("\(entry.teamLabel)  •  \(entry.record.position)\(showsSeason ? "  •  \(entry.record.season)" : "")").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.58)).lineLimit(1) }; Spacer(minLength: 4); Text(leaderValue(entry)).font(.title3.weight(.black)).foregroundStyle(Color.accent) }.cardStyle() }
    private func leaderValue(_ entry: NBALeaderEntry) -> String { entry.stat == .games ? "\(entry.record.games)" : entry.value.formatted(.number.precision(.fractionLength(1))) }
    private func profileRow(_ profile: NBAPlayerProfile) -> some View { HStack(spacing: 13) { TeamBadge(team: profile.seasons.first?.team ?? "NBA", size: 46); VStack(alignment: .leading, spacing: 3) { Text(profile.playerName).font(.headline.weight(.black)); Text("\(profile.seasons.count) PLAYER-SEASONS · \(profile.seasons.first?.season ?? "") TO \(profile.seasons.last?.season ?? "")").scoreLabel() }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.38)) }.cardStyle() }
    private func browseCard(_ title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View { Button(action: action) { HStack(spacing: 14) { Image(systemName: icon).font(.title2.weight(.black)).foregroundStyle(Color.accent).frame(width: 40); VStack(alignment: .leading, spacing: 3) { Text(title).font(.title3.weight(.black)); Text(subtitle).scoreLabel() }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4)) }.cardStyle() }.buttonStyle(.plain).padding(.horizontal, 20) }
    private func header(title: String, subtitle: String, back: (() -> Void)? = nil) -> some View { HStack(spacing: 13) { if let back { Button(action: back) { Image(systemName: "chevron.left").font(.headline.bold()).frame(width: 42, height: 42).background(.white.opacity(0.08)).clipShape(Circle()) } }; VStack(alignment: .leading, spacing: 2) { Text(title).font(.title2.weight(.black)); Text(subtitle).scoreLabel() }; Spacer(); Image(systemName: "basketball.fill").font(.title2).foregroundStyle(Color.accent) }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 14) }
    private func clearFilters() { selectedSeasonFilter = nil; selectedFranchiseFilter = nil; selectedPositionFilter = nil }
    private func openLeaderBoard(season: String?) { selectedLeaderStat = .points; screen = .leaderBoard(season) }
    private func cancelPlayerSearch() { query = ""; isPlayerSearchFocused = false }
    private func leavePlayers() { cancelPlayerSearch(); screen = .landing }
}

private extension View { func cardStyle() -> some View { padding(11).background(.white.opacity(0.065)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08))).clipShape(RoundedRectangle(cornerRadius: 14)) } }

private struct PlayerStatRow: View { let player: SeasonRecord; var body: some View { HStack(spacing: 12) { TeamBadge(team: player.team, size: 42); VStack(alignment: .leading, spacing: 3) { Text(player.playerName).font(.subheadline.weight(.black)).lineLimit(1); Text("\(player.team)  •  \(player.season)  •  \(player.position)").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.58)) }; Spacer(minLength: 4); HStack(spacing: 9) { StatMini(value: player.points, label: "PTS"); StatMini(value: player.rebounds, label: "REB"); StatMini(value: player.assists, label: "AST") } }.padding(10).background(.white.opacity(0.065)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08))).clipShape(RoundedRectangle(cornerRadius: 14)) } }
private struct StatMini: View { let value: Double; let label: String; var body: some View { VStack(spacing: 1) { Text(value, format: .number.precision(.fractionLength(1))).font(.caption.weight(.black)); Text(label).scoreLabel().font(.system(size: 8, weight: .black)) } } }
private struct PlayerStatDetail: View { @Environment(\.dismiss) private var dismiss; let player: SeasonRecord; var body: some View { VStack(spacing: 20) { HStack { Spacer(); Button("Done") { dismiss() }.fontWeight(.bold).foregroundStyle(Color.accent) }; TeamBadge(team: player.team, size: 82); Text(player.playerName).font(.title.weight(.black)); Text("\(player.team)  •  \(player.season)  •  \(player.position)").foregroundStyle(.secondary); LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) { DetailStat("PPG", player.points); DetailStat("RPG", player.rebounds); DetailStat("APG", player.assists); DetailStat("SPG", player.steals); DetailStat("BPG", player.blocks); DetailStat("MPG", player.minutes); DetailStat("FG%", player.fgPercent); DetailStat("3P%", player.threePercent); DetailStat("FT%", player.ftPercent) }; Text("\(player.games) GAMES PLAYED").scoreLabel(); Spacer() }.padding(24).presentationDetents([.medium]) }; private func DetailStat(_ label: String, _ value: Double) -> some View { VStack(spacing: 4) { Text(value, format: .number.precision(.fractionLength(1))).font(.title3.weight(.black)); Text(label).scoreLabel() }.frame(maxWidth: .infinity).padding(.vertical, 12).background(.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12)) } }
