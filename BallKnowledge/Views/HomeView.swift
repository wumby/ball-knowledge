import SwiftUI
import GameKit
import UIKit
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
            PlayModeCard(title: "RANKED LADDER", subtitle: "Box Wars MMR is separate from Five Alive", icon: "trophy.fill") { matchMode = .ranked; route = .gridDuelRankedHub }
            PlayModeCard(title: "FRIEND MATCH", subtitle: "Send a private Game Center Box Wars challenge", icon: "person.2.fill") { matchMode = .friend; route = .gridDuelFriendSetup }
            Text("Each shared grid runs for 90 seconds. Rarity tiers and points reveal after the buzzer.").font(.caption).foregroundStyle(.white.opacity(0.6))
        }
    }
}

struct GridDuelRankedHubView: View {
    @Binding var route: Route
    @Binding var matchMode: OnlineMatchMode
    @Binding var friendMatch: GKMatch?
    @Binding var rankedMatchup: RankedMatchup?
    @ObservedObject var gameCenter: GameCenterCoordinator
    @ObservedObject var ladder: GridDuelLadderService
    @ObservedObject var leaderboard: GridDuelLeaderboardService
    var rankTransition: RankTransition?
    var consumeRankTransition: (UUID) -> Void = { _ in }
    @State private var showingLeaderboard = false
    @State private var showingRanks = false
    @State private var matchupTask: Task<Void, Never>?

    var body: some View {
        FiveAlivePage(route: $route, back: .gridDuelSetup, title: "BOX WARS RANKED", subtitle: "MONTHLY LADDER") {
            RankedHeader(display: ladder.display, game: .boxWars, transition: rankTransition, consumeTransition: consumeRankTransition)
            LeaderboardSubmissionStatusCard(status: ladder.leaderboardSubmissionStatus, retry: ladder.retryPendingLeaderboardSubmission)
            Button { showingLeaderboard = true } label: { Label("Leaderboard", systemImage: "list.number").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle())
            Button { showingRanks = true } label: { Label("Ranks & MMR", systemImage: "chart.bar.fill").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle())
            action
        }
        .onAppear { gameCenter.authenticate() }
        .onChange(of: gameCenter.rankedSearchState) { _, state in
            switch state {
            case .matched:
                guard let ticket = gameCenter.consumeRankedMatch() else { return }
                matchupTask?.cancel()
                matchupTask = Task {
                    let matchup = await gameCenter.rankedMatchup(for: ticket.match, localRating: ladder.rating)
                    guard !Task.isCancelled,
                          route == .gridDuelRankedHub,
                          gameCenter.isConsumedRankedSessionCurrent(ticket.id) else { return }
                    rankedMatchup = matchup
                    // Transfer the actual matched transport into Box Wars.
                    // Previously this ticket was consumed and then discarded,
                    // silently turning a PVP queue result into a local AI game.
                    friendMatch = ticket.match
                    matchMode = .ranked
                    route = .gridDuel
                }
            case .startingAI:
                guard let ticket = gameCenter.consumeRankedAIFallback() else { return }
                rankedMatchup = .aiFallback(localName: GKLocalPlayer.local.displayName, localRating: ladder.rating, profile: ticket.profile)
                friendMatch = nil
                matchMode = .ranked
                route = .gridDuel
            default: break
            }
        }
        .onDisappear {
            matchupTask?.cancel()
            if route != .gridDuel { gameCenter.resetRankedSession() }
        }
        .sheet(isPresented: $showingLeaderboard) { GridDuelLeaderboardSheet(gameCenter: gameCenter, leaderboard: leaderboard) }
        .sheet(isPresented: $showingRanks) { RankedSearchRanksSheet(game: .boxWars, currentTier: ladder.tier) }
        .authenticationSheet(gameCenter)
    }

