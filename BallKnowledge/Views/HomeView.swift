import SwiftUI
import GameKit
import UIKit

struct HomeView: View {
    @Binding var route: Route
    @Binding var difficulty: MatchDifficulty

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 700
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 14 : 20) {
                    BrandHeader(compact: compact)
                    Text("GAMES").scoreLabel()
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            Image("FiveAliveMark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: compact ? 54 : 64, height: compact ? 54 : 64)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("FIVE ALIVE").font(.title3.weight(.black))
                                Text("BUILD THE BEST FIVE").font(.caption.weight(.black)).foregroundStyle(Color.accent)
                            }
                            Spacer()
                        }
                        Text("Bid on legendary team-years, draft the right player, and outbuild your rival.")
                            .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.70))
                        Button { route = .gameSetup } label: { Label("PLAY FIVE ALIVE", systemImage: "banknote.fill").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle(compact: compact))
                    }
                    .padding(compact ? 15 : 18)
                    .background(LinearGradient(colors: [Color.accent.opacity(0.15), .white.opacity(0.055)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.accent.opacity(0.32)))
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            Image("BoxWarsMark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: compact ? 54 : 64, height: compact ? 54 : 64)
                            VStack(alignment: .leading, spacing: 3) { Text("BOX WARS").font(.title3.weight(.black)); Text("90-SECOND NBA BOX FIGHT").font(.caption.weight(.black)).foregroundStyle(Color.accent) }
                            Spacer()
                        }
                        Text("Fill a four-square grid with players who match both clues. Submit your best answers before the buzzer.")
                            .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.70))
                        Button { route = .gridDuelSetup } label: { Label("PLAY BOX WARS", systemImage: "square.grid.2x2.fill").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle(compact: compact))
                    }
                    .padding(compact ? 15 : 18)
                    .background(LinearGradient(colors: [Color.accent.opacity(0.15), .white.opacity(0.055)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.accent.opacity(0.32)))
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                    HStack(spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.title2.weight(.black))
                            .foregroundStyle(.white.opacity(0.34))
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.055))
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("MORE GAMES").scoreLabel()
                            Text("COMING SOON").font(.headline.weight(.black)).foregroundStyle(.white.opacity(0.68))
                            Text("Leave a comment with the game you want to see next.")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.42))
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(compact ? 14 : 16)
                    .background(.white.opacity(0.035))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08)))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .padding(.horizontal, 20).padding(.top, compact ? 14 : 22).padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

}

struct GameSetupView: View {
    @Binding var route: Route
    @Binding var matchMode: OnlineMatchMode
    var body: some View {
        FiveAlivePage(route: $route, title: "FIVE ALIVE", subtitle: "CHOOSE HOW YOU PLAY") {
            PlayModeCard(title: "PRACTICE", subtitle: "Draft against a computer rival", icon: "cpu") { matchMode = .versusAI; route = .aiSetup }
            PlayModeCard(title: "RANKED LADDER", subtitle: "Face random players and climb to GOAT", icon: "trophy.fill") { matchMode = .ranked; route = .rankedHub }
            PlayModeCard(title: "FRIEND MATCH", subtitle: "Send a private Game Center challenge", icon: "person.2.fill") { matchMode = .friend; route = .friendSetup }
        }
    }
}

struct GridDuelSetupView: View {
    @Binding var route: Route
    @Binding var matchMode: OnlineMatchMode
    var body: some View {
        FiveAlivePage(route: $route, title: "BOX WARS", subtitle: "CHOOSE HOW YOU PLAY") {
            PlayModeCard(title: "PRACTICE AI", subtitle: "Solve a fresh 2×2 NBA archive grid", icon: "cpu") { matchMode = .versusAI; route = .gridDuel }
            PlayModeCard(title: "RANKED LADDER", subtitle: "Box Wars MMR is separate from Five Alive", icon: "trophy.fill") { matchMode = .ranked; route = .gridDuel }
            PlayModeCard(title: "FRIEND MATCH", subtitle: "Local Box Wars practice while Game Center transport is configured", icon: "person.2.fill") { matchMode = .friend; route = .gridDuel }
            Text("Each shared grid runs for 90 seconds. Rarity tiers and points reveal after the buzzer.").font(.caption).foregroundStyle(.white.opacity(0.6))
        }
    }
}

