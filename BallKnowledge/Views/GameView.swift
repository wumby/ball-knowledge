import SwiftUI
import GameKit

struct GameView: View {
    @Binding var route: Route
    private let rankedMatchKind: RankedMatchKind
    private let rankedAIProfile: RankedAIProfile?
    private let isRanked: Bool
    private let hasLiveOpponent: Bool
    @StateObject private var model: GameViewModel
    @State private var showingLeaveConfirmation = false
    init(route: Binding<Route>, difficulty: MatchDifficulty, friendMatch: GKMatch? = nil, friendHostID: String? = nil, matchMode: OnlineMatchMode = .versusAI, rankedMatchKind: RankedMatchKind = .pvp, rankedLadder: RankedLadderService? = nil, rankedAIProfile: RankedAIProfile? = nil) {
        _route = route
        self.rankedMatchKind = rankedMatchKind
        self.rankedAIProfile = rankedAIProfile
        self.isRanked = matchMode == .ranked
        self.hasLiveOpponent = friendMatch != nil
        if let friendMatch {
            let transport = GameKitMatchTransport(match: friendMatch)
            _model = StateObject(wrappedValue: GameViewModel(difficulty: difficulty, transport: transport, friendSession: FriendBattleSession(transport: transport, hostID: friendHostID, difficulty: difficulty), matchMode: matchMode, rankedLadder: rankedLadder))
        } else {
            let botProfile = matchMode == .ranked && rankedMatchKind == .aiFallback ? rankedAIProfile : nil
            _model = StateObject(wrappedValue: GameViewModel(difficulty: difficulty, matchMode: matchMode, rankedLadder: rankedLadder, rankedAIProfile: botProfile))
        }
    }
    var body: some View {
        Group { switch model.phase { case .matching: if let error = model.loadError { ContentUnavailableView("NBA ARCHIVE UNAVAILABLE", systemImage: "exclamationmark.triangle", description: Text(error)).foregroundStyle(.white) } else { VStack(spacing: 14) { ProgressView(hasLiveOpponent ? "WAITING FOR OPPONENT…" : "PREPARING MATCH…").tint(Color.accent); if let message = model.connectionMessage { Text(message).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center) } } }; case .revealing: TeamRouletteView(model: model); case .auction: AuctionView(model: model); case .bidResult: BidResultView(model: model); case .selecting: PlayerSelectionView(model: model); case .draftReveal: DraftRevealView(model: model); case .reportLoading: FinalReportLoadingView(); case .results: ResultsView(model: model, route: $route, rankedMatchKind: rankedMatchKind, rankedAIProfile: rankedAIProfile) } }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                HStack {
                    Button { showingLeaveConfirmation = true } label: {
                        Label("FORFEIT", systemImage: "flag.fill")
                            .scoreLabel()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.45))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    if isRanked { Text(rankedLabel).scoreLabel().foregroundStyle(Color.accent).padding(.horizontal, 10).padding(.vertical, 5).background(.black.opacity(0.45)).clipShape(Capsule()) }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }
            .alert("Forfeit this match?", isPresented: $showingLeaveConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Forfeit Match", role: .destructive) {
                    model.leaveMatch()
                    route = .home
                }
            } message: {
                Text("Your current match progress will be lost.")
            }
            .task { await model.start() }
    }
    private var rankedLabel: String { rankedMatchKind == .aiFallback ? "\(rankedMatchKind.label) · \(rankedAIProfile?.tier.rawValue ?? "AI")" : rankedMatchKind.label }
}

struct FinalReportLoadingView: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView().controlSize(.large).tint(Color.accent)
            Text("CALCULATING FINAL REPORT…").font(.title3.weight(.black)).foregroundStyle(Color.accent)
            Text("Finding the best lineup from each won team-year.").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.62)).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct BidResultView: View {
    @ObservedObject var model: GameViewModel
    private var playerWon: Bool { model.pendingWinner == .player }
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(model.isForcedAward ? "ROSTER FULL" : (playerWon ? "AUCTION WON" : "AUCTION LOST")).scoreLabel().foregroundStyle(playerWon ? Color.accent : .white.opacity(0.55))
            Image(systemName: model.isForcedAward ? "forward.fill" : (playerWon ? "trophy.fill" : "gavel.fill")).font(.system(size: 54)).foregroundStyle(playerWon ? Color.accent : .white.opacity(0.55))
            Text(model.isForcedAward ? (playerWon ? "TEAM AWARDED TO YOU" : "TEAM AWARDED TO OPPONENT") : (playerWon ? "YOU WON THE BID" : "OPPONENT WON THE BID")).font(.system(size: 32, weight: .black, design: .rounded)).multilineTextAlignment(.center)
            if let team = model.engine?.current { VStack(spacing: 12) { TeamLogo(team: team.team, season: team.season, size: 58); Text(team.team).font(.title.weight(.black)); Text(team.season).font(.headline).foregroundStyle(.white.opacity(0.6)); if model.isForcedAward { Text("BIDDING VOID · ROSTER FULL").scoreLabel().padding(.top, 4) } else { HStack(spacing: 12) { bidScore("YOU", bid: model.playerBid, won: playerWon); Text("VS").font(.caption.weight(.black)).foregroundStyle(.white.opacity(0.45)); bidScore(model.opponentDisplayName.uppercased(), bid: model.opponentBid, won: !playerWon) } } }.padding(22).frame(maxWidth: .infinity).background(.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 22)) }
            Text(playerWon ? "Your player selection is coming up." : "Opponent pick incoming.").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.62)).multilineTextAlignment(.center)
            Spacer()
        }.padding(24).task { try? await Task.sleep(for: .milliseconds(2600)); model.continueAfterBid() }
    }
    private func bidScore(_ label: String, bid: Int, won: Bool) -> some View { VStack(spacing: 3) { Text(label).scoreLabel().foregroundStyle(won ? Color.accent : .white.opacity(0.45)); Text("$\(bid)M").font(.title2.weight(.black)).monospacedDigit().foregroundStyle(won ? Color.accent : .white); Text(won ? "WINNING BID" : "OUTBID").font(.caption2.weight(.black)).foregroundStyle(won ? Color.accent : .white.opacity(0.35)) }.frame(maxWidth: .infinity).padding(.vertical, 8).background(won ? Color.accent.opacity(0.12) : .white.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 12)) }
}

