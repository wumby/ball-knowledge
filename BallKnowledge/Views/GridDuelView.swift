import SwiftUI

struct GridDuelView: View {
    @Binding var route: Route
    let mode: OnlineMatchMode
    @StateObject private var model: GridDuelViewModel

    init(route: Binding<Route>, mode: OnlineMatchMode, ladder: GridDuelLadderService? = nil) {
        _route = route; self.mode = mode
        _model = StateObject(wrappedValue: GridDuelViewModel(mode: mode, ladder: ladder))
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loading: ProgressView("BUILDING YOUR GRID…").tint(Color.accent)
            case let .failed(message): ContentUnavailableView("GRID UNAVAILABLE", systemImage: "exclamationmark.triangle", description: Text(message)).foregroundStyle(.white)
            case .playing: play
            case .results: results
            }
        }
        .task { await model.start() }
        .padding(16)
    }

    private var play: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Button { route = .home } label: { Image(systemName: "xmark").font(.headline.bold()).frame(width: 40, height: 40).background(.white.opacity(0.1)).clipShape(Circle()) }; Spacer(); VStack(alignment: .trailing, spacing: 1) { Text(mode == .ranked ? "RANKED BOX WARS" : "BOX WARS").font(.caption.weight(.black)).foregroundStyle(Color.accent); Text("\(model.secondsRemaining)s").font(.title.weight(.black)).monospacedDigit() } }
                Text("FIND A PLAYER WHO FITS BOTH CLUES").font(.headline.weight(.black))
                grid
                if let cell = model.selectedCell {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SELECTED · \(cell.rowPredicate.label) + \(cell.columnPredicate.label)").font(.caption.weight(.black)).foregroundStyle(Color.accent)
                        TextField("Type a player name to search", text: $model.query).textInputAutocapitalization(.words).padding(12).background(.white.opacity(0.09)).clipShape(RoundedRectangle(cornerRadius: 12))
                        ForEach(model.matches, id: \.id) { record in
                            Button { model.submit(record) } label: { HStack { Text(record.playerName).font(.headline.weight(.bold)); Spacer(); Image(systemName: "plus.circle.fill").foregroundStyle(Color.accent) }.padding(.vertical, 5) }.buttonStyle(.plain)
                        }
                    }.padding(14).background(.white.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }.scrollIndicators(.hidden)
    }

    private var grid: some View {
        let cells = model.engine?.grid.cells ?? []
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                Color.clear.frame(width: 82, height: 1)
                ForEach(0..<2, id: \.self) { column in
                    if let engine = model.engine {
                        let predicate = engine.grid.columns[column]
                        Text(predicate.label)
                            .font(.caption2.weight(.black))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .foregroundStyle(Color.accent)
                    }
                }
            }
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 4) {
                    if let engine = model.engine {
                        let predicate = engine.grid.rows[row]
                        Text(predicate.label)
                            .font(.caption2.weight(.black))
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(Color.accent)
                            .frame(width: 82, alignment: .trailing)
                    }
                    ForEach(0..<2, id: \.self) { column in
                        if cells.indices.contains(row * 2 + column) {
                            let cell = cells[row * 2 + column]; let answer = model.engine?.localAnswers[cell.id]
                            Button { model.select(cell: cell) } label: {
                                Text(answer?.playerName ?? "TAP TO ANSWER")
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(answer == nil ? Color.accent : .white)
                                    .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
                                    .padding(9)
                                    .background(model.selectedCellID == cell.id ? Color.accent.opacity(0.25) : .white.opacity(0.075))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.selectedCellID == cell.id ? Color.accent : .white.opacity(0.12)))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var results: some View {
        ScrollView { VStack(alignment: .leading, spacing: 14) {
            Text("BOX WARS RESULTS").font(.title2.weight(.black))
            if let result = model.result {
                Text(result.winner == .local ? "YOU WIN" : result.winner == .opponent ? "OPPONENT WINS" : "DRAW").font(.title.weight(.black)).foregroundStyle(Color.accent)
                Text("\(score(result.localScore)) – \(score(result.opponentScore))").font(.system(size: 42, weight: .black)).monospacedDigit()
                ForEach(result.cells) { item in HStack { VStack(alignment: .leading) { Text("\(item.cell.rowPredicate.label) + \(item.cell.columnPredicate.label)").font(.caption.weight(.black)); Text(item.localAnswer?.playerName ?? "No answer").font(.headline.weight(.bold)); Text("YOU: \(item.localRarity?.rawValue ?? "—") · OPP: \(item.opponentRarity?.rawValue ?? "—")").font(.caption).foregroundStyle(Color.accent) }; Spacer(); Text(item.winner == .local ? "WIN" : item.winner == .opponent ? "LOSS" : item.winner == .split ? "SPLIT" : "—").font(.caption.weight(.black)) }.padding(12).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12)) }
            }
            if let ranked = model.rankedResult { Text("RANKED MMR \(ranked.delta >= 0 ? "+" : "")\(ranked.delta) · \(ranked.ratingAfter)").font(.headline.weight(.black)).foregroundStyle(Color.accent) }
            Button("BACK TO HOME") { route = .home }.buttonStyle(PrimaryButtonStyle())
        }}.scrollIndicators(.hidden)
    }
    private func score(_ value: Double) -> String { value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value) }
}