struct AISetupView: View {
    @Binding var route: Route; @Binding var difficulty: MatchDifficulty; @Binding var friendMatch: GKMatch?; @Binding var matchMode: OnlineMatchMode
    @State private var selectedDifficulty: MatchDifficulty = .easy
    var body: some View {
        FiveAlivePage(route: $route, back: .gameSetup, title: "PRACTICE", subtitle: "PICK A SCOUTING LEVEL") {
            ForEach(MatchDifficulty.allCases) { level in
                Button { selectedDifficulty = level } label: { HStack { VStack(alignment: .leading) { Text(level.rawValue).font(.headline.weight(.black)); Text(level.subtitle).font(.caption).foregroundStyle(.white.opacity(0.6)) }; Spacer(); Image(systemName: selectedDifficulty == level ? "checkmark.circle.fill" : "circle").foregroundStyle(selectedDifficulty == level ? Color.accent : .white.opacity(0.3)) }.padding(14).modeCard(selectedDifficulty == level) }.buttonStyle(.plain)
            }
            Button { difficulty = selectedDifficulty; friendMatch = nil; matchMode = .versusAI; route = .game } label: { Label("START PRACTICE", systemImage: "banknote.fill").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle())
        }
    }
}

struct RankedHubView: View {
    @Binding var route: Route; @Binding var difficulty: MatchDifficulty; @Binding var friendMatch: GKMatch?; @Binding var matchMode: OnlineMatchMode
    @Binding var rankedMatchKind: RankedMatchKind
    @Binding var rankedAIProfile: RankedAIProfile?
    @Binding var rankedMatchup: RankedMatchup?
    @ObservedObject var gameCenter: GameCenterCoordinator; @ObservedObject var rankedLadder: RankedLadderService
    var body: some View {
        FiveAlivePage(route: $route, back: .gameSetup, title: "RANKED", subtitle: "MONTHLY LADDER") {
            HStack { VStack(alignment: .leading) { Text("CURRENT RANK").scoreLabel(); Text("\(rankedLadder.rating) MMR").font(.title.weight(.black)).foregroundStyle(Color.accent); Text(rankedLadder.tier.rawValue).font(.headline.weight(.black)) }; Spacer(); RankBadge(tier: rankedLadder.tier, size: 58) }.padding(18).modeCard(true)
            Button { route = .leaderboard } label: { Label("LEADERBOARD", systemImage: "list.number").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle())
            Button { route = .rankDetails } label: { Label("RANKS & MMR", systemImage: "chart.bar.fill").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle())
            rankedAction
        }
        .onAppear { gameCenter.authenticate() }
        .onChange(of: gameCenter.match) { _, match in
            guard let match else { return }
            Task {
                rankedMatchup = await gameCenter.rankedMatchup(for: match, localRating: rankedLadder.rating)
                friendMatch = match; difficulty = RankedMatchSetup.difficulty(afterSelecting: difficulty); matchMode = .ranked; rankedMatchKind = .pvp; rankedAIProfile = nil; route = .game
            }
        }
        .onChange(of: gameCenter.rankedSearchState) { _, state in
            guard case let .startingAI(profile) = state else { return }
            friendMatch = nil; difficulty = RankedMatchSetup.difficulty(afterSelecting: difficulty); matchMode = .ranked; rankedMatchKind = .aiFallback; rankedAIProfile = profile
            rankedMatchup = .aiFallback(localName: GKLocalPlayer.local.displayName, localRating: rankedLadder.rating, profile: profile)
            route = .game
        }
        .authenticationSheet(gameCenter)
    }
    @ViewBuilder private var rankedAction: some View {
        switch gameCenter.status {
        case .ready:
            Text("We’ll search for a real opponent for up to 30 seconds. If nobody is available, you’ll play a ranked match against AI instead.")
                .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.72))
            switch gameCenter.rankedSearchState {
            case let .searching(stage, elapsed):
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView().tint(Color.accent)
                    Text(stage.playerMessage).font(.headline.weight(.black))
                    Text("Your rating: \(rankedLadder.rating) MMR · searching ±\(stage.acceptedMMRRange) · \(max(0, RankedSearchStage.duration - elapsed)) seconds left")
                        .font(.caption).foregroundStyle(.white.opacity(0.55)).monospacedDigit()
                    Button { gameCenter.cancelRankedMatch() } label: { Label("CANCEL SEARCH", systemImage: "xmark.circle.fill").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle())
                    Text("Cancelling does not affect your rank.").font(.caption).foregroundStyle(.white.opacity(0.58))
                }.padding(14).modeCard(true)
            case .startingAI:
                ProgressView("No player found — starting a Ranked AI match.").tint(Color.accent)
            case let .failed(message):
                VStack(alignment: .leading, spacing: 8) { Text("Couldn’t connect to Game Center.").font(.headline.weight(.black)); Text(message).font(.caption).foregroundStyle(.white.opacity(0.65)); Button("TRY AGAIN") { gameCenter.startRankedSearch(rating: rankedLadder.rating) }.buttonStyle(SecondaryButtonStyle()) }.padding(14).modeCard()
            case .idle:
                Button { Task { await rankedLadder.refreshFromGameCenter(); gameCenter.startRankedSearch(rating: rankedLadder.rating) } } label: { Label("FIND A FAIR MATCH", systemImage: "trophy.fill").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle())
            }
        case .authenticating: ProgressView("SIGNING IN TO GAME CENTER…").frame(maxWidth: .infinity).padding()
        case let .unavailable(message): Text(message).foregroundStyle(.red)
        case .idle: EmptyView()
        }
        if let error = gameCenter.inviteError { Text(error).font(.caption).foregroundStyle(.white.opacity(0.65)) }
    }
}

