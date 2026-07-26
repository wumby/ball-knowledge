import SwiftUI
import GameKit

struct RootView: View {
    @State private var route: Route = .home
    @State private var difficulty: MatchDifficulty = .easy
    @State private var friendMatch: GKMatch?
    @State private var friendHostID: String?
    @State private var matchMode: OnlineMatchMode = .versusAI
    @State private var rankedMatchKind: RankedMatchKind = .pvp
    @State private var rankedAIProfile: RankedAIProfile?
    @State private var rankedMatchup: RankedMatchup?
    @StateObject private var gameCenter = GameCenterCoordinator()
    @StateObject private var rankedLadder = RankedLadderService()
    @StateObject private var gridDuelLadder = GridDuelLadderService()
    @StateObject private var leaderboard = RankedLeaderboardService()
    var body: some View {
        ZStack {
            ArenaBackground()
            Group {
                switch route {
                case .home:
                    HomeHub(route: $route, difficulty: $difficulty)
                case .gameSetup:
                    GameSetupView(route: $route, matchMode: $matchMode)
                case .gridDuelSetup:
                    GridDuelSetupView(route: $route, matchMode: $matchMode)
                case .aiSetup:
                    AISetupView(route: $route, difficulty: $difficulty, friendMatch: $friendMatch, matchMode: $matchMode)
                case .rankedHub:
                    RankedHubView(route: $route, difficulty: $difficulty, friendMatch: $friendMatch, matchMode: $matchMode, rankedMatchKind: $rankedMatchKind, rankedAIProfile: $rankedAIProfile, rankedMatchup: $rankedMatchup, gameCenter: gameCenter, rankedLadder: rankedLadder)
                case .leaderboard:
                    RankedLeaderboardView(route: $route, gameCenter: gameCenter, leaderboard: leaderboard)
                case .rankDetails:
                    RankDetailsView(route: $route, rankedLadder: rankedLadder)
                case .friendSetup:
                    FriendSetupView(route: $route, difficulty: $difficulty, friendMatch: $friendMatch, friendHostID: $friendHostID, matchMode: $matchMode, gameCenter: gameCenter)
                case .game:
                    GameView(route: $route, difficulty: difficulty, friendMatch: friendMatch, friendHostID: friendHostID, matchMode: matchMode, rankedMatchKind: rankedMatchKind, rankedLadder: rankedLadder, rankedAIProfile: rankedAIProfile, rankedMatchup: rankedMatchup)
                case .gridDuel:
                    GridDuelView(route: $route, mode: matchMode, ladder: gridDuelLadder)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // This is the actual screen-sized container. It must retain its full
        // height when a child text field presents the keyboard.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .preferredColorScheme(.dark)
    }
}
enum Route { case home, gameSetup, aiSetup, rankedHub, leaderboard, rankDetails, friendSetup, game, gridDuelSetup, gridDuel }
enum OnlineMatchMode: Equatable { case versusAI, friend, ranked }
enum RankedMatchKind: Equatable { case pvp, aiFallback
    var label: String { self == .pvp ? "RANKED PVP" : "RANKED VS AI" }
}

private enum HomeTab: String, CaseIterable { case games = "Games", stats = "Stats" }

private struct HomeHub: View {
    @Binding var route: Route
    @Binding var difficulty: MatchDifficulty
    @State private var tab: HomeTab = .games
    @State private var statsResetID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if tab == .games { HomeView(route: $route, difficulty: $difficulty) }
                else { StatsView(resetID: statsResetID) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                ForEach(HomeTab.allCases, id: \.self) { item in
                    Button {
                        if item == .stats, tab == .stats {
                            statsResetID = UUID()
                        } else {
                            tab = item
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item == .games ? "gamecontroller.fill" : "chart.bar.xaxis")
                                .font(.system(size: 18, weight: .bold))
                            Text(item.rawValue).font(.caption2.weight(.black))
                        }
                        .foregroundStyle(tab == item ? Color.accent : .white.opacity(0.48))
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 7).padding(.bottom, 4)
            .background(.ultraThinMaterial)
        }
    }
}
