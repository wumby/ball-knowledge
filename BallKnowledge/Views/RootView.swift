import SwiftUI
import GameKit
import Combine

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var route: Route = .home
    @State private var difficulty: MatchDifficulty = .easy
    @State private var friendMatch: GKMatch?
    @State private var friendHostID: String?
    @State private var matchMode: OnlineMatchMode = .versusAI
    @State private var rankedMatchKind: RankedMatchKind = .pvp
    @State private var rankedAIProfile: RankedAIProfile?
    @State private var rankedMatchup: RankedMatchup?
    @State private var gridDuelRankedMatchup: RankedMatchup?
    @State private var rankTransition: RankTransition?
    @StateObject private var gameCenter = GameCenterCoordinator()
    @StateObject private var gridDuelGameCenter = GameCenterCoordinator(competitiveGame: .boxWars)
    @StateObject private var rankedLadder = RankedLadderService()
    @StateObject private var gridDuelLadder = GridDuelLadderService()
    @StateObject private var leaderboard = RankedLeaderboardService()
    @StateObject private var gridDuelLeaderboard = GridDuelLeaderboardService()
    @StateObject private var navigation = RouteNavigationCoordinator()

    var body: some View {
        ZStack {
            ArenaBackground()
            Group {
                switch route {
                case .home:
                    HomeHub(route: routedRoute, difficulty: $difficulty)
                case .gameSetup:
                    GameSetupView(route: routedRoute, matchMode: $matchMode)
                case .gridDuelSetup:
                    GridDuelSetupView(route: routedRoute, matchMode: $matchMode)
                case .gridDuelRankedHub:
                    GridDuelRankedHubView(route: routedRoute, matchMode: $matchMode, friendMatch: $friendMatch, rankedMatchup: $gridDuelRankedMatchup, gameCenter: gridDuelGameCenter, ladder: gridDuelLadder, leaderboard: gridDuelLeaderboard, rankTransition: rankTransition, consumeRankTransition: consumeRankTransition)
                case .gridDuelLeaderboard:
                    GridDuelLeaderboardView(route: routedRoute, gameCenter: gridDuelGameCenter, leaderboard: gridDuelLeaderboard)
                case .gridDuelRankDetails:
                    GridDuelRankDetailsView(route: routedRoute, ladder: gridDuelLadder)
                case .gridDuelFriendSetup:
                    GridDuelFriendSetupView(route: routedRoute, matchMode: $matchMode, gameCenter: gridDuelGameCenter, friendMatch: $friendMatch)
                case .aiSetup:
                    AISetupView(route: routedRoute, difficulty: $difficulty, friendMatch: $friendMatch, matchMode: $matchMode)
                case .rankedHub:
                    RankedHubView(route: routedRoute, difficulty: $difficulty, friendMatch: $friendMatch, matchMode: $matchMode, rankedMatchKind: $rankedMatchKind, rankedAIProfile: $rankedAIProfile, rankedMatchup: $rankedMatchup, gameCenter: gameCenter, rankedLadder: rankedLadder, leaderboard: leaderboard, rankTransition: rankTransition, consumeRankTransition: consumeRankTransition)
                case .leaderboard:
                    RankedLeaderboardView(route: routedRoute, gameCenter: gameCenter, leaderboard: leaderboard)
                case .rankDetails:
                    RankDetailsView(route: routedRoute, rankedLadder: rankedLadder)
                case .friendSetup:
                    FriendSetupView(route: routedRoute, difficulty: $difficulty, friendMatch: $friendMatch, friendHostID: $friendHostID, matchMode: $matchMode, gameCenter: gameCenter)
                case .game:
                    GameView(route: routedRoute, difficulty: difficulty, friendMatch: friendMatch, friendHostID: friendHostID, matchMode: matchMode, rankedMatchKind: rankedMatchKind, rankedLadder: rankedLadder, rankedAIProfile: rankedAIProfile, rankedMatchup: rankedMatchup, onExit: { finishGameSession($0) })
                case .gridDuel:
                    GridDuelView(route: routedRoute, mode: matchMode, ladder: gridDuelLadder, friendMatch: friendMatch, opponentName: gridDuelRankedMatchup?.opponent.displayName ?? friendMatch?.players.first?.displayName ?? (matchMode == .ranked ? "RANKED AI" : "OPPONENT"), opponentTier: matchMode == .ranked ? gridDuelRankedMatchup?.opponent.tier : nil, onExit: { finishGridDuelSession($0) })
                }
            }
            .id(route)
            .transition(ScreenMotion.transition(reduceMotion: reduceMotion))
            .animation(ScreenMotion.animation(reduceMotion: reduceMotion), value: route)
            .allowsHitTesting(!navigation.isTransitioning)

            if navigation.isTransitioning {
                RouteLoadingOverlay()
                    .transition(.opacity)
                    .allowsHitTesting(true)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: navigation.isTransitioning)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // This is the actual screen-sized container. It must retain its full
        // height when a child text field presents the keyboard.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { gameCenter.resetRankedSession(); gridDuelGameCenter.resetRankedSession() }
        }
    }

    private func finishRankedSession() {
        gameCenter.resetRankedSession()
        friendMatch = nil
        friendHostID = nil
        rankedAIProfile = nil
        rankedMatchup = nil
    }

    private func finishGameSession(_ result: RankedMatchResult? = nil) {
        // A GameView owns its live transport; once it exits, no route-level
        // Game Center reference should keep that GKMatch alive.
        if let result { rankTransition = RankTransition(result: result, game: .fiveAlive) }
        finishRankedSession()
    }

    private func finishGridDuelSession(_ result: RankedMatchResult? = nil) {
        if let result { rankTransition = RankTransition(result: result, game: .boxWars) }
        gridDuelGameCenter.resetRankedSession()
        friendMatch = nil
        gridDuelRankedMatchup = nil
    }

    private func consumeRankTransition(_ id: UUID) {
        guard rankTransition?.id == id else { return }
        rankTransition = nil
    }

    private var routedRoute: Binding<Route> {
        Binding(
            get: { route },
            set: { destination in
                navigation.navigate(to: destination, from: route, reduceMotion: reduceMotion) {
                    route = $0
                }
            }
        )
    }
}
enum Route: Hashable { case home, gameSetup, aiSetup, rankedHub, leaderboard, rankDetails, friendSetup, game, gridDuelSetup, gridDuel, gridDuelRankedHub, gridDuelLeaderboard, gridDuelRankDetails, gridDuelFriendSetup }
enum OnlineMatchMode: Equatable { case versusAI, friend, ranked }
enum RankedMatchKind: Equatable { case pvp, aiFallback
    var label: String { self == .pvp ? "RANKED PVP" : "RANKED VS AI" }
}