struct RankDetailsView: View {
    @Binding var route: Route; @ObservedObject var rankedLadder: RankedLadderService
    var body: some View { FiveAlivePage(route: $route, back: .rankedHub, title: "RANKS & MMR", subtitle: "MONTHLY REQUIREMENTS") { ForEach(RankedTier.allCases, id: \.self) { tier in HStack(spacing: 12) { RankBadge(tier: tier, size: 44); Text(tier.rawValue).font(.headline.weight(.black)).foregroundStyle(tier == rankedLadder.tier ? Color.accent : .white); Spacer(); Text(tier.requiredMMR).font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(.white.opacity(0.68)) }.padding(14).modeCard(tier == rankedLadder.tier) }; Text("Wins and losses update your MMR after every ranked match.").font(.caption).foregroundStyle(.white.opacity(0.6)) } }
}

struct FriendSetupView: View {
    @Binding var route: Route; @Binding var difficulty: MatchDifficulty; @Binding var friendMatch: GKMatch?; @Binding var friendHostID: String?; @Binding var matchMode: OnlineMatchMode
    @ObservedObject var gameCenter: GameCenterCoordinator; @State private var showingMatchmaker = false; @State private var selectedDifficulty: MatchDifficulty = .easy
    var body: some View {
        FiveAlivePage(route: $route, back: .gameSetup, title: "FRIEND MATCH", subtitle: "PRIVATE GAME CENTER CHALLENGE") {
            Text("Invite one friend through Game Center to start a private Five Alive match.").font(.subheadline).foregroundStyle(.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 8) {
                Text("SCOUTING LEVEL").scoreLabel()
                ForEach(MatchDifficulty.allCases) { level in
                    Button { selectedDifficulty = level } label: {
                        HStack { VStack(alignment: .leading, spacing: 2) { Text(level.rawValue).font(.headline.weight(.black)); Text(level.subtitle).font(.caption).foregroundStyle(.white.opacity(0.62)) }; Spacer(); if selectedDifficulty == level { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accent) } }
                            .padding(13).modeCard(selectedDifficulty == level)
                    }.buttonStyle(.plain)
                }
            }
            friendAction
        }
        .onAppear { gameCenter.authenticate() }
        .sheet(isPresented: $showingMatchmaker) { FriendMatchmakerView(coordinator: gameCenter) }
        .onChange(of: gameCenter.match) { _, match in if let match { difficulty = selectedDifficulty; friendHostID = GKLocalPlayer.local.gamePlayerID; friendMatch = match; matchMode = .friend; route = .game } }
        .authenticationSheet(gameCenter)
    }
    @ViewBuilder private var friendAction: some View { switch gameCenter.status { case .ready: Button { showingMatchmaker = true } label: { Label("INVITE FRIEND", systemImage: "person.crop.circle.badge.plus").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle()); case .authenticating: ProgressView("SIGNING IN TO GAME CENTER…").frame(maxWidth: .infinity).padding(); case let .unavailable(message): Text(message).foregroundStyle(.red); case .idle: EmptyView() }; if let error = gameCenter.inviteError { Text(error).font(.caption).foregroundStyle(.white.opacity(0.65)) } }
}

