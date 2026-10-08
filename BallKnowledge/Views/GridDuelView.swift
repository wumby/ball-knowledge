import SwiftUI
import UIKit
import GameKit

struct GridDuelView: View {
    @Binding var route: Route
    @Environment(\.scenePhase) private var scenePhase
    let mode: OnlineMatchMode
    let opponentName: String
    let opponentTier: RankedTier?
    let onExit: (RankedMatchResult?) -> Void
    @StateObject private var model: GridDuelViewModel
    @State private var showingForfeitConfirmation = false
    @State private var showingPlayerSearch = false

    init(route: Binding<Route>, mode: OnlineMatchMode, ladder: GridDuelLadderService? = nil, friendMatch: GKMatch? = nil, opponentName: String = "RANKED AI", opponentTier: RankedTier? = nil, onExit: @escaping (RankedMatchResult?) -> Void = { _ in }) {
        _route = route
        self.mode = mode
        self.opponentName = opponentName
        self.opponentTier = opponentTier
        self.onExit = onExit
        let battleSession: BoxWarsBattleSession?
        if (mode == .friend || mode == .ranked), let friendMatch {
            battleSession = BoxWarsBattleSession(transport: GameKitMatchTransport(match: friendMatch))
        } else {
            battleSession = nil
        }
        _model = StateObject(wrappedValue: GridDuelViewModel(mode: mode, ladder: ladder, battleSession: battleSession))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch model.phase {
                case .loading:
                    ProgressView("BUILDING YOUR GRID…").tint(Color.accent)
                case let .failed(message):
                    ContentUnavailableView("GRID UNAVAILABLE", systemImage: "exclamationmark.triangle", description: Text(message))
                        .foregroundStyle(.white)
                case .playing: play
                case .calculatingResults: CalculationResultsView()
                case .results: results
                }
            }
            if let chat = model.quickChatToast {
                QuickChatToast(chat: chat)
                    .padding(.top, 12)
                    .padding(.horizontal, 56)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .padding(16)
        .background(Color.appBackground.ignoresSafeArea())
        .alert("Forfeit this match?", isPresented: $showingForfeitConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Forfeit Match", role: .destructive) {
                model.forfeit()
                onExit(nil)
                route = mode == .ranked ? .gridDuelRankedHub : .home
            }
        } message: {
            Text("Your current match progress will be lost.")
        }
        .sheet(isPresented: $showingPlayerSearch, onDismiss: {
            model.clearSelection()
        }) {
            playerSearchSheet
                .presentationDetents([.fraction(0.75)])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: model.secondsRemaining) { _, secondsRemaining in
            if secondsRemaining < 1 { dismissPlayerSearch() }
        }
        .onChange(of: model.phase) { _, phase in
            if phase != .playing { dismissPlayerSearch() }
        }
        .task { await model.start() }
        // Backgrounding preserves the live match. GameKit's 60-second grace
        // is owned by the session, not by SwiftUI scene transitions.
    }

    private var play: some View {
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 12) {
                playHeader
                grid
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    playHeader
                    grid
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var playHeader: some View {
        HStack(spacing: 10) {
            ForfeitButton { showingForfeitConfirmation = true }
            Text(opponentName.uppercased())
                .font(.system(size: 12, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(.white.opacity(0.07))
                .clipShape(Capsule())
            if mode == .ranked, let opponentTier {
                RankBadge(tier: opponentTier, game: .boxWars, size: 28)
            }
            Spacer(minLength: 4)
            if model.canQuickChat {
                QuickChatTrigger(messages: BoxWarsQuickChat.allCases, send: model.sendQuickChat)
            }
            Text(timerText)
                .font(.headline.monospacedDigit().weight(.black))
                .foregroundStyle(model.secondsRemaining <= 5 ? .red : Color.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(.white.opacity(0.07))
                .clipShape(Capsule())
        }
    }

    private var timerText: String {
        let minutes = model.secondsRemaining / 60
        let seconds = model.secondsRemaining % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    @ViewBuilder private var playerSearchSheet: some View {
        if let cell = model.selectedCell {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(cell.rowPredicate.label)  +  \(cell.columnPredicate.label)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.accent)

                    AutofocusingPlayerSearchField(text: $model.query)
                        .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20)
                        .padding(12)
                        .background(Color.boxPanelLight)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accent.opacity(0.42)))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    if model.matches.isEmpty {
                        ContentUnavailableView("SEARCH FOR A PLAYER", systemImage: "magnifyingglass", description: Text("Enter a player name to find an answer."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(model.matches, id: \.id) { record in
                            Button {
                                model.submit(record)
                                dismissPlayerSearch()
                            } label: {
                                HStack(spacing: 13) {
                                    PlayerPortrait(player: record, size: 52)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.playerName)
                                            .font(.headline.weight(.black))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Text(model.careerRange(for: record))
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white.opacity(0.58))
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "arrow.up.right.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.accent)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.boxPanel)
                                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.12)))
                                .clipShape(RoundedRectangle(cornerRadius: 15))
                                .contentShape(RoundedRectangle(cornerRadius: 15))
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        }
                        .listStyle(.plain)
                    }
                }
                .padding()
                .navigationTitle("CHOOSE PLAYER")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done", action: dismissPlayerSearch)
                    }
                }
            }
        }
    }

    private func dismissPlayerSearch() {
        showingPlayerSearch = false
        // Keep the text field in the sheet until `onDismiss` clears the
        // selection. Removing it during the keyboard dismissal animation can
        // invalidate UIKit's active text-input session.
    }
    private var grid: some View {
        let cells = model.engine?.grid.cells ?? []
        let gridIndices: [Int] = [0, 1]
        let boardSpacing: CGFloat = 14
        let columnClueHeight: CGFloat = 82
        let answerRowHeight: CGFloat = 138

        return VStack(spacing: boardSpacing) {
            HStack(spacing: boardSpacing) {
                Color.clear.frame(width: 86, height: 1)
                ForEach(gridIndices, id: \.self) { column in
                    if let predicate = model.engine?.grid.columns[column] {
                        ClueHeader(predicate: predicate, archiveRows: model.engine?.archiveRows ?? [])
                            .frame(maxWidth: .infinity, minHeight: columnClueHeight, maxHeight: columnClueHeight)
                    }
                }
            }
            .frame(height: columnClueHeight)

            playableRow(0, cells: cells, height: answerRowHeight, spacing: boardSpacing)
            playableRow(1, cells: cells, height: answerRowHeight, spacing: boardSpacing)
        }
        .frame(maxWidth: .infinity)
    }

    private func playableRow(_ row: Int, cells: [GridDuelCell], height: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            if let predicate = model.engine?.grid.rows[row] {
                ClueHeader(predicate: predicate, archiveRows: model.engine?.archiveRows ?? [], compact: true)
                    .frame(width: 86)
                    .frame(minHeight: height, maxHeight: height)
            }
            ForEach([0, 1], id: \.self) { column in
                if cells.indices.contains(row * 2 + column) {
                    let cell = cells[row * 2 + column]
                    boardCell(cell)
                        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                }
            }
        }
        .frame(height: height)
    }

    private func boardCell(_ cell: GridDuelCell) -> some View {
        let answer = model.engine?.localAnswers[cell.id]
        let portraitRecord = answer.flatMap { answer in
            model.engine?.archiveRows.first(where: { $0.id == answer.recordID })
        }
        let rarity = model.engine?.rarity(for: answer)
        let isSelected = model.selectedCellID == cell.id
        let isIncorrect: Bool = {
            guard case let .incorrect(feedbackCellID) = model.submissionFeedback else { return false }
            return feedbackCellID == cell.id
        }()

        return Button {
            model.select(cell: cell)
            showingPlayerSearch = true
        } label: {
            Group {
                if isIncorrect {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "xmark.octagon.fill").font(.title2)
                        Text("WRONG ANSWER").font(.caption.weight(.black))
                        Text("Try another player").font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else if let answer, let rarity {
                    rarityAnswer(answer, portraitRecord: portraitRecord, rarity: rarity)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Color.accent)
                        Text("CHOOSE PLAYER").font(.caption.weight(.black)).foregroundStyle(.white)
                        Text("Tap to answer").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.46))
                    }
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(isIncorrect ? AnyShapeStyle(Color.boxError.opacity(0.78)) : answer == nil ? AnyShapeStyle(Color.boxPanel) : (rarity?.background ?? AnyShapeStyle(Color.boxPanelLight)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isIncorrect ? Color.boxError : isSelected ? Color.accent : (rarity?.color ?? .white.opacity(0.11)), lineWidth: isSelected || isIncorrect ? 2 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: isSelected ? Color.accent.opacity(0.25) : .clear, radius: 10)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isIncorrect)
    }

    private func rarityAnswer(_ answer: GridAnswer, portraitRecord: SeasonRecord?, rarity: GridRarityTier) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let portraitRecord {
                    PlayerPortrait(player: portraitRecord, size: 42)
                } else {
                    PlayerPortrait(playerID: answer.playerID, playerName: answer.playerName, position: "", size: 42)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(rarity.rawValue).font(.caption2.weight(.black)).foregroundStyle(rarity.color)
                    Text(answer.playerName).font(.subheadline.weight(.black)).lineLimit(2).minimumScaleFactor(0.72)
                }
            }
            HStack(spacing: 4) {
                Image(systemName: "sparkles").font(.caption2)
                Text("\(rarity.points) PT\(rarity.points == 1 ? "" : "S")").font(.caption.weight(.black)).monospacedDigit()
            }
            .foregroundStyle(Color.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let result = model.result {
                    resultHeader(result)
                    reportDivider
                    reportActions
                    reportDivider
                    answerBoard(result)
                    reportDivider
                    bestGrid
                    reportDivider
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private var reportActions: some View {
        HStack(spacing: 10) {
            Button("PLAY AGAIN") { Task { await model.start() } }
                .buttonStyle(PrimaryButtonStyle(compact: true))
            Button("EXIT") {
                onExit(model.rankedResult)
                route = mode == .ranked ? .gridDuelRankedHub : .home
            }
            .buttonStyle(SecondaryButtonStyle(compact: true))
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    private func answerBoard(_ result: GridDuelResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ResultSectionHeader(title: "ANSWER REVEAL", subtitle: "Both answers and points for every square")
            resultAxisGrid { index in
                if result.cells.indices.contains(index) {
                    ResultMatchupGridCell(item: result.cells[index], opponentName: opponentName, archiveRows: model.engine?.archiveRows ?? [])
                }
            }
        }
    }

    private var bestGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResultSectionHeader(title: "BEST GRID", subtitle: "Highest-scoring answers for this board")
            let answers = model.engine?.bestValidAnswers() ?? []
            resultAxisGrid { index in
                if answers.indices.contains(index) { BestGridCell(item: answers[index]) }
            }
        }
    }

    private func resultAxisGrid<Content: View>(@ViewBuilder cell: @escaping (Int) -> Content) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Color.clear.frame(width: 86, height: 1)
                ForEach(0..<2, id: \.self) { column in
                    if let predicate = model.engine?.grid.columns[column] {
                        ClueHeader(predicate: predicate, archiveRows: model.engine?.archiveRows ?? []).frame(maxWidth: .infinity)
                    }
                }
            }
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 8) {
                    if let predicate = model.engine?.grid.rows[row] {
                        ClueHeader(predicate: predicate, archiveRows: model.engine?.archiveRows ?? [], compact: true).frame(width: 86)
                    }
                    ForEach(0..<2, id: \.self) { column in
                        cell(row * 2 + column).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func resultHeader(_ result: GridDuelResult) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(result.winner.resultTitle)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(result.winner.resultColor)
                .lineLimit(1).minimumScaleFactor(0.76)

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                scoreboardSide("YOU", score(result.localScore), color: result.winner == .local ? .boxSuccess : .white, alignment: .leading)
                Text("—").font(.title2.weight(.black)).foregroundStyle(.white.opacity(0.32))
                scoreboardSide(opponentName.uppercased(), score(result.opponentScore), color: result.winner == .opponent ? .boxSuccess : .white, alignment: .trailing)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .background(Color.boxPanelLight.opacity(0.92))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(result.winner.resultColor.opacity(0.42)))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
    }

    private var reportDivider: some View {
        Divider().overlay(.white.opacity(0.12))
    }

    private func scoreboardSide(_ label: String, _ value: String, color: Color, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(label).font(.caption2.weight(.black)).tracking(0.8).foregroundStyle(.white.opacity(0.56))
            Text(value).font(.system(size: 40, weight: .black, design: .rounded)).monospacedDigit().foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func score(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

private struct AutofocusingPlayerSearchField: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextField {
        let textField = MountedTextField()
        textField.placeholder = "Type a player name to search"
        textField.autocapitalizationType = .words
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.textColor = .white
        textField.tintColor = UIColor(Color.accent)
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        textField.didMoveToWindowHandler = { [weak coordinator = context.coordinator] textField in
            coordinator?.focusWhenMounted(textField)
        }
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        if textField.text != text {
            textField.text = text
        }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor final class Coordinator: NSObject {
        var parent: AutofocusingPlayerSearchField
        private var hasRetriedFocus = false

        init(parent: AutofocusingPlayerSearchField) {
            self.parent = parent
        }

        @objc func textChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func focusWhenMounted(_ textField: UITextField) {
            guard textField.window != nil, !textField.isFirstResponder else { return }

            if !textField.becomeFirstResponder(), !hasRetriedFocus {
                hasRetriedFocus = true
                DispatchQueue.main.async { [weak textField] in
                    guard let textField, textField.window != nil else { return }
                    _ = textField.becomeFirstResponder()
                }
            }
        }
    }
}

private final class MountedTextField: UITextField {
    var didMoveToWindowHandler: ((UITextField) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            didMoveToWindowHandler?(self)
        }
    }
}

private struct ClueHeader: View {
    let predicate: GridPredicate
    let archiveRows: [SeasonRecord]
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 3 : 5) {
            clueVisual
            Text(predicate.label)
                .font((compact ? Font.caption2 : .caption).weight(.black))
                .lineLimit(compact ? 4 : 3)
                .minimumScaleFactor(0.65)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white.opacity(0.88))
        .frame(maxWidth: .infinity, minHeight: compact ? 112 : 55)
        .padding(compact ? 5 : 7)
        .background(Color.boxPanel)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.1)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var clueVisual: some View {
        switch predicate {
        case let .team(team):
            if let record = archiveRows.first(where: { $0.team == team })
                ?? archiveRows.first(where: { NBAFranchiseIdentity.canonicalCode(for: $0.team) == team }) {
                TeamLogo(team: record.team, season: record.season, size: compact ? 25 : 31)
            } else {
                TeamBadge(team: team, size: compact ? 25 : 31)
            }
        case let .teammateOf(star):
            PlayerPortrait(playerID: star.playerID, playerName: star.playerName, position: "", size: compact ? 25 : 31)
        case .position, .decade:
            Image(systemName: predicate.symbol).font(compact ? .caption : .subheadline).foregroundStyle(Color.accent)
        }
    }
}

