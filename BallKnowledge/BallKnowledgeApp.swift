import SwiftUI
import SwiftData

@main
struct BallKnowledgeApp: App {
    private let container: ModelContainer = {
        let schema = Schema([PlayerSeason.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .containerRelativeFrame([.horizontal, .vertical])
        }
            .modelContainer(container)
    }
}