struct DraftRevealView: View {
    @ObservedObject var model: GameViewModel
    private var playerWon: Bool { model.revealedPlayer.map { player in model.engine?.playerRoster.contains(where: { $0.id == player.id }) ?? false } ?? false }
    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 14)
            Text(playerWon ? "YOU DRAFTED" : "OPPONENT DRAFTED").scoreLabel().foregroundStyle(playerWon ? Color.accent : .white.opacity(0.55))
            if let drafted = model.revealedPlayer {
                VStack(spacing: 12) {
                    HStack(spacing: 14) { PlayerPortrait(player: drafted.season, size: 96); TeamLogo(team: drafted.season.team, season: drafted.season.season, size: 58) }
                    Text(drafted.season.playerName).font(.system(size: 44, weight: .black, design: .rounded)).minimumScaleFactor(0.58).multilineTextAlignment(.center)
                    Text("\(drafted.season.position) · \(drafted.season.team) \(drafted.season.season)").font(.headline.weight(.bold)).foregroundStyle(Color.accent)
                    if model.difficulty == .easy {
                        VStack(spacing: 3) {
                            Text("\(drafted.season.points, specifier: "%.1f") PPG · \(drafted.season.rebounds, specifier: "%.1f") REB · \(drafted.season.assists, specifier: "%.1f") AST")
                            Text("\(drafted.season.steals, specifier: "%.1f") STL · \(drafted.season.blocks, specifier: "%.1f") BLK")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                    }
                }.padding(28).frame(maxWidth: .infinity).background(.white.opacity(0.08)).overlay(RoundedRectangle(cornerRadius: 28).stroke(playerWon ? Color.accent.opacity(0.55) : .white.opacity(0.16), lineWidth: 2)).clipShape(RoundedRectangle(cornerRadius: 28))
            }
            DraftMatchupBoard(playerRoster: model.engine?.playerRoster ?? [], opponentRoster: model.engine?.opponentRoster ?? [], opponentName: model.opponentDisplayName)
            Spacer()
        }.padding(20).task { try? await Task.sleep(for: .milliseconds(4200)); model.finishDraftReveal() }
    }
}