    @ViewBuilder private var action: some View {
        switch gameCenter.status {
        case .ready:
            switch gameCenter.rankedSearchState {
            case let .searching(stage, elapsed):
                VStack(alignment: .leading, spacing: 8) { ProgressView().tint(Color.accent); Text(stage.playerMessage).font(.headline.weight(.black)); Text("\(ladder.rating) MMR · ±\(stage.acceptedMMRRange) · \(max(0, RankedSearchStage.duration - elapsed)) seconds left").font(.caption).foregroundStyle(.white.opacity(0.6)); Button("CANCEL SEARCH") { gameCenter.cancelRankedMatch() }.buttonStyle(SecondaryButtonStyle()) }.padding(14).modeCard(true)
            case .matched, .startingAI: ProgressView("PREPARING BOX WARS…").tint(Color.accent)
            case let .failed(message): VStack(alignment: .leading) { Text("Couldn’t connect to Game Center.").font(.headline.weight(.black)); Text(message).font(.caption); Button("TRY AGAIN") { gameCenter.startRankedSearch(rating: ladder.rating) }.buttonStyle(SecondaryButtonStyle()) }.padding(14).modeCard()
            case .idle: Button { Task { await ladder.refreshFromGameCenter(); gameCenter.startRankedSearch(rating: ladder.rating) } } label: { Text("QUEUE FOR RANKED").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle())
            }
        case .authenticating: ProgressView("SIGNING IN TO GAME CENTER…")
        case let .unavailable(message): Text(message).foregroundStyle(.red)
        case .idle: EmptyView()
        }
    }
}

struct GridDuelRankDetailsView: View {
    @Binding var route: Route; @ObservedObject var ladder: GridDuelLadderService
    var body: some View { FiveAlivePage(route: $route, back: .gridDuelRankedHub, title: "BOX WARS RANKS", subtitle: "MONTHLY REQUIREMENTS") { ForEach(RankedTier.allCases, id: \.self) { rank in HStack { RankBadge(tier: rank, game: .boxWars, size: 44); Text(rank.rawValue).font(.headline.weight(.black)).foregroundStyle(rank == ladder.tier ? Color.accent : .white); Spacer(); Text(rank.requiredMMR).font(.subheadline.weight(.bold)).foregroundStyle(.white.opacity(0.68)) }.padding(14).modeCard(rank == ladder.tier) } } }
}

struct GridDuelFriendSetupView: View {
    @Binding var route: Route; @Binding var matchMode: OnlineMatchMode; @ObservedObject var gameCenter: GameCenterCoordinator; @Binding var friendMatch: GKMatch?
    @State private var showingMatchmaker = false
    var body: some View { FiveAlivePage(route: $route, back: .gridDuelSetup, title: "BOX WARS FRIEND MATCH", subtitle: "PRIVATE GAME CENTER CHALLENGE") { Text("Invite a friend to solve the same Box Wars grid. Friend matches never affect MMR.").foregroundStyle(.white.opacity(0.7)); Button { showingMatchmaker = true } label: { Label("INVITE FRIEND", systemImage: "person.crop.circle.badge.plus").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle()) }
        .onAppear { gameCenter.authenticate() }.sheet(isPresented: $showingMatchmaker) { FriendMatchmakerView(coordinator: gameCenter) }.onChange(of: gameCenter.match) { _, match in if let match { friendMatch = match; matchMode = .friend; route = .gridDuel } }.authenticationSheet(gameCenter) }
}

