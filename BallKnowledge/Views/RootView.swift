import SwiftUI

struct RootView: View {
    @State private var route: Route = .home
    @State private var difficulty: MatchDifficulty = .easy
    var body: some View {
        ZStack {
            ArenaBackground()
            Group {
                switch route {
                case .home:
                    HomeHub(route: $route, difficulty: $difficulty)
                case .gameSetup:
                    GameSetupView(route: $route, difficulty: $difficulty)
                case .game:
                    GameView(route: $route, difficulty: difficulty)
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
enum Route { case home, gameSetup, game }

private enum HomeTab: String, CaseIterable { case games = "Games", stats = "Stats" }

private struct HomeHub: View {
    @Binding var route: Route
    @Binding var difficulty: MatchDifficulty
    @State private var tab: HomeTab = .games

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if tab == .games { HomeView(route: $route, difficulty: $difficulty) }
                else { StatsView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                ForEach(HomeTab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
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