private struct AuthenticationSheet: Identifiable { let controller: UIViewController; var id: ObjectIdentifier { ObjectIdentifier(controller) } }
private extension View { func authenticationSheet(_ coordinator: GameCenterCoordinator) -> some View { sheet(item: Binding(get: { coordinator.authenticationController.map(AuthenticationSheet.init) }, set: { _ in coordinator.authenticationController = nil }), onDismiss: { coordinator.refreshAuthenticationStatus() }) { GameCenterAuthenticationView(controller: $0.controller) } }; func modeCard(_ selected: Bool = false) -> some View { background(selected ? Color.accent.opacity(0.14) : .white.opacity(0.055)).overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.accent.opacity(0.75) : .white.opacity(0.12))).clipShape(RoundedRectangle(cornerRadius: 14)) } }
private struct FiveAlivePage<Content: View>: View { @Binding var route: Route; var back: Route = .home; let title: String; let subtitle: String; @ViewBuilder let content: Content; init(route: Binding<Route>, back: Route = .home, title: String, subtitle: String, @ViewBuilder content: () -> Content) { _route = route; self.back = back; self.title = title; self.subtitle = subtitle; self.content = content() }; var body: some View { ScrollView { VStack(alignment: .leading, spacing: 14) { Button { route = back } label: { Image(systemName: "chevron.left").font(.headline.bold()).frame(width: 42, height: 42).background(.white.opacity(0.08)).clipShape(Circle()) }; BrandHeader(compact: false, title: title, tagline: subtitle, markAsset: "FiveAliveMark"); content }.padding(20) }.scrollIndicators(.hidden) } }
private struct PlayModeCard: View { let title: String; let subtitle: String; let icon: String; let action: () -> Void; var body: some View { Button(action: action) { HStack(spacing: 12) { Image(systemName: icon).font(.title3.weight(.black)).foregroundStyle(Color.accent).frame(width: 28); VStack(alignment: .leading, spacing: 2) { Text(title).font(.subheadline.weight(.black)); Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.58)) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.45)) }.padding(14).modeCard() }.buttonStyle(.plain) } }

struct RankedLeaderboardView: View {
    @Binding var route: Route
    @ObservedObject var gameCenter: GameCenterCoordinator
    @ObservedObject var leaderboard: RankedLeaderboardService
    @State private var filter: RankedLeaderboardFilter = .global

