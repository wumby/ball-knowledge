import SwiftUI

struct StatsView: View {
    @State private var query = ""
    @State private var position = "All"
    @State private var selectedTeam: String?
    @State private var selectedSeason: TeamSeason?
    @State private var selected: SeasonRecord?

    private let teams = BundledSeasonRepository.allTeams
    private let positions = ["All", "PG", "SG", "SF", "PF", "C"]

    private var franchises: [(code: String, seasons: [TeamSeason])] {
        Dictionary(grouping: teams, by: \.team)
            .map { (code: $0.key, seasons: $0.value.sorted { $0.season > $1.season }) }
            .sorted { $0.code < $1.code }
    }

    // Search is deliberately empty until the player supplies a name. This prevents
    // the UI from constructing or sorting every player row as the archive grows.
    private var playerResults: [SeasonRecord] {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return [] }
        return teams.lazy.flatMap(\.players)
            .filter { $0.playerName.localizedCaseInsensitiveContains(query) }
            .filter { position == "All" || $0.position.contains(position) }
            .prefix(50)
            .sorted { $0.points > $1.points }
    }

    private var roster: [SeasonRecord] {
        guard let selectedSeason else { return [] }
        return selectedSeason.players
            .filter { position == "All" || $0.position.contains(position) }
            .sorted { $0.points == $1.points ? $0.playerName < $1.playerName : $0.points > $1.points }
    }

    var body: some View {
        Group {
            if let season = selectedSeason { rosterView(season) }
            else if let team = selectedTeam { seasonList(team) }
            else { teamDirectory }
        }
        .sheet(item: $selected) { player in PlayerStatDetail(player: player) }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var teamDirectory: some View {
        VStack(spacing: 0) {
            header(title: "STAT DATABASE", subtitle: "BROWSE BY TEAM OR SEARCH A PLAYER")
            playerSearch
            if query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                positionFilters
                resultList(playerResults, heading: "PLAYER RESULTS", detail: playerResults.count == 50 ? "TOP 50" : "\(playerResults.count)")
            } else {
                HStack { Text("TEAMS"); Spacer(); Text("\(franchises.count) AVAILABLE") }.scoreLabel().padding(.horizontal, 20).padding(.top, 14)
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(franchises, id: \.code) { franchise in
                            Button { selectedTeam = franchise.code } label: {
                                HStack(spacing: 13) {
                                    TeamBadge(team: franchise.code, size: 48)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(TeamBrand.name(for: franchise.code)).font(.headline.weight(.black))
                                        Text("\(franchise.code) · \(franchise.seasons.count) TEAM-YEARS AVAILABLE").scoreLabel()
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.38))
                                }.padding(11).background(.white.opacity(0.065)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08))).clipShape(RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 12)
                }.scrollIndicators(.hidden)
            }
        }
    }

    private func seasonList(_ team: String) -> some View {
        let seasons = franchises.first(where: { $0.code == team })?.seasons ?? []
        return VStack(spacing: 0) {
            header(title: TeamBrand.name(for: team), subtitle: "\(team) · SELECT A TEAM-YEAR", back: { selectedTeam = nil })
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(seasons) { season in
                        Button { selectedSeason = season } label: {
                            HStack(spacing: 13) {
                                TeamBadge(team: season.team, size: 46)
                                VStack(alignment: .leading, spacing: 3) { Text(season.season).font(.headline.weight(.black)); Text("\(season.players.count) PLAYERS WITH STATS").scoreLabel() }
                                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.38))
                            }.padding(11).background(.white.opacity(0.065)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08))).clipShape(RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                    }
                }.padding(20)
            }.scrollIndicators(.hidden)
        }
    }

    private func rosterView(_ season: TeamSeason) -> some View {
        VStack(spacing: 0) {
            header(title: "\(season.team) \(season.season)", subtitle: "FULL ROSTER STAT LINE", back: { selectedSeason = nil })
            positionFilters
            resultList(roster, heading: "\(roster.count) PLAYERS", detail: "TAP FOR FULL STATS")
        }
    }

    private func resultList(_ players: [SeasonRecord], heading: String, detail: String) -> some View {
        VStack(spacing: 0) {
            HStack { Text(heading); Spacer(); Text(detail) }.scoreLabel().padding(.horizontal, 20).padding(.top, 4)
            ScrollView { LazyVStack(spacing: 9) { ForEach(players) { player in Button { selected = player } label: { PlayerStatRow(player: player) }.buttonStyle(.plain) } }.padding(.horizontal, 20).padding(.vertical, 12) }.scrollIndicators(.hidden)
        }
    }

    private func header(title: String, subtitle: String, back: (() -> Void)? = nil) -> some View {
        HStack(spacing: 13) {
            if let back { Button(action: back) { Image(systemName: "chevron.left").font(.headline.bold()).frame(width: 42, height: 42).background(.white.opacity(0.08)).clipShape(Circle()) } }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.black))
                Text(subtitle).scoreLabel()
            }
            Spacer()
            Image(systemName: "basketball.fill").font(.title2).foregroundStyle(Color.accent)
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 14)
    }

    private var playerSearch: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.48))
            TextField("Search for a player", text: $query)
                .textInputAutocapitalization(.words).autocorrectionDisabled()
            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.48)) } }
        }
        .padding(.horizontal, 14).frame(height: 48)
        .background(.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    private var positionFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(positions, id: \.self) { item in
                    Button(item) { position = item }
                        .font(.caption.weight(.black))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(position == item ? Color.accent : .white.opacity(0.08))
                        .foregroundStyle(position == item ? .black : .white)
                        .clipShape(Capsule())
                }
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }.scrollIndicators(.hidden)
    }
}