struct GridDuelLeaderboardView: View {
    @Binding var route: Route; @ObservedObject var gameCenter: GameCenterCoordinator; @ObservedObject var leaderboard: GridDuelLeaderboardService; @State private var filter: RankedLeaderboardFilter = .global
    var body: some View { FiveAlivePage(route: $route, back: .gridDuelRankedHub, title: "BOX WARS LEADERBOARD", subtitle: RankedLadder.seasonDateRange()) { Picker("Leaderboard filter", selection: $filter) { ForEach(RankedLeaderboardFilter.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented); content }.task { await leaderboard.load(filter: filter) }.onChange(of: filter) { _, value in Task { await leaderboard.load(filter: value) } }.onAppear { if gameCenter.status == .idle { gameCenter.authenticate() } }.authenticationSheet(gameCenter) }
    @ViewBuilder private var content: some View { switch leaderboard.state { case .idle, .loading: ProgressView("LOADING LEADERBOARD…").frame(maxWidth: .infinity).padding(30); case .signInRequired: Text("SIGN IN TO GAME CENTER TO VIEW THE MONTHLY LEADERBOARD.").foregroundStyle(.white.opacity(0.7)); case .emptyFriends: Text("NO FRIENDS RANKED YET").foregroundStyle(.white.opacity(0.7)); case let .failed(message): Text(message).foregroundStyle(.red); case .loaded: ForEach(leaderboard.rows) { row in HStack { Text("#\(row.placement)").monospacedDigit(); RankBadge(tier: row.tier, game: .boxWars, size: 38); VStack(alignment: .leading) { Text(row.displayName).font(.headline.weight(.black)); Text(row.display.title).scoreLabel() }; Spacer(); Text("\(row.mmr) MMR").font(.headline.weight(.black)).monospacedDigit() }.padding(12).modeCard(row.isLocalPlayer) } } }
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
    @ObservedObject var leaderboard: RankedLeaderboardService
    var rankTransition: RankTransition?
    var consumeRankTransition: (UUID) -> Void = { _ in }
    @State private var matchupTask: Task<Void, Never>?
    @State private var showingLeaderboard = false
    @State private var showingRanks = false
    var body: some View {
        FiveAlivePage(route: $route, back: .gameSetup, title: "RANKED", subtitle: "MONTHLY LADDER") {
            RankedHeader(display: rankedLadder.display, game: .fiveAlive, transition: rankTransition, consumeTransition: consumeRankTransition)
            LeaderboardSubmissionStatusCard(status: rankedLadder.leaderboardSubmissionStatus, retry: rankedLadder.retryPendingLeaderboardSubmission)
            Button { showingLeaderboard = true } label: { Label("Leaderboard", systemImage: "list.number").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle())
            Button { showingRanks = true } label: { Label("Ranks & MMR", systemImage: "chart.bar.fill").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle())
            rankedAction
        }
        .onAppear { gameCenter.authenticate() }
        .onChange(of: gameCenter.rankedSearchState) { _, state in
            switch state {
            case .matched:
                guard let ticket = gameCenter.consumeRankedMatch() else { return }
                matchupTask?.cancel()
                matchupTask = Task {
                    let matchup = await gameCenter.rankedMatchup(for: ticket.match, localRating: rankedLadder.rating)
                    guard !Task.isCancelled,
                          route == .rankedHub,
                          gameCenter.isConsumedRankedSessionCurrent(ticket.id) else { return }
                    rankedMatchup = matchup
                    friendMatch = ticket.match
                    difficulty = RankedMatchSetup.difficulty(afterSelecting: difficulty)
                    matchMode = .ranked
                    rankedMatchKind = .pvp
                    rankedAIProfile = nil
                    route = .game
                }
            case .startingAI:
                guard let ticket = gameCenter.consumeRankedAIFallback() else { return }
                friendMatch = nil
                difficulty = RankedMatchSetup.difficulty(afterSelecting: difficulty)
                matchMode = .ranked
                rankedMatchKind = .aiFallback
                rankedAIProfile = ticket.profile
                rankedMatchup = .aiFallback(localName: GKLocalPlayer.local.displayName, localRating: rankedLadder.rating, profile: ticket.profile)
                route = .game
            default:
                break
            }
        }
        .onDisappear {
            matchupTask?.cancel()
            if route != .game { gameCenter.resetRankedSession() }
        }
        .sheet(isPresented: $showingLeaderboard) { RankedLeaderboardSheet(gameCenter: gameCenter, leaderboard: leaderboard) }
        .sheet(isPresented: $showingRanks) { RankedSearchRanksSheet(game: .fiveAlive, currentTier: rankedLadder.tier) }
        .authenticationSheet(gameCenter)
    }
    @ViewBuilder private var rankedAction: some View {
        switch gameCenter.status {
        case .ready:
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
            case .matched:
                ProgressView("Opponent found — preparing your ranked match.").tint(Color.accent)
            case .startingAI:
                ProgressView("No player found — starting a Ranked AI match.").tint(Color.accent)
            case let .failed(message):
                VStack(alignment: .leading, spacing: 8) { Text("Couldn’t connect to Game Center.").font(.headline.weight(.black)); Text(message).font(.caption).foregroundStyle(.white.opacity(0.65)); Button("TRY AGAIN") { gameCenter.startRankedSearch(rating: rankedLadder.rating) }.buttonStyle(SecondaryButtonStyle()) }.padding(14).modeCard()
            case .idle:
                Button { Task { await rankedLadder.refreshFromGameCenter(); gameCenter.startRankedSearch(rating: rankedLadder.rating) } } label: { Text("QUEUE FOR RANKED").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle())
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
    var body: some View { FiveAlivePage(route: $route, back: .rankedHub, title: "RANKS & MMR", subtitle: "MONTHLY REQUIREMENTS") { ForEach(RankedTier.allCases, id: \.self) { tier in HStack(spacing: 12) { RankBadge(tier: tier, game: .fiveAlive, size: 44); Text(tier.rawValue).font(.headline.weight(.black)).foregroundStyle(tier == rankedLadder.tier ? Color.accent : .white); Spacer(); Text(tier.requiredMMR).font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(.white.opacity(0.68)) }.padding(14).modeCard(tier == rankedLadder.tier) }; Text("Wins and losses update your MMR after every ranked match.").font(.caption).foregroundStyle(.white.opacity(0.6)) } }
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
private struct LeaderboardSubmissionStatusCard: View {
    let status: LeaderboardSubmissionStatus
    let retry: () -> Void

    var body: some View {
        switch status {
        case .synced:
            EmptyView()
        case let .pending(score):
            Label("\(score) MMR is waiting to sync with Game Center.", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.72)).padding(12).modeCard()
        case let .failed(score, message):
            VStack(alignment: .leading, spacing: 8) {
                Text(score.map { "Couldn’t submit \($0) MMR to Game Center." } ?? "Couldn’t sync the Game Center leaderboard.")
                    .font(.caption.weight(.bold)).foregroundStyle(.red)
                Text(message).font(.caption).foregroundStyle(.white.opacity(0.7))
                Button("RETRY LEADERBOARD SYNC", action: retry).buttonStyle(SecondaryButtonStyle())
            }.padding(12).modeCard()
        }
    }
}
private struct RankedSearchRanksSheet: View {
    let game: CompetitiveGame
    let currentTier: RankedTier

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(RankedTier.allCases, id: \.self) { tier in
                        HStack {
                            RankBadge(tier: tier, game: game, size: 42)
                            Text(tier.rawValue).font(.headline.weight(.black))
                            Spacer()
                            Text(tier.requiredMMR).font(.subheadline.weight(.bold)).monospacedDigit()
                        }
                        .padding(12).modeCard(tier == currentTier)
                    }
                }.padding()
            }
            .navigationTitle("Ranks & MMR")
        }
        .presentationDetents([.fraction(0.8), .large])
    }
}