    var body: some View {
        FiveAlivePage(route: $route, back: .rankedHub, title: "LEADERBOARD", subtitle: "CURRENT MONTH") {
            Picker("Leaderboard filter", selection: $filter) { ForEach(RankedLeaderboardFilter.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented)
            content
        }
        .task { await leaderboard.load(filter: filter) }
        .onChange(of: filter) { _, newFilter in Task { await leaderboard.load(filter: newFilter) } }
        .onChange(of: gameCenter.status) { _, status in if status == .ready { Task { await leaderboard.load(filter: filter) } } }
        .onAppear { if gameCenter.status == .idle { gameCenter.authenticate() } }
        .authenticationSheet(gameCenter)
    }

    @ViewBuilder private var content: some View {
        switch leaderboard.state {
        case .idle, .loading:
            ProgressView("LOADING LEADERBOARD…").frame(maxWidth: .infinity).padding(30)
        case .signInRequired:
            VStack(spacing: 10) { Image(systemName: "person.crop.circle.badge.exclamationmark").font(.largeTitle).foregroundStyle(Color.accent); Text("SIGN IN TO GAME CENTER").font(.headline.weight(.black)); Text("Connect Game Center to view the monthly ranked leaderboard.").font(.caption).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center); Button("SIGN IN") { gameCenter.authenticate() }.buttonStyle(SecondaryButtonStyle()) }.frame(maxWidth: .infinity).padding(20).modeCard()
        case .emptyFriends:
            ContentUnavailableView("NO FRIENDS RANKED YET", systemImage: "person.2.slash", description: Text("Play ranked with Game Center friends to see them here.")).foregroundStyle(.white)
        case let .failed(message):
            VStack(spacing: 10) { ContentUnavailableView("LEADERBOARD UNAVAILABLE", systemImage: "exclamationmark.triangle", description: Text(message)); Button("TRY AGAIN") { Task { await leaderboard.load(filter: filter) } }.buttonStyle(SecondaryButtonStyle()) }.foregroundStyle(.white)
        case .loaded:
            if let pinned = leaderboard.pinnedLocalPlayer { leaderboardRow(pinned, pinned: true); Text("YOUR POSITION").scoreLabel().foregroundStyle(.white.opacity(0.55)) }
            ForEach(leaderboard.rows) { leaderboardRow($0, pinned: false) }
        }
    }

    private func leaderboardRow(_ row: RankedLeaderboardRow, pinned: Bool) -> some View {
        HStack(spacing: 10) { Text("#\(row.placement)").font(.subheadline.weight(.black)).monospacedDigit().foregroundStyle(row.isLocalPlayer ? Color.accent : .white.opacity(0.7)).frame(width: 36, alignment: .leading); RankBadge(tier: row.tier, size: 38); VStack(alignment: .leading, spacing: 2) { Text(row.displayName).font(.subheadline.weight(.black)).lineLimit(1); Text(row.tier.rawValue).scoreLabel().foregroundStyle(row.isLocalPlayer ? Color.accent : .white.opacity(0.48)) }; Spacer(minLength: 2); VStack(alignment: .trailing, spacing: 1) { Text("\(row.mmr)").font(.headline.weight(.black)).monospacedDigit(); Text("MMR").scoreLabel().foregroundStyle(.white.opacity(0.45)) } }.padding(12).background(row.isLocalPlayer || pinned ? Color.accent.opacity(0.14) : .white.opacity(0.045)).overlay(RoundedRectangle(cornerRadius: 12).stroke(row.isLocalPlayer || pinned ? Color.accent.opacity(0.65) : .white.opacity(0.08))).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct RulesView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("HOW TO PLAY").font(.title2.weight(.black)); Spacer(); Button("Done") { dismiss() }.fontWeight(.bold) }
            rule("1", "Bid on 10 iconic team-years with a $100M cap.")
            rule("2", "Win a team-year and draft one player from its roster.")
            rule("3", "Build five players. The highest combined overall rating wins.")
            Spacer()
        }.padding(24).presentationDetents([.height(360)])
    }
    private func rule(_ number: String, _ copy: String) -> some View { HStack(alignment: .top, spacing: 14) { Text(number).font(.headline.weight(.black)).foregroundStyle(.black).frame(width: 30, height: 30).background(Color.accent).clipShape(Circle()); Text(copy).font(.body.weight(.medium)) } }
}

