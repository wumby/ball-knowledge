import Foundation
import GameKit

protocol MatchmakingService { func connect() async throws -> MatchConnection }
struct MatchConnection { let seed: UInt64; let isLocalFallback: Bool }

final class GameKitMatchmakingService: NSObject, MatchmakingService {
    func connect() async throws -> MatchConnection {
        // The production adapter presents GKMatchmakerViewController and exchanges the seed over GKMatch.
        // Local fallback keeps the MVP playable in previews and on Simulator.
        try await Task.sleep(for: .milliseconds(650))
        return MatchConnection(seed: UInt64(Date().timeIntervalSince1970), isLocalFallback: true)
    }
}