private struct GridDuelLeaderboardSheet: View {
    @ObservedObject var gameCenter: GameCenterCoordinator
    @ObservedObject var leaderboard: GridDuelLeaderboardService
    @State private var filter: RankedLeaderboardFilter = .global

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Leaderboard filter", selection: $filter) { ForEach(RankedLeaderboardFilter.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    content
                }.padding()
            }
            .navigationTitle("Leaderboard")
        }
        .task { await leaderboard.load(filter: filter) }
        .onChange(of: filter) { _, value in Task { await leaderboard.load(filter: value) } }
        .onChange(of: gameCenter.status) { _, status in if status == .ready { Task { await leaderboard.load(filter: filter) } } }
        .presentationDetents([.fraction(0.8), .large])
    }

    @ViewBuilder private var content: some View {
        switch leaderboard.state {
        case .idle, .loading: ProgressView("Loading leaderboard…").frame(maxWidth: .infinity).padding(30)
        case .signInRequired: Text("Sign in to Game Center to view the monthly leaderboard.").foregroundStyle(.secondary)
        case .emptyFriends: Text("No friends ranked yet").foregroundStyle(.secondary)
        case let .failed(message): VStack(spacing: 10) { Text(message).foregroundStyle(.red); Button("Try Again") { Task { await leaderboard.load(filter: filter) } }.buttonStyle(SecondaryButtonStyle()) }
        case .loaded: ForEach(leaderboard.rows) { row in
            HStack { Text("#\(row.placement)").monospacedDigit(); RankBadge(tier: row.tier, game: .boxWars, size: 36); VStack(alignment: .leading) { Text(row.displayName).font(.headline.weight(.black)); Text(row.display.title).scoreLabel() }; Spacer(); Text("\(row.mmr) MMR").font(.headline.weight(.black)).monospacedDigit() }.padding(12).modeCard(row.isLocalPlayer)
        }
        }
    }
}