struct BrandHeader: View {
    let compact: Bool
    var title: String = "HOOPS IQ"
    var tagline: String?
    var markAsset: String = "BrandMark"

    var body: some View {
        HStack(spacing: compact ? 10 : 12) {
            Image(markAsset)
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 52 : 62, height: compact ? 52 : 62)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 14 : 17, style: .continuous))
                .shadow(color: Color.accent.opacity(0.35), radius: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: compact ? 24 : 29, weight: .black, design: .rounded))
                    .tracking(-0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                if let tagline {
                    Text(tagline).scoreLabel().foregroundStyle(Color.accent)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

struct RankBadge: View {
    let tier: RankedTier
    let size: CGFloat

    var body: some View {
        Image(tier.badgeAssetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(tier.rawValue + " rank badge")
    }
}

extension Color { static let appBackground = Color(red: 0.035, green: 0.02, blue: 0.07); static let accent = Color(red: 0.961, green: 0.184, blue: 0.525) }
struct TeamBrand {
    let primary: Color
    let secondary: Color
    static func forTeam(_ team: String) -> TeamBrand {
        switch team {
        case "LAL": TeamBrand(primary: Color(red: 0.33, green: 0.19, blue: 0.55), secondary: Color(red: 0.99, green: 0.72, blue: 0.15))
        case "BOS": TeamBrand(primary: Color(red: 0.02, green: 0.48, blue: 0.28), secondary: Color.white)
        case "CHI": TeamBrand(primary: Color(red: 0.78, green: 0.05, blue: 0.12), secondary: Color.white)
        case "GSW", "OKC": TeamBrand(primary: Color(red: 0.04, green: 0.29, blue: 0.62), secondary: Color(red: 1.0, green: 0.78, blue: 0.08))
        case "MIA": TeamBrand(primary: Color(red: 0.60, green: 0.03, blue: 0.09), secondary: Color(red: 0.96, green: 0.68, blue: 0.20))
        case "SAS": TeamBrand(primary: Color(red: 0.55, green: 0.57, blue: 0.58), secondary: Color.white)
        case "DET": TeamBrand(primary: Color(red: 0.79, green: 0.06, blue: 0.14), secondary: Color(red: 0.05, green: 0.20, blue: 0.47))
        case "DEN": TeamBrand(primary: Color(red: 0.05, green: 0.18, blue: 0.40), secondary: Color(red: 0.98, green: 0.71, blue: 0.10))
        case "PHX": TeamBrand(primary: Color(red: 0.28, green: 0.09, blue: 0.46), secondary: Color(red: 0.98, green: 0.36, blue: 0.05))
        case "MIL": TeamBrand(primary: Color(red: 0.00, green: 0.28, blue: 0.20), secondary: Color(red: 0.93, green: 0.82, blue: 0.52))
        case "TOR": TeamBrand(primary: Color(red: 0.80, green: 0.05, blue: 0.12), secondary: Color.white)
        case "NYK": TeamBrand(primary: Color(red: 0.00, green: 0.40, blue: 0.72), secondary: Color(red: 0.95, green: 0.35, blue: 0.10))
        case "HOU": TeamBrand(primary: Color(red: 0.75, green: 0.03, blue: 0.09), secondary: Color.white)
        case "UTA": TeamBrand(primary: Color(red: 0.05, green: 0.23, blue: 0.45), secondary: Color(red: 0.98, green: 0.73, blue: 0.12))
        case "CLE": TeamBrand(primary: Color(red: 0.40, green: 0.04, blue: 0.10), secondary: Color(red: 0.98, green: 0.72, blue: 0.14))
        default: TeamBrand(primary: Color(red: 0.05, green: 0.32, blue: 0.58), secondary: Color.accent)
        }
    }
    static func name(for team: String) -> String {
        let names = [
            "ATL": "Atlanta Hawks", "BKN": "Brooklyn Nets", "BRK": "Brooklyn Nets", "BOS": "Boston Celtics", "CHA": "Charlotte Bobcats", "CHO": "Charlotte Hornets", "CHH": "Charlotte Hornets", "CHI": "Chicago Bulls", "CLE": "Cleveland Cavaliers", "DAL": "Dallas Mavericks", "DEN": "Denver Nuggets", "DET": "Detroit Pistons", "GSW": "Golden State Warriors", "HOU": "Houston Rockets", "IND": "Indiana Pacers", "KCK": "Kansas City Kings", "LAC": "Los Angeles Clippers", "LAL": "Los Angeles Lakers", "MEM": "Memphis Grizzlies", "MIA": "Miami Heat", "MIL": "Milwaukee Bucks", "MIN": "Minnesota Timberwolves", "NJN": "New Jersey Nets", "NOH": "New Orleans Hornets", "NOK": "New Orleans/Oklahoma City Hornets", "NOP": "New Orleans Pelicans", "NYK": "New York Knicks", "OKC": "Oklahoma City Thunder", "ORL": "Orlando Magic", "PHI": "Philadelphia 76ers", "PHO": "Phoenix Suns", "PHX": "Phoenix Suns", "POR": "Portland Trail Blazers", "SAC": "Sacramento Kings", "SAS": "San Antonio Spurs", "SDC": "San Diego Clippers", "SEA": "Seattle SuperSonics", "TOR": "Toronto Raptors", "UTA": "Utah Jazz", "VAN": "Vancouver Grizzlies", "WAS": "Washington Wizards", "WSB": "Washington Bullets"
        ]
        return names[team] ?? team
    }
}
struct TeamBadge: View {
    let team: String
    let size: CGFloat
    var body: some View { let brand = TeamBrand.forTeam(team); ZStack { Circle().fill(LinearGradient(colors: [brand.primary, brand.secondary.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)); Circle().stroke(.white.opacity(0.3), lineWidth: 1); Image(systemName: "basketball.fill").font(.system(size: size * 0.34, weight: .black)).foregroundStyle(.white.opacity(0.24)); Text(team).font(.system(size: size * 0.23, weight: .black, design: .rounded)).tracking(-1).foregroundStyle(.white) }.frame(width: size, height: size).shadow(color: brand.primary.opacity(0.45), radius: 10) }
}
struct ArenaBackground: View { var body: some View { LinearGradient(colors: [Color.appBackground, Color(red: 0.10, green: 0.035, blue: 0.13), Color.appBackground], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea().overlay(alignment: .topTrailing) { Circle().fill(Color.accent.opacity(0.12)).frame(width: 360).blur(radius: 24).offset(x: 120, y: -150) } } }
struct PrimaryButtonStyle: ButtonStyle { let compact: Bool; init(compact: Bool = false) { self.compact = compact }; func makeBody(configuration: Configuration) -> some View { configuration.label.font(.headline.weight(.black)).foregroundStyle(.black).padding(compact ? 13 : 17).background(Color.accent).clipShape(RoundedRectangle(cornerRadius: 15)).scaleEffect(configuration.isPressed ? 0.98 : 1) } }
struct SecondaryButtonStyle: ButtonStyle { let compact: Bool; init(compact: Bool = false) { self.compact = compact }; func makeBody(configuration: Configuration) -> some View { configuration.label.font(.headline.weight(.bold)).foregroundStyle(.white).padding(compact ? 12 : 16).frame(maxWidth: .infinity).background(.white.opacity(configuration.isPressed ? 0.1 : 0.04)).overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.14))).clipShape(RoundedRectangle(cornerRadius: 15)) } }
extension View { func scoreLabel() -> some View { font(.caption2.weight(.black)).tracking(1.4).foregroundStyle(.white.opacity(0.48)) } }