private struct CalculationResultsView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 52, weight: .black))
                .foregroundStyle(Color.accent)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .scaleEffect(isAnimating ? 1.08 : 0.92)
            Text("CALCULATING FINAL RESULTS…")
                .font(.headline.weight(.black))
                .tracking(0.8)
            Text("Comparing every answer and score")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.58))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

private struct ResultSectionHeader: View {
    let title: String
    let subtitle: String
    var accent: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline.weight(.black)).tracking(0.5).foregroundStyle(accent)
            Text(subtitle).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.53))
        }
    }
}

private struct ResultPlayerGridCell: View {
    enum Player: Equatable {
        case local
        case opponent
    }

    let item: GridDuelCellResult
    let player: Player
    let archiveRows: [SeasonRecord]

    var body: some View {
        playerCard(answer, points: points, rarity: rarity)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .topLeading)
        .background(Color.boxPanel)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke((rarity?.color ?? .white.opacity(0.12)).opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var answer: GridAnswer? { player == .local ? item.localAnswer : item.opponentAnswer }
    private var points: Double { player == .local ? item.localPoints : item.opponentPoints }
    private var rarity: GridRarityTier? { player == .local ? item.localRarity : item.opponentRarity }
    private var portraitRecord: SeasonRecord? {
        answer.flatMap { answer in archiveRows.first(where: { $0.id == answer.recordID }) }
    }

    private func playerCard(_ answer: GridAnswer?, points: Double, rarity: GridRarityTier?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                if let portraitRecord {
                    PlayerPortrait(player: portraitRecord, size: 40)
                } else if let answer {
                    PlayerPortrait(playerID: answer.playerID, playerName: answer.playerName, position: "", size: 40)
                } else {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.24))
                        .frame(width: 40, height: 40)
                }
                Text(answer?.playerName ?? "—")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(answer == nil ? .white.opacity(0.34) : .white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 2)
            }
            Text(rarity?.rawValue ?? "—")
                .font(.caption2.weight(.black))
                .foregroundStyle(rarity?.color ?? .white.opacity(0.3))
            Text("\(gridScore(points)) PTS")
                .font(.headline.weight(.black))
                .foregroundStyle(rarity?.color ?? .white.opacity(0.38))
                .monospacedDigit()
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background((rarity?.color ?? .white).opacity(answer == nil ? 0.04 : 0.12))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke((rarity?.color ?? .white.opacity(0.3)).opacity(answer == nil ? 0.16 : 0.36)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ResultMatchupGridCell: View {
    let item: GridDuelCellResult
    let opponentName: String
    let archiveRows: [SeasonRecord]

    var body: some View {
        HStack(spacing: 6) {
            ResultPlayerGridCell(item: item, player: .local, archiveRows: archiveRows)
                .accessibilityLabel("You: \(Int(item.localPoints)) points")
            ResultPlayerGridCell(item: item, player: .opponent, archiveRows: archiveRows)
                .accessibilityLabel("\(opponentName): \(Int(item.opponentPoints)) points")
        }
        .accessibilityElement(children: .contain)
    }
}

private struct BestGridCell: View {
    let item: GridBestAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                PlayerPortrait(playerID: item.portraitPlayerID, playerName: item.playerName, position: "", size: 40)
                Text(item.playerName).font(.headline.weight(.black)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }
            Text(item.rarity.rawValue.uppercased()).font(.caption2.weight(.black)).foregroundStyle(item.rarity.color)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(item.rarity.color.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(item.rarity.color.opacity(0.43)))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer(minLength: 0)
            Text("\(item.points) PTS").font(.headline.weight(.black)).foregroundStyle(Color.accent).monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .topLeading)
        .background(LinearGradient(colors: [Color.boxPanelLight, item.rarity.color.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(item.rarity.color.opacity(0.5)))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: item.rarity.color.opacity(0.1), radius: 8, y: 4)
    }
}