struct DraftMatchupBoard: View {
    let playerRoster: [DraftedPlayer]
    let opponentRoster: [DraftedPlayer]
    let opponentName: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            rosterColumn("YOUR TEAM", roster: playerRoster, accent: true)
            rosterColumn(opponentName.uppercased(), roster: opponentRoster, accent: false)
        }.padding(14).background(.white.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 18))
    }
    private func rosterColumn(_ title: String, roster: [DraftedPlayer], accent: Bool) -> some View {
        let slots = TeamSimulator.currentTeamSlots(for: roster)
        return VStack(alignment: .leading, spacing: 5) {
            Text(title).scoreLabel().foregroundStyle(accent ? Color.accent : .white.opacity(0.48))
            ForEach(slots) { slot in
                if let player = slot.player {
                    HStack(spacing: 6) { Text(slot.position).font(.caption.weight(.black)).foregroundStyle(accent ? Color.accent : .white.opacity(0.55)).frame(width: 20, alignment: .leading); Text(player.season.playerName).font(.subheadline.weight(.black)).lineLimit(1).minimumScaleFactor(0.76) }
                } else {
                    HStack(spacing: 6) { Text(slot.position).font(.caption.weight(.black)).foregroundStyle(.white.opacity(0.28)).frame(width: 20, alignment: .leading); Text("OPEN SLOT").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.28)) }
                }
        }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TeamRouletteView: View {
    @ObservedObject var model: GameViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedTeam: TeamSeason?
    @State private var offerRevealed = false
    @State private var scanLineAtBottom = false
    @State private var scanTarget = 0

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 700
            VStack(spacing: compact ? 14 : 18) {
                Spacer(minLength: compact ? 10 : 22)
                Text(offerRevealed ? "ASSET IDENTIFIED" : "TEAM SELECTION")
                    .font(.system(size: compact ? 28 : 32, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(offerRevealed ? "Cleared for auction review." : "Running archive and roster intake scan.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)

                dossierCard(compact: compact)
                    .frame(maxHeight: compact ? 390 : 460)

                Text(offerRevealed ? "ROSTER INTAKE COMPLETE" : "SCANNING ARCHIVE")
                    .scoreLabel()
                    .foregroundStyle(offerRevealed ? Color.accent : .white.opacity(0.48))
                Spacer(minLength: compact ? 8 : 20)
            }
            .padding(.horizontal, 24)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .task { await spin() }
    }

    private func dossierCard(compact: Bool) -> some View {
        ZStack {
            dossierGrid
            if offerRevealed, let team = displayedTeam {
                revealedDossier(for: team, compact: compact)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
            } else {
                scanningDossier
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.36))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(offerRevealed ? Color.accent.opacity(0.78) : .white.opacity(0.18), lineWidth: offerRevealed ? 2 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .shadow(color: Color.accent.opacity(offerRevealed ? 0.36 : 0.12), radius: offerRevealed ? 20 : 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(offerRevealed && displayedTeam != nil ? "War Room dossier. \(TeamBrand.name(for: displayedTeam!.team)), \(displayedTeam!.season). Roster intake, 5 players." : "War Room dossier scanning incoming asset.")
    }

    /// The actual offer is deliberately first, so the reticle can visibly lock
    /// onto it after cycling through decoy archive records. The scan reveals
    /// only the team-year metadata; roster and player details remain hidden.
    private var scoutingTeams: [TeamSeason] {
        guard let engine = model.engine, let current = engine.current else { return [] }
        let decoys = engine.teams.filter { $0.id != current.id }.prefix(4)
        return [current] + decoys
    }

    private var dossierGrid: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 24
            Path { path in
                stride(from: CGFloat(0), through: proxy.size.width, by: spacing).forEach { x in
                    path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                }
                stride(from: CGFloat(0), through: proxy.size.height, by: spacing).forEach { y in
                    path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
            }
            .stroke(Color.accent.opacity(0.11), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
    }

    private var scanningDossier: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                Text("SCANNING FIVE ARCHIVE SIGNALS")
                    .scoreLabel()
                    .foregroundStyle(.white.opacity(0.58))
                VStack(spacing: 14) {
                    HStack(spacing: 26) {
                        scoutTarget(at: 0, size: proxy.size.width < 340 ? 40 : 48)
                        scoutTarget(at: 1, size: proxy.size.width < 340 ? 40 : 48)
                    }
                    scoutTarget(at: 2, size: proxy.size.width < 340 ? 46 : 56)
                    HStack(spacing: 26) {
                        scoutTarget(at: 3, size: proxy.size.width < 340 ? 40 : 48)
                        scoutTarget(at: 4, size: proxy.size.width < 340 ? 40 : 48)
                    }
                }
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, Color.accent.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 2)
                    .shadow(color: Color.accent, radius: 8)
                    .offset(y: scanLineAtBottom ? proxy.size.height * 0.34 : -proxy.size.height * 0.34)
                Text(scanTarget == 0 ? "TARGET ACQUISITION…" : "CROSS-REFERENCING ARCHIVE…")
                    .scoreLabel()
                    .foregroundStyle(Color.accent.opacity(0.84))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func scoutTarget(at index: Int, size: CGFloat) -> some View {
        if scoutingTeams.indices.contains(index) {
            let team = scoutingTeams[index]
            VStack(spacing: 4) {
                ZStack {
                    TeamLogo(team: team.team, season: team.season, size: size)
                    if scanTarget == index {
                        Image(systemName: "scope")
                            .font(.system(size: size + 16, weight: .light))
                            .foregroundStyle(Color.accent)
                            .shadow(color: Color.accent, radius: 9)
                            .transition(.opacity)
                    }
                }
                .frame(width: size + 54, height: size + 20)

                VStack(spacing: 1) {
                    Text(TeamBrand.name(for: team.team))
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .multilineTextAlignment(.center)
                        .frame(height: 26, alignment: .top)
                    Text(team.season)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.accent)
                        .lineLimit(1)
                }
                .frame(width: size + 54)
            }
            .opacity(scanTarget == index ? 1 : 0.42)
            .scaleEffect(scanTarget == index ? 1.05 : 0.92)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(TeamBrand.name(for: team.team)), \(team.season)\(scanTarget == index ? ", current scan target" : "")")
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.72), value: scanTarget)
        } else {
            Color.clear.frame(width: size + 54, height: size + 78)
        }
    }

    private func revealedDossier(for team: TeamSeason, compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 14) {
            HStack {
                Text("ASSET CLEARED").scoreLabel().foregroundStyle(Color.accent)
                Spacer()
                Text("INTAKE // 05").scoreLabel().foregroundStyle(.white.opacity(0.48))
            }
            TeamLogo(team: team.team, season: team.season, size: compact ? 94 : 112)
                .shadow(color: Color.accent.opacity(0.52), radius: 20)
            Text(TeamBrand.name(for: team.team))
                .font(.system(size: compact ? 29 : 33, weight: .black, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.66)
                .multilineTextAlignment(.center)
            Text(team.season)
                .font(.system(size: compact ? 38 : 46, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.accent)
            Divider().overlay(.white.opacity(0.16))
            Text("ROSTER INTAKE · 5 PLAYERS")
                .scoreLabel()
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(compact ? 22 : 28)
    }

    private func spin() async {
        guard let current = model.engine?.current else { return }
        if !reduceMotion {
            withAnimation(.linear(duration: 0.72).repeatForever(autoreverses: true)) { scanLineAtBottom = true }
        }
        // Two passes across five targets create a deliberate War Room search,
        // then the reticle makes a final lock on the incoming team-year.
        for step in 0..<10 {
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.72)) {
                scanTarget = step % max(scoutingTeams.count, 1)
            }
            try? await Task.sleep(for: .milliseconds(330))
        }
        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7)) { scanTarget = 0 }
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.72)) {
            displayedTeam = current
            offerRevealed = true
        }
        try? await Task.sleep(for: .milliseconds(950))
        model.finishReveal()
    }
}

struct MatchHeader: View {
    @ObservedObject var model: GameViewModel
    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 28) {
                score("YOUR CAP", "$\(model.engine?.playerBudget ?? 0)M", .leading)
                score("\(model.opponentDisplayName.uppercased()) CAP", "$\(model.engine?.opponentBudget ?? 0)M", .trailing)
            }
            timer
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
    private func score(_ title: String, _ value: String, _ alignment: HorizontalAlignment) -> some View { VStack(alignment: alignment, spacing: 2) { Text(title).scoreLabel(); Text(value).font(.subheadline.weight(.black)).monospacedDigit() } }
    private var timer: some View {
        Text("0:\(String(format: "%02d", model.seconds))")
            .font(.headline.monospacedDigit().weight(.black))
            .foregroundStyle(model.seconds <= 5 ? .red : Color.accent)
    }
}

struct AuctionView: View {
    @ObservedObject var model: GameViewModel
    @State private var selectedPosition: String?
    @State private var isCurrentTeamExpanded = false
    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 700
            VStack(spacing: compact ? 12 : 18) {
                MatchHeader(model: model)
                if let team = model.engine?.current {
                    AuctionOfferCard(team: team, difficulty: model.difficulty, compact: compact)
                    if model.difficulty == .ballKnowledge {
                        CurrentTeamBoard(roster: model.engine?.playerRoster ?? [])
                    } else {
                        ExpandableCurrentTeamPanel(
                            roster: model.engine?.playerRoster ?? [],
                            isExpanded: $isCurrentTeamExpanded
                        )
                        AvailablePlayers(team: team, displayPlayers: model.engine?.randomizedDisplayOrder(for: team.players) ?? team.players, difficulty: model.difficulty, compact: compact, selectedPosition: $selectedPosition)
                    }
                }
                Spacer(minLength: 0)
                if !model.toast.isEmpty { Text(model.toast).font(.caption.weight(.black)).foregroundStyle(Color.accent).lineLimit(1) }
            }
            .padding(.horizontal, 20).padding(.top, compact ? 8 : 14)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { BidActionBar(model: model) }
    }
}