private struct RankedLeaderboardSheet: View {
    @ObservedObject var gameCenter: GameCenterCoordinator
    @ObservedObject var leaderboard: RankedLeaderboardService
    @State private var filter: RankedLeaderboardFilter = .global

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Leaderboard filter", selection: $filter) { ForEach(RankedLeaderboardFilter.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    content
                }.padding()
            }
            .navigationTitle("Leaderboard")
        }
        .task { await leaderboard.load(filter: filter) }
        .onChange(of: filter) { _, value in Task { await leaderboard.load(filter: value) } }
        .onChange(of: gameCenter.status) { _, status in if status == .ready { Task { await leaderboard.load(filter: filter) } } }
        .presentationDetents([.fraction(0.8), .large])
    }

    @ViewBuilder private var content: some View {
        switch leaderboard.state {
        case .idle, .loading: ProgressView("Loading leaderboard…").frame(maxWidth: .infinity).padding(30)
        case .signInRequired: Text("Sign in to Game Center to view the monthly leaderboard.").foregroundStyle(.secondary)
        case .emptyFriends: Text("No friends ranked yet").foregroundStyle(.secondary)
        case let .failed(message): VStack(spacing: 10) { Text(message).foregroundStyle(.red); Button("Try Again") { Task { await leaderboard.load(filter: filter) } }.buttonStyle(SecondaryButtonStyle()) }
        case .loaded:
            if let pinned = leaderboard.pinnedLocalPlayer { row(pinned, pinned: true) }
            ForEach(leaderboard.rows) { row($0, pinned: false) }
        }
    }

    private func row(_ item: RankedLeaderboardRow, pinned: Bool) -> some View {
        HStack { Text("#\(item.placement)").monospacedDigit(); RankBadge(tier: item.tier, game: .fiveAlive, size: 36); Text(item.displayName).font(.headline.weight(.black)); Spacer(); Text("\(item.mmr) MMR").font(.headline.weight(.black)).monospacedDigit() }.padding(12).modeCard(pinned || item.isLocalPlayer)
    }
}
private struct FiveAlivePage<Content: View>: View { @Binding var route: Route; var back: Route = .home; let title: String; let subtitle: String; @ViewBuilder let content: Content; init(route: Binding<Route>, back: Route = .home, title: String, subtitle: String, @ViewBuilder content: () -> Content) { _route = route; self.back = back; self.title = title; self.subtitle = subtitle; self.content = content() }; var body: some View { ScrollView { VStack(alignment: .leading, spacing: 14) { Button { route = back } label: { Image(systemName: "chevron.left").font(.headline.bold()).frame(width: 42, height: 42).background(.white.opacity(0.08)).clipShape(Circle()) }; BrandHeader(compact: false, title: title, tagline: subtitle, markAsset: "FiveAliveMark"); content }.padding(20) }.scrollIndicators(.hidden) } }
private struct PlayModeCard: View { let title: String; let subtitle: String; let icon: String; let action: () -> Void; var body: some View { Button(action: action) { HStack(spacing: 12) { Image(systemName: icon).font(.title3.weight(.black)).foregroundStyle(Color.accent).frame(width: 28); VStack(alignment: .leading, spacing: 2) { Text(title).font(.subheadline.weight(.black)); Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.58)) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.45)) }.padding(14).modeCard() }.buttonStyle(.plain) } }

struct RankedLeaderboardView: View {
    @Binding var route: Route
    @ObservedObject var gameCenter: GameCenterCoordinator
    @ObservedObject var leaderboard: RankedLeaderboardService
    @State private var filter: RankedLeaderboardFilter = .global