private func gridScore(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
}

fileprivate extension GridPredicate {
    var symbol: String {
        switch self {
        case .team: "shield.fill"
        case .position: "person.3.fill"
        case .teammateOf: "person.2.fill"
        case .decade: "calendar"
        }
    }
}

fileprivate extension GridRarityTier {
    var color: Color {
        switch self {
        case .common: .white.opacity(0.72)
        case .uncommon: Color(red: 0.39, green: 0.86, blue: 0.65)
        case .rare: Color(red: 0.97, green: 0.39, blue: 0.69)
        case .legendary: Color(red: 0.72, green: 0.46, blue: 0.98)
        case .mythic: Color(red: 0.81, green: 0.43, blue: 1.0)
        }
    }
    var background: AnyShapeStyle {
        let colors: [Color]
        switch self {
        case .common: colors = [.white.opacity(0.12), .white.opacity(0.045)]
        case .uncommon: colors = [Color(red: 0.26, green: 0.58, blue: 0.44).opacity(0.38), Color(red: 0.09, green: 0.24, blue: 0.18)]
        case .rare: colors = [Color.accent.opacity(0.42), Color(red: 0.29, green: 0.06, blue: 0.22)]
        case .legendary: colors = [Color(red: 0.58, green: 0.31, blue: 0.88).opacity(0.45), Color(red: 0.18, green: 0.07, blue: 0.28)]
        case .mythic: colors = [Color(red: 0.74, green: 0.33, blue: 0.86).opacity(0.48), Color(red: 0.22, green: 0.06, blue: 0.29)]
        }
        return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

fileprivate extension GridDuelWinner {
    var resultLabel: String {
        switch self { case .local: "YOU WIN"; case .opponent: "OPP WINS"; case .draw: "DRAW" }
    }
    var resultTitle: String {
        switch self { case .local: "YOU WIN"; case .opponent: "OPPONENT WINS"; case .draw: "DRAW" }
    }
    var resultColor: Color {
        switch self { case .local: .boxSuccess; case .opponent: .boxOpponent; case .draw: Color(red: 0.30, green: 0.78, blue: 0.79) }
    }
}

fileprivate extension Color {
    static let boxPanel = Color(red: 0.105, green: 0.035, blue: 0.115)
    static let boxPanelLight = Color(red: 0.16, green: 0.055, blue: 0.17)
    static let boxError = Color(red: 0.78, green: 0.15, blue: 0.19)
    static let boxSuccess = Color(red: 0.36, green: 0.85, blue: 0.60)
    static let boxOpponent = Color(red: 0.97, green: 0.30, blue: 0.60)
}

struct ForfeitButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "flag.fill")
                .font(.caption.weight(.black))
                .foregroundStyle(.black)
                .frame(width: 34, height: 34)
                .background(Color.accent)
                .clipShape(Circle())
        }
        .accessibilityLabel("FORFEIT")
    }
}