struct CurrentTeamBoard: View {
    let roster: [DraftedPlayer]
    private var slots: [CurrentTeamSlot] { TeamSimulator.currentTeamSlots(for: roster) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("YOUR CURRENT TEAM").scoreLabel().foregroundStyle(Color.accent)
                    Text("SCOUTING LOCKED").font(.caption2.weight(.black)).foregroundStyle(.white.opacity(0.42))
                }
                Spacer()
                Text("\(roster.count) / 5 PICKED").scoreLabel().foregroundStyle(.white.opacity(0.72))
            }

            Text("Only drafted player identities and assigned positions are visible.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.55))

            VStack(spacing: 9) {
                ForEach(slots) { slot in
                    currentTeamRow(slot)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(16)
        .background(.white.opacity(0.045))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.10)))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .layoutPriority(1)
    }

    private func currentTeamRow(_ slot: CurrentTeamSlot) -> some View {
        HStack(spacing: 14) {
            Text(slot.position)
                .font(.title3.weight(.black))
                .foregroundStyle(slot.player == nil ? .white.opacity(0.35) : Color.accent)
                .frame(width: 42, alignment: .leading)
            Rectangle().fill(.white.opacity(0.10)).frame(width: 1)
            Text(slot.player?.season.playerName ?? "NEED")
                .font(.title3.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(slot.player == nil ? .white.opacity(0.34) : .white)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 14)
        .background(slot.player == nil ? .white.opacity(0.035) : Color.accent.opacity(0.11))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(slot.player == nil ? .white.opacity(0.07) : Color.accent.opacity(0.32)))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct AuctionOfferCard: View {
    let team: TeamSeason; let difficulty: MatchDifficulty; let compact: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("UP FOR AUCTION").scoreLabel().foregroundStyle(Color.accent)
            HStack(alignment: .center, spacing: 11) {
                TeamLogo(team: team.team, season: team.season, size: compact ? 44 : 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(TeamBrand.name(for: team.team))
                        .font(.system(size: compact ? 22 : 26, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(team.season)
                        .font(.system(size: compact ? 18 : 21, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.accent)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
            }
        }.padding(compact ? 12 : 14).background(.white.opacity(0.075)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.1))).clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct AvailablePlayers: View {
    let team: TeamSeason; let displayPlayers: [SeasonRecord]; let difficulty: MatchDifficulty; let compact: Bool
    @Binding var selectedPosition: String?
    private var players: [SeasonRecord] { displayPlayers.filter { selectedPosition == nil || $0.position == selectedPosition } }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(difficulty == .ballKnowledge ? "SCOUTING LOCKED" : "AVAILABLE PLAYERS").scoreLabel(); Spacer(); if difficulty != .ballKnowledge { Text("SCROLL").scoreLabel() } }
            if difficulty == .ballKnowledge {
                Text("Only the team and year are available before the auction.").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.55)).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            } else {
                PositionFilterBar(positions: team.players.map(\.position), selection: $selectedPosition)
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 11) {
                        ForEach(players) { player in ScoutingPlayerCard(player: player, showStats: difficulty == .easy) }
                    }
                }
                .frame(maxHeight: .infinity)
                .layoutPriority(1)
            }
        }.frame(maxHeight: .infinity, alignment: .top).layoutPriority(1).padding(.horizontal, 13).padding(.vertical, 10).background(.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct ScoutingPlayerCard: View {
    let player: SeasonRecord
    let showStats: Bool
    var body: some View {
        Group {
            if showStats {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 10) {
                        PlayerPortrait(player: player, size: 34, context: .draftSelection)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.playerName).font(.headline.weight(.black)).lineLimit(1).minimumScaleFactor(0.78).layoutPriority(1)
                            Text(player.position).font(.caption2.weight(.black)).foregroundStyle(Color.accent)
                        }
                        Spacer(minLength: 0)
                    }
                    RatingInputsLine(player: player)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
            } else {
                HStack(spacing: 10) {
                    PlayerPortrait(player: player, size: 34, context: .draftSelection)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.playerName).font(.headline.weight(.black)).lineLimit(1).minimumScaleFactor(0.78).layoutPriority(1)
                        Text(player.position).font(.caption2.weight(.black)).foregroundStyle(Color.accent)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: showStats ? 92 : 64, alignment: .topLeading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.white.opacity(0.09))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.10)))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct ScoutStat: View {
    let label: String; let value: Double
    init(_ label: String, _ value: Double) { self.label = label; self.value = value }
    var body: some View { VStack(spacing: 1) { Text(value, format: .number.precision(.fractionLength(1))).font(.caption2.weight(.black)).monospacedDigit().foregroundStyle(Color.accent); Text(label).font(.system(size: 7, weight: .black)).foregroundStyle(.white.opacity(0.46)) } }
}