private enum HomeTab: String, CaseIterable { case games = "Games", stats = "Stats" }

private struct HomeHub: View {
    @Binding var route: Route
    @Binding var difficulty: MatchDifficulty
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: HomeTab = .games
    @State private var statsResetID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if tab == .games {
                    HomeView(route: $route, difficulty: $difficulty)
                        .id(HomeTab.games)
                        .transition(ScreenMotion.transition(reduceMotion: reduceMotion))
                } else {
                    StatsView(resetID: statsResetID)
                        .id(HomeTab.stats)
                        .transition(ScreenMotion.transition(reduceMotion: reduceMotion))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(ScreenMotion.animation(reduceMotion: reduceMotion), value: tab)

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

@MainActor
final class RouteNavigationCoordinator: ObservableObject {
    @Published private(set) var isTransitioning = false

    func navigate(to destination: Route, from currentRoute: Route, reduceMotion: Bool, apply: @escaping (Route) -> Void) {
        guard !isTransitioning, destination != currentRoute else { return }
        isTransitioning = true

        Task { @MainActor in
            // Let the overlay reach the screen before creating the next route's view tree.
            await Task.yield()
            withAnimation(ScreenMotion.animation(reduceMotion: reduceMotion)) {
                apply(destination)
            }
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeInOut(duration: 0.16)) {
                isTransitioning = false
            }
        }
    }
}

enum ScreenMotion {
    static func animation(reduceMotion: Bool) -> Animation {
        .easeInOut(duration: reduceMotion ? 0.2 : 0.24)
    }

    static func transition(reduceMotion: Bool) -> AnyTransition {
        .opacity
    }
}

struct RouteLoadingOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.48).ignoresSafeArea()
            VStack(spacing: 12) {
                if reduceMotion {
                    Image(systemName: "basketball.fill")
                        .font(.title2.weight(.black))
                        .foregroundStyle(Color.accent)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Color.accent)
                }
                Text("LOADING…")
                    .font(.caption.weight(.black))
                    .tracking(1.4)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.accent.opacity(0.3)))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading")
        .accessibilityAddTraits(.isModal)
    }
}
