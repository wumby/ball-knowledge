import Foundation

@MainActor final class GridDuelViewModel: ObservableObject {
    enum Phase: Equatable { case loading, playing, results, failed(String) }
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var engine: GridDuelEngine?
    @Published private(set) var deadline: Date?
    @Published var selectedCellID: String?
    @Published var query = ""
    @Published private(set) var secondsRemaining = Int(GridDuelEngine.duration)
    @Published private(set) var result: GridDuelResult?
    @Published private(set) var rankedResult: RankedMatchResult?
    private var clock: Task<Void, Never>?
    private let mode: OnlineMatchMode
    private let ladder: GridDuelLadderService?

    init(mode: OnlineMatchMode, ladder: GridDuelLadderService? = nil) { self.mode = mode; self.ladder = ladder }

    func start() async {
        phase = .loading; result = nil; rankedResult = nil
        do {
            let rows = try await NBAStatsStore.shared.database().teamSeasons.flatMap(\.players)
            guard let grid = GridDuelEngine.generate(from: rows, seed: UInt64(Date().timeIntervalSince1970)) else { throw ArchiveLoadError.invalidArchive }
            var createdEngine = GridDuelEngine(grid: grid, archiveRows: rows)
            // Practice and ranked fallback share the exact human validation and
            // scoring path. Difficulty here controls how many cells the AI fills.
            if mode != .friend {
                let fillCount = mode == .ranked ? 4 : 3
                for cell in grid.cells.prefix(fillCount) {
                    if let answer = createdEngine.validRecords(for: cell).sorted(by: { $0.playerName < $1.playerName }).first {
                        _ = createdEngine.submit(answer, to: cell.id, forLocalPlayer: false, at: Date().addingTimeInterval(20))
                    }
                }
            }
            engine = createdEngine
            selectedCellID = grid.cells.first?.id; deadline = Date().addingTimeInterval(GridDuelEngine.duration); phase = .playing
            startClock()
        } catch { phase = .failed(error.localizedDescription) }
    }

    var selectedCell: GridDuelCell? { engine?.grid.cells.first(where: { $0.id == selectedCellID }) }
    var matches: [SeasonRecord] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let engine,
              let selectedCell else { return [] }
        return Array(engine.validRecords(for: selectedCell, query: query).prefix(30))
    }

    func select(cell: GridDuelCell) { selectedCellID = cell.id; query = "" }
    func submit(_ record: SeasonRecord) {
        guard var engine, let cellID = selectedCellID else { return }
        guard engine.submit(record, to: cellID, forLocalPlayer: true, deadline: deadline) else { return }
        self.engine = engine
    }

    func finish() {
        guard phase == .playing, let engine else { return }
        clock?.cancel(); let final = engine.resolve(); result = final; phase = .results
        if mode == .ranked { rankedResult = ladder?.recordCompletedMatch(id: "grid-duel-\(engine.grid.id.uuidString)", didWin: final.winner == .local) }
    }

    private func startClock() {
        clock?.cancel()
        clock = Task { [weak self] in
            while let self, !Task.isCancelled, let deadline = self.deadline {
                self.secondsRemaining = max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
                if self.secondsRemaining == 0 { self.finish(); return }
                try? await Task.sleep(for: .seconds(0.25))
            }
        }
    }

    deinit { clock?.cancel() }
}