struct BidActionBar: View {
    @ObservedObject var model: GameViewModel
    var body: some View {
        VStack(spacing: 10) {
            HStack { VStack(alignment: .leading, spacing: 1) { Text("YOUR BID").scoreLabel(); Text("$\(model.bid)M").font(.title2.weight(.black)).monospacedDigit() }; Spacer(); VStack(alignment: .trailing, spacing: 1) { Text("BANKROLL $\(model.engine?.playerBudget ?? 0)M").scoreLabel(); Text("0:\(String(format: "%02d", model.seconds))").font(.headline.monospacedDigit().weight(.black)).foregroundStyle(model.seconds <= 5 ? .red : .white) } }
            if let bankroll = model.engine?.playerBudget, bankroll > 0 {
                Slider(value: Binding(get: { Double(model.bid) }, set: { model.bid = Int($0.rounded()) }), in: 0...Double(bankroll), step: 1).tint(Color.accent)
            } else {
                HStack(spacing: 8) { Image(systemName: "banknote").foregroundStyle(.white.opacity(0.45)); Text("NO BANKROLL REMAINING — BID $0M").font(.caption.weight(.black)).foregroundStyle(.white.opacity(0.55)); Spacer() }.frame(height: 30)
            }
            HStack(spacing: 8) { bidButton("−10", -10); bidButton("−1", -1); bidButton("+1", 1); bidButton("+10", 10); Button("ALL") { model.bid = model.engine?.playerBudget ?? 0 }.buttonStyle(CompactBidStyle(accent: true)) }
            Button("LOCK BID") { model.submitBid() }.buttonStyle(PrimaryButtonStyle(compact: true))
        }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8).background(.ultraThinMaterial).overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
    }
    private func bidButton(_ title: String, _ amount: Int) -> some View { Button(title) { model.adjustBid(by: amount) }.buttonStyle(CompactBidStyle()) }
}

struct CompactBidStyle: ButtonStyle { let accent: Bool; init(accent: Bool = false) { self.accent = accent }; func makeBody(configuration: Configuration) -> some View { configuration.label.font(.caption.weight(.black)).foregroundStyle(accent ? .black : .white).frame(maxWidth: .infinity, minHeight: 38).background(accent ? Color.accent : .white.opacity(configuration.isPressed ? 0.16 : 0.08)).clipShape(RoundedRectangle(cornerRadius: 10)) } }

struct PlayerSelectionView: View {
    @ObservedObject var model: GameViewModel
    @State private var selectedPosition: String?
    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 700
            VStack(spacing: compact ? 8 : 12) {
                MatchHeader(model: model)
                if let team = model.engine?.current {
                    HStack { TeamLogo(team: team.team, season: team.season, size: 42); VStack(alignment: .leading, spacing: 2) { Text("YOU WON THE AUCTION").scoreLabel().foregroundStyle(Color.accent); Text("\(team.team) · \(team.season)").font(compact ? .title3.weight(.black) : .title2.weight(.black)) }; Spacer() }.padding(.vertical, 6)
                    HStack {
                        Text("SELECT A PLAYER").scoreLabel()
                        Spacer()
                        Text("0:\(String(format: "%02d", model.seconds))")
                            .font(.headline.monospacedDigit().weight(.black))
                            .foregroundStyle(model.seconds <= 5 ? .red : Color.accent)
                    }
                    RosterNeedsStrip(roster: model.engine?.playerRoster ?? [])
                    PositionFilterBar(positions: team.players.map(\.position), selection: $selectedPosition)
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 12) {
                            ForEach((model.engine?.randomizedDisplayOrder(for: team.players) ?? team.players).filter { !(model.engine?.isPlayerSelected($0) ?? false) && (selectedPosition == nil || $0.position == selectedPosition) }) { player in PlayerPickRow(player: player, difficulty: model.difficulty) { model.selectPlayer(player) } }
                        }
                    }
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 20).padding(.vertical, compact ? 8 : 14).frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }
}

struct RosterNeedsStrip: View {
    let roster: [DraftedPlayer]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text("YOUR CURRENT TEAM").scoreLabel().foregroundStyle(Color.accent); Spacer(); Text("\(roster.count) / 5 PICKED").scoreLabel() }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(TeamSimulator.currentTeamSlots(for: roster)) { slot in
                        let player = slot.player
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slot.position).scoreLabel().foregroundStyle(player == nil ? .white.opacity(0.38) : Color.accent)
                            Text(player?.season.playerName ?? "NEED").font(.caption.weight(.black)).lineLimit(1).foregroundStyle(player == nil ? .white.opacity(0.42) : .white)
                        }
                        .frame(width: 88, alignment: .leading).padding(9)
                        .background(player == nil ? .white.opacity(0.045) : Color.accent.opacity(0.11))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(player == nil ? .white.opacity(0.08) : Color.accent.opacity(0.35)))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding(10).background(.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct PlayerPickRow: View {
    let player: SeasonRecord; let difficulty: MatchDifficulty; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                if difficulty == .easy {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 10) {
                            PlayerPortrait(player: player, size: 34, context: .draftSelection)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.playerName).font(.headline.weight(.black)).lineLimit(1).minimumScaleFactor(0.78).layoutPriority(1)
                                Text(player.position).font(.caption2.weight(.black)).foregroundStyle(Color.accent)
                            }
                            Spacer(minLength: 4)
                            draftLabel
                        }
                        RatingInputsLine(player: player)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                } else {
                    HStack(spacing: 10) {
                        PlayerPortrait(player: player, size: 34, context: .draftSelection)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.playerName).font(.headline.weight(.black)).lineLimit(1).minimumScaleFactor(0.78).layoutPriority(1)
                            Text(player.position).font(.caption2.weight(.black)).foregroundStyle(Color.accent)
                        }
                        Spacer(minLength: 0)
                        draftLabel
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: difficulty == .easy ? 92 : 64, alignment: .topLeading)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.white.opacity(0.09))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.10)))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    private var draftLabel: some View {
        HStack(spacing: 4) {
            Text("DRAFT")
            Image(systemName: "checkmark")
        }
            .font(.caption.weight(.black))
            .foregroundStyle(.black)
            .padding(.horizontal, 11)
            .frame(minHeight: 34)
            .background(Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct RatingInputsLine: View {
    let player: SeasonRecord
    var body: some View {
        HStack(spacing: 5) {
            ScoutStat("PTS", player.points).frame(maxWidth: .infinity)
            ScoutStat("REB", player.rebounds).frame(maxWidth: .infinity)
            ScoutStat("AST", player.assists).frame(maxWidth: .infinity)
            ScoutStat("STL", player.steals).frame(maxWidth: .infinity)
            ScoutStat("BLK", player.blocks).frame(maxWidth: .infinity)
        }.frame(maxWidth: .infinity)
    }
}

struct PositionFilterBar: View {
    let positions: [String]
    @Binding var selection: String?
    private var availablePositions: [String] { ["PG", "SG", "SF", "PF", "C"].filter(positions.contains) }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                filterButton("ALL", value: nil)
                ForEach(availablePositions, id: \.self) { position in filterButton(position, value: position) }
            }
        }
    }
    private func filterButton(_ title: String, value: String?) -> some View {
        Button { selection = value } label: { Text(title).font(.caption2.weight(.black)).foregroundStyle(selection == value ? .black : .white.opacity(0.75)).padding(.horizontal, 12).frame(minHeight: 30).background(selection == value ? Color.accent : .white.opacity(0.08)).clipShape(Capsule()) }
    }
}