private struct PlayerStatRow: View {
    let player: SeasonRecord
    var body: some View {
        HStack(spacing: 12) {
            TeamBadge(team: player.team, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(player.playerName).font(.subheadline.weight(.black)).lineLimit(1)
                Text("\(player.team)  •  \(player.season)  •  \(player.position)").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.58))
            }
            Spacer(minLength: 4)
            HStack(spacing: 9) {
                StatMini(value: player.points, label: "PTS")
                StatMini(value: player.rebounds, label: "REB")
                StatMini(value: player.assists, label: "AST")
            }
        }
        .padding(10).background(.white.opacity(0.065)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct StatMini: View {
    let value: Double; let label: String
    var body: some View { VStack(spacing: 1) { Text(value, format: .number.precision(.fractionLength(1))).font(.caption.weight(.black)); Text(label).scoreLabel().font(.system(size: 8, weight: .black)) } }
}

private struct PlayerStatDetail: View {
    @Environment(\.dismiss) private var dismiss
    let player: SeasonRecord
    var body: some View {
        VStack(spacing: 20) {
            HStack { Spacer(); Button("Done") { dismiss() }.fontWeight(.bold).foregroundStyle(Color.accent) }
            TeamBadge(team: player.team, size: 82)
            Text(player.playerName).font(.title.weight(.black))
            Text("\(player.team)  •  \(player.season)  •  \(player.position)").foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                DetailStat("PPG", player.points); DetailStat("RPG", player.rebounds); DetailStat("APG", player.assists)
                DetailStat("SPG", player.steals); DetailStat("BPG", player.blocks); DetailStat("MPG", player.minutes)
                DetailStat("FG%", player.fgPercent, percent: true); DetailStat("3P%", player.threePercent, percent: true); DetailStat("FT%", player.ftPercent, percent: true)
            }
            Text("\(player.games) GAMES PLAYED").scoreLabel()
            Spacer()
        }
        .padding(24).presentationDetents([.medium])
    }
    private func DetailStat(_ label: String, _ value: Double, percent: Bool = false) -> some View {
        VStack(spacing: 4) { Text(value, format: .number.precision(.fractionLength(1))).font(.title3.weight(.black)); Text(label).scoreLabel() }
            .frame(maxWidth: .infinity).padding(.vertical, 12).background(.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
