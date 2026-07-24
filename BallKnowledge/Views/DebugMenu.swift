#if DEBUG
import SwiftUI

struct DebugMenu: View {
    @ObservedObject var model: GameViewModel
    var body: some View { Form { Section("Match") { Text("Difficulty: \(model.difficulty.rawValue)"); Text("Offers: \(model.engine?.teams.count ?? 0)") }; Section("Auction") { Button("Set bid to all-in") { model.bid = model.engine?.playerBudget ?? 0 }; Button("Lock current bid") { model.submitBid() } } }.navigationTitle("Developer tools") }
}
#endif