struct CurrentTeamPanelState: Equatable {
    let isExpanded: Bool
    let slots: [CurrentTeamSlot]

    init(roster: [DraftedPlayer], isExpanded: Bool) {
        self.isExpanded = isExpanded
        self.slots = TeamSimulator.currentTeamSlots(for: roster)
    }
}

struct ExpandableCurrentTeamPanel: View {
    let roster: [DraftedPlayer]
    @Binding var isExpanded: Bool

    private var state: CurrentTeamPanelState {
        CurrentTeamPanelState(roster: roster, isExpanded: isExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text("YOUR CURRENT TEAM")
                        .scoreLabel()
                        .foregroundStyle(Color.accent)
                    Spacer(minLength: 0)
                    Text("\(roster.count) / 5 PICKED")
                        .scoreLabel()
                        .foregroundStyle(.white.opacity(0.72))
                    Image(systemName: state.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 16)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if state.isExpanded {
                VStack(spacing: 7) {
                    ForEach(state.slots) { slot in
                        HStack(spacing: 10) {
                            Text(slot.position)
                                .scoreLabel()
                                .foregroundStyle(slot.player == nil ? .white.opacity(0.38) : Color.accent)
                                .frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(slot.player?.season.playerName ?? "OPEN SLOT")
                                    .font(.caption.weight(.black))
                                    .lineLimit(1)
                                    .foregroundStyle(slot.player == nil ? .white.opacity(0.42) : .white)
                                if let player = slot.player {
                                    Text(player.season.season)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .padding(.horizontal, 10)
                        .background(slot.player == nil ? .white.opacity(0.035) : Color.accent.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(.white.opacity(0.045))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .animation(.easeInOut(duration: 0.22), value: state.isExpanded)
    }
}

struct ResultsView: View {
    @ObservedObject var model: GameViewModel; @Binding var route: Route
    var rankedMatchKind: RankedMatchKind = .pvp
    var rankedAIProfile: RankedAIProfile?
    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 700
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: compact ? 14 : 18) {
                        Text("FINAL MATCHUP").scoreLabel().foregroundStyle(Color.accent).padding(.top, compact ? 10 : 18)
                        Text(model.result).font(.system(size: compact ? 34 : 42, weight: .black, design: .rounded)).minimumScaleFactor(0.7).multilineTextAlignment(.center)
                        if let ranked = model.rankedMatchResult { rankedResultCard(ranked) }
                        finalRatingScoreboard(model: model)
                        FinalMatchupBoard(player: model.engine?.playerRoster ?? [], opponent: model.engine?.opponentRoster ?? [], opponentName: model.opponentDisplayName, playerAssignments: model.playerRatingBreakdown.assignments, opponentAssignments: model.opponentRatingBreakdown.assignments)
                        lineupScoreboard(model: model)
                        VStack(spacing: 6) {
                            Text("STAT BATTLE").scoreLabel().frame(maxWidth: .infinity, alignment: .leading)
                            StatBattleRow(label: "POINTS", player: model.playerStats.points, opponent: model.opponentStats.points)
                            StatBattleRow(label: "REBOUNDS", player: model.playerStats.rebounds, opponent: model.opponentStats.rebounds)
                            StatBattleRow(label: "ASSISTS", player: model.playerStats.assists, opponent: model.opponentStats.assists)
                            StatBattleRow(label: "STEALS", player: model.playerStats.steals, opponent: model.opponentStats.steals)
                            StatBattleRow(label: "BLOCKS", player: model.playerStats.blocks, opponent: model.opponentStats.blocks)
                        }
                        .padding(13)
                        .background(.white.opacity(0.065))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.10)))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        BestPossibleTeamCard(player: model.bestPossibleTeam, opponent: model.bestPossibleOpponentTeam, opponentName: model.opponentDisplayName)
                    }.padding(.horizontal, 20).padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                VStack(spacing: 8) { Button("PLAY AGAIN") { Task { await model.start() } }.buttonStyle(PrimaryButtonStyle(compact: true)); Button("HOME") { route = .home }.buttonStyle(SecondaryButtonStyle(compact: true)) }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8).background(.ultraThinMaterial)
            }.frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
    private func rankedResultCard(_ result: RankedMatchResult) -> some View {
        HStack(spacing: 12) {
            RankBadge(tier: result.tier, size: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.tier.rawValue).scoreLabel().foregroundStyle(Color.accent)
                Text("\(result.ratingBefore) → \(result.ratingAfter) MMR")
                    .font(.headline.weight(.black))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(result.delta >= 0 ? "+\(result.delta) MMR" : "\(result.delta) MMR")
                    .font(.headline.weight(.black)).monospacedDigit().foregroundStyle(result.delta >= 0 ? Color.accent : .red)
                Text("\(rankedResultLabel) · \(result.didWin ? "WIN" : "LOSS")").scoreLabel().foregroundStyle(.white.opacity(0.56))
            }
        }
        .padding(14).background(Color.accent.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.accent.opacity(0.5)))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    private var rankedResultLabel: String { rankedMatchKind == .aiFallback ? "\(rankedMatchKind.label) · \(rankedAIProfile?.tier.rawValue ?? "AI")" : rankedMatchKind.label }
    private func finalRatingScoreboard(model: GameViewModel) -> some View {
        let playerWon = model.playerRatingBreakdown.finalRating > model.opponentRatingBreakdown.finalRating
        let opponentWon = model.opponentRatingBreakdown.finalRating > model.playerRatingBreakdown.finalRating
        return HStack(spacing: 12) {
            finalRatingCard("YOUR TEAM", rating: model.playerRatingBreakdown.finalRating, highlighted: playerWon)
            Text("VS").font(.caption.weight(.black)).foregroundStyle(.white.opacity(0.45))
            finalRatingCard(model.opponentDisplayName.uppercased(), rating: model.opponentRatingBreakdown.finalRating, highlighted: opponentWon)
        }
        .padding(12)
        .background(.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    private func finalRatingCard(_ title: String, rating: Double, highlighted: Bool) -> some View {
        VStack(spacing: 3) {
            Text(title).scoreLabel().foregroundStyle(highlighted ? Color.accent : .white.opacity(0.55))
            Text(rating, format: .number.precision(.fractionLength(1)))
                .font(.system(size: 30, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(highlighted ? Color.accent : .white)
            Text("FINAL TEAM RATING").font(.caption2.weight(.black)).foregroundStyle(.white.opacity(0.46))
        }
        .frame(maxWidth: .infinity)
    }
    private func lineupScoreboard(model: GameViewModel) -> some View { HStack(spacing: 10) { lineupCard("YOUR TEAM", rating: model.playerRatingBreakdown, accent: model.playerRatingBreakdown.finalRating > model.opponentRatingBreakdown.finalRating); Text("VS").font(.caption.weight(.black)).foregroundStyle(.white.opacity(0.45)); lineupCard(model.opponentDisplayName.uppercased(), rating: model.opponentRatingBreakdown, accent: model.opponentRatingBreakdown.finalRating > model.playerRatingBreakdown.finalRating) }.padding(12).background(.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 16)) }
    private func lineupCard(_ title: String, rating: LineupRatingBreakdown, accent: Bool) -> some View { VStack(spacing: 7) { Text(title).scoreLabel().foregroundStyle(accent ? Color.accent : .white.opacity(0.55)); ratingMath("PLAYER TOTAL", String(format: "%.1f", rating.playerTotal), color: .white); ratingMath("POSITION FIT", "\(rating.positionPenalty)", color: rating.positionPenalty < 0 ? .orange : Color.accent, detail: rating.missingPositions.isEmpty ? "All five positions covered" : "Missing \(rating.missingPositions.joined(separator: ", "))"); Divider().overlay(.white.opacity(0.14)); Text(rating.finalRating, format: .number.precision(.fractionLength(1))).font(.title.weight(.black)).monospacedDigit().foregroundStyle(accent ? Color.accent : .white); Text("FINAL TEAM RATING").scoreLabel() }.frame(maxWidth: .infinity) }
    private func ratingMath(_ label: String, _ value: String, color: Color, detail: String? = nil) -> some View { VStack(alignment: .leading, spacing: 3) { HStack { Text(label).font(.system(size: 9, weight: .black)).foregroundStyle(.white.opacity(0.58)); Spacer(); Text(value).font(.caption.weight(.black)).monospacedDigit().foregroundStyle(color) }; if let detail { Text(detail).font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.64)).lineLimit(2).fixedSize(horizontal: false, vertical: true) } } }
    private func netScoreboard(player: TeamNetRating, opponent: TeamNetRating) -> some View { HStack(spacing: 12) { netCard("YOU", player); Text("VS").font(.caption.weight(.black)).foregroundStyle(.white.opacity(0.45)); netCard("OPP", opponent) }.padding(12).background(.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 16)) }
    private func netCard(_ title: String, _ rating: TeamNetRating) -> some View { VStack(spacing: 2) { Text(title).scoreLabel(); Text(rating.net >= 0 ? "+\(rating.net)" : "\(rating.net)").font(.title2.weight(.black)).foregroundStyle(Color.accent); Text("OFF \(rating.offense) · DEF \(rating.defense)").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.6)) }.frame(maxWidth: .infinity) }
}