    var body: some View {
        FiveAlivePage(route: $route, back: .rankedHub, title: "LEADERBOARD", subtitle: currentMonthDateRange) {
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

    private var currentMonthDateRange: String {
        RankedLadder.seasonDateRange()
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
        HStack(spacing: 10) { Text("#\(row.placement)").font(.subheadline.weight(.black)).monospacedDigit().foregroundStyle(row.isLocalPlayer ? Color.accent : .white.opacity(0.7)).frame(width: 36, alignment: .leading); RankBadge(tier: row.tier, game: .fiveAlive, size: 38); VStack(alignment: .leading, spacing: 2) { Text(row.displayName).font(.subheadline.weight(.black)).lineLimit(1); Text(row.tier.rawValue).scoreLabel().foregroundStyle(row.isLocalPlayer ? Color.accent : .white.opacity(0.48)) }; Spacer(minLength: 2); VStack(alignment: .trailing, spacing: 1) { Text("\(row.mmr)").font(.headline.weight(.black)).monospacedDigit(); Text("MMR").scoreLabel().foregroundStyle(.white.opacity(0.45)) } }.padding(12).background(row.isLocalPlayer || pinned ? Color.accent.opacity(0.14) : .white.opacity(0.045)).overlay(RoundedRectangle(cornerRadius: 12).stroke(row.isLocalPlayer || pinned ? Color.accent.opacity(0.65) : .white.opacity(0.08))).clipShape(RoundedRectangle(cornerRadius: 12))
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
    var game: CompetitiveGame = .fiveAlive
    let size: CGFloat

    var body: some View {
        Image(tier.badgeAssetName(for: game))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(tier.rawValue + " rank badge")
    }
}

private struct RankedHeader: View {
    let display: RankedDisplay
    let game: CompetitiveGame
    let transition: RankTransition?
    let consumeTransition: (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeTransition: RankTransition?
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CURRENT RANK").scoreLabel()
                Text(display.title)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Color.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(revealed ? 1 : 0.72)
                Text("\(display.rating) MMR")
                    .font(.subheadline.weight(.black)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.68))
            }
            Spacer(minLength: 4)
            ZStack {
                Circle().fill(tint.opacity(activeTransition == nil ? 0 : 0.26)).blur(radius: 15)
                    .scaleEffect(revealed ? 1.25 : 0.7)
                RankBadge(tier: display.tier, game: game, size: 94)
                    .scaleEffect(revealed ? 1 : (activeTransition?.kind == .demotion ? 0.82 : 0.55))
            }
        }
        .padding(18)
        .modeCard(true)
        .onAppear(perform: beginTransition)
    }

    private var tint: Color { activeTransition?.kind == .demotion ? .red : Color.accent }
    private func beginTransition() {
        guard let transition, transition.game == game else {
            revealed = true
            return
        }
        consumeTransition(transition.id)
        guard transition.kind != .unchanged else {
            revealed = true
            return
        }
        activeTransition = transition
        if !reduceMotion, transition.kind != .demotion { UIImpactFeedbackGenerator(style: transition.kind == .tierPromotion ? .heavy : .light).impactOccurred() }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: transition.kind == .tierPromotion ? 0.55 : 0.4, dampingFraction: 0.68)) { revealed = true }
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
struct PrimaryButtonStyle: ButtonStyle { let compact: Bool; init(compact: Bool = false) { self.compact = compact }; func makeBody(configuration: Configuration) -> some View { configuration.label.font(.headline.weight(.black)).foregroundStyle(Color.accent).frame(maxWidth: .infinity, minHeight: compact ? 44 : 52).padding(.horizontal, compact ? 13 : 17).background(Color.black.opacity(configuration.isPressed ? 0.22 : 0), in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.accent)).contentShape(RoundedRectangle(cornerRadius: 15)).scaleEffect(configuration.isPressed ? 0.98 : 1) } }
struct SecondaryButtonStyle: ButtonStyle { let compact: Bool; init(compact: Bool = false) { self.compact = compact }; func makeBody(configuration: Configuration) -> some View { configuration.label.font(.headline.weight(.bold)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: compact ? 44 : 52).padding(.horizontal, compact ? 12 : 16).background(.white.opacity(configuration.isPressed ? 0.1 : 0.04), in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.14))).contentShape(RoundedRectangle(cornerRadius: 15)) } }
extension View { func scoreLabel() -> some View { font(.caption2.weight(.black)).tracking(1.4).foregroundStyle(.white.opacity(0.48)) } }