struct BestPossibleTeamCard: View {
    let player: [DraftedPlayer]
    let opponent: [DraftedPlayer]
    let opponentName: String
    private var playerRating: LineupRatingBreakdown { TeamSimulator.ratingBreakdown(for: player) }
    private var opponentRating: LineupRatingBreakdown { TeamSimulator.ratingBreakdown(for: opponent) }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BEST POSSIBLE TEAMS").scoreLabel().foregroundStyle(Color.accent)
                    Text("Best lineups from each side’s five won teams").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
            }
            HStack(spacing: 12) {
                ratingCard("YOUR TEAM", rating: playerRating.finalRating, highlighted: playerRating.finalRating > opponentRating.finalRating)
                Text("VS").font(.caption.weight(.black)).foregroundStyle(.white.opacity(0.45))
                ratingCard(opponentName.uppercased(), rating: opponentRating.finalRating, highlighted: opponentRating.finalRating > playerRating.finalRating)
            }
            HStack { Text("YOUR BEST").scoreLabel().foregroundStyle(.white.opacity(0.55)); Spacer(); Text(opponentName.uppercased()).scoreLabel().foregroundStyle(.white.opacity(0.55)) }
            ForEach(0..<5, id: \.self) { index in
                let playerAssignment = playerRating.assignments[index]
                let opponentAssignment = opponentRating.assignments[index]
                HStack(alignment: .top, spacing: 7) {
                    lineupPlayer(player.first(where: { $0.id == playerAssignment.playerID }), slot: playerAssignment.slot, alignRight: true)
                    Text("VS").font(.caption2.weight(.black)).foregroundStyle(.white.opacity(0.35)).frame(width: 20)
                    lineupPlayer(opponent.first(where: { $0.id == opponentAssignment.playerID }), slot: opponentAssignment.slot, alignRight: false)
                }
            }
        }
        .padding(13)
        .background(.white.opacity(0.065))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.accent.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
    private func ratingCard(_ title: String, rating: Double, highlighted: Bool) -> some View {
        VStack(spacing: 2) {
            Text(title).scoreLabel().foregroundStyle(highlighted ? Color.accent : .white.opacity(0.55))
            Text(rating, format: .number.precision(.fractionLength(1))).font(.title2.weight(.black)).monospacedDigit().foregroundStyle(highlighted ? Color.accent : .white)
            Text("BEST RATING").font(.caption2.weight(.black)).foregroundStyle(.white.opacity(0.46))
        }.frame(maxWidth: .infinity)
    }
    private func lineupPlayer(_ drafted: DraftedPlayer?, slot: String, alignRight: Bool) -> some View {
        Group {
            if let drafted {
                VStack(alignment: alignRight ? .trailing : .leading, spacing: 2) {
                    HStack(spacing: 5) { if !alignRight { PlayerPortrait(player: drafted.season, size: 22) }; Text("\(slot) · \(drafted.season.playerName)").font(.footnote.weight(.black)).lineLimit(1); if alignRight { PlayerPortrait(player: drafted.season, size: 22) } }
                    Text(drafted.season.season).font(.caption2.weight(.black)).foregroundStyle(.white.opacity(0.56))
                    Text("\(drafted.season.points, specifier: "%.1f") PTS · \(drafted.season.rebounds, specifier: "%.1f") REB · \(drafted.season.assists, specifier: "%.1f") AST").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                    Text("\(drafted.season.steals, specifier: "%.1f") STL · \(drafted.season.blocks, specifier: "%.1f") BLK").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.58)).lineLimit(1)
                }
            } else {
                Text("\(slot) · OPEN").font(.caption.weight(.black)).foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity, alignment: alignRight ? .trailing : .leading)
        .padding(.vertical, 5)
    }
}

struct FinalMatchupBoard: View {
    let player: [DraftedPlayer]
    let opponent: [DraftedPlayer]
    let opponentName: String
    let playerAssignments: [PositionAssignment]
    let opponentAssignments: [PositionAssignment]
    var body: some View {
        VStack(spacing: 8) {
            HStack { Text("YOUR TEAM").scoreLabel(); Spacer(); Text(opponentName.uppercased()).scoreLabel() }
            ForEach(0..<5, id: \.self) { index in
                let playerAssignment = playerAssignments[index]
                let opponentAssignment = opponentAssignments[index]
                HStack(alignment: .top, spacing: 7) {
                    lineupPlayer(player.first(where: { $0.id == playerAssignment.playerID }), slot: playerAssignment.slot, outOfPosition: playerAssignment.isOutOfPosition, alignRight: true, accent: false)
                    Text("VS").font(.caption2.weight(.black)).foregroundStyle(.white.opacity(0.35)).frame(width: 20)
                    lineupPlayer(opponent.first(where: { $0.id == opponentAssignment.playerID }), slot: opponentAssignment.slot, outOfPosition: opponentAssignment.isOutOfPosition, alignRight: false, accent: false)
                }
            }
        }
        .padding(11).background(.white.opacity(0.065)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.10))).clipShape(RoundedRectangle(cornerRadius: 18))
    }
    private func lineupPlayer(_ drafted: DraftedPlayer?, slot: String, outOfPosition: Bool, alignRight: Bool, accent: Bool) -> some View {
        Group {
            if let drafted {
                VStack(alignment: alignRight ? .trailing : .leading, spacing: 2) {
                    HStack(spacing: 5) { if !alignRight { PlayerPortrait(player: drafted.season, size: 25) }; Text("\(slot) · \(drafted.season.playerName)").font(.footnote.weight(.black)).lineLimit(1); if alignRight { PlayerPortrait(player: drafted.season, size: 25) } }
                    Text(drafted.season.season).font(.caption2.weight(.black)).foregroundStyle(.white.opacity(0.56))
                    Text("\(drafted.season.points, specifier: "%.1f") PTS · \(drafted.season.rebounds, specifier: "%.1f") REB · \(drafted.season.assists, specifier: "%.1f") AST").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                    Text("\(drafted.season.steals, specifier: "%.1f") STL · \(drafted.season.blocks, specifier: "%.1f") BLK").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.58)).lineLimit(1)
                    Text("RATING \(drafted.season.overallRating)").font(.caption.weight(.black)).foregroundStyle(accent ? Color.accent : .white)
                    if outOfPosition { Text("OUT OF POSITION · −7").font(.system(size: 8, weight: .black)).foregroundStyle(.orange) }
                }
            } else { VStack(alignment: alignRight ? .trailing : .leading, spacing: 2) { Text("\(slot) · OPEN").font(.caption.weight(.black)).foregroundStyle(.white.opacity(0.38)); Text("OUT OF POSITION · −7").font(.system(size: 8, weight: .black)).foregroundStyle(.orange) } }
        }.frame(maxWidth: .infinity, alignment: alignRight ? .trailing : .leading).padding(.vertical, 7)
    }
}

struct StatBattleRow: View {
    let label: String; let player: Double; let opponent: Double
    private var playerWon: Bool { player > opponent }
    private var opponentWon: Bool { opponent > player }
    var body: some View { HStack(spacing: 9) { Text(value(player)).font(.caption.weight(.black)).foregroundStyle(playerWon ? Color.accent : .white).frame(width: 38, alignment: .trailing); GeometryReader { proxy in HStack(spacing: 2) { Rectangle().fill(playerWon ? Color.accent : .white.opacity(0.18)).frame(width: proxy.size.width * CGFloat(player / max(player + opponent, 1))); Spacer(minLength: 0) } }.frame(height: 4).clipShape(Capsule()).background(.white.opacity(0.08)).clipShape(Capsule()); Text(label).font(.caption2.weight(.black)).frame(width: 58); GeometryReader { proxy in HStack(spacing: 2) { Spacer(minLength: 0); Rectangle().fill(opponentWon ? Color.accent : .white.opacity(0.18)).frame(width: proxy.size.width * CGFloat(opponent / max(player + opponent, 1))) } }.frame(height: 4).clipShape(Capsule()).background(.white.opacity(0.08)).clipShape(Capsule()); Text(value(opponent)).font(.caption.weight(.black)).foregroundStyle(opponentWon ? Color.accent : .white).frame(width: 38, alignment: .leading) }.frame(height: 24) }
    private func value(_ number: Double) -> String { String(format: "%.1f", number) }
}
