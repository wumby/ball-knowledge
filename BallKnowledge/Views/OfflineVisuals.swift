import Foundation
import SwiftUI

/// Offline visual catalog. Asset names are deliberately stable: portraits use
/// `player_<playerID>` and logos use the era key returned by `teamLogoName`.
/// Missing or unapproved files always fall back to app-generated artwork.
enum OfflineVisualCatalog {
    enum PortraitContext: Equatable {
        case standard
        case draftSelection
    }

    enum PortraitPresentation: Equatable {
        case realHeadshot
        case generatedAvatar
    }

    struct TeamSeasonPortraitCoverage: Hashable, Decodable {
        let team: String
        let season: String
        let rosterCount: Int
        let availableHeadshots: Int
        let missingHeadshots: Int
        let suppressDraftPortraits: Bool
    }

    struct TeamLogoEra: Hashable, Decodable {
        let team: String
        let firstSeason: Int
        let lastSeason: Int
        let assetName: String

        func contains(_ season: Int) -> Bool {
            season >= firstSeason && season <= lastSeason
        }
    }

    /// Loaded from the bundled visual manifest, which is the sole era registry.
    /// A broken/missing manifest intentionally leaves no match, so `TeamLogo`
    /// renders its neutral badge rather than a modern franchise mark.
    static let teamLogoEras: [TeamLogoEra] = loadTeamLogoEras()

    static func portraitName(for playerID: String, team: String? = nil, season: String? = nil, context: PortraitContext = .standard) -> String? {
        guard portraitMode == "licensedPhotos" || portraitMode == "developmentReferencePhotos" else { return nil }
        if context == .draftSelection, let team, let season, isDraftPortraitSuppressed(team: team, season: season) {
            return nil
        }
        let name = portraitAssetName(for: playerID)
        return hasImage(named: name) ? name : nil
    }

    static func isDraftPortraitSuppressed(team: String, season: String) -> Bool {
        teamSeasonPortraitCoverage.first { $0.team == team && $0.season == season }?.suppressDraftPortraits ?? false
    }

    static func shouldSuppressDraftPortraits(missingHeadshots: Int, rosterCount: Int) -> Bool {
        rosterCount > 0 && missingHeadshots > rosterCount / 2
    }

    /// Pure policy helper so coverage behavior can be tested independently of
    /// UIKit asset loading. Standard/profile contexts never suppress an image.
    static func portraitPresentation(team: String, season: String, context: PortraitContext, hasAvailableHeadshot: Bool, coverage: TeamSeasonPortraitCoverage? = nil) -> PortraitPresentation {
        guard hasAvailableHeadshot else { return .generatedAvatar }
        guard context == .draftSelection else { return .realHeadshot }
        let suppressed = coverage?.suppressDraftPortraits ?? isDraftPortraitSuppressed(team: team, season: season)
        return suppressed ? .generatedAvatar : .realHeadshot
    }

    static func portraitAssetName(for playerID: String) -> String {
        "player_\(playerID.lowercased())"
    }

    static func teamLogoName(team: String, season: String) -> String? {
        if let year = Int(season.prefix(4)), let era = teamLogoEras.first(where: { $0.team == team && $0.contains(year) }), hasImage(named: era.assetName) {
            return era.assetName
        }
        return nil
    }

    /// Useful to validation tests and the ingestion script: it selects an era
    /// even before that approved image has been added to the asset catalog.
    static func expectedTeamLogoName(team: String, season: String) -> String? {
        guard let year = Int(season.prefix(4)) else { return nil }
        return teamLogoEras.first { $0.team == team && $0.contains(year) }?.assetName
    }

    private static func hasImage(named name: String) -> Bool {
        #if canImport(UIKit)
        return UIImage(named: name) != nil
        #else
        return false
        #endif
    }

    private struct VisualManifest: Decodable {
        let teamLogos: [TeamLogoEra]
        let portraitMode: String?
        let teamSeasonPortraitCoverage: [TeamSeasonPortraitCoverage]?
    }

    private static let portraitMode = loadManifest()?.portraitMode ?? "generatedAvatars"
    static let teamSeasonPortraitCoverage = loadManifest()?.teamSeasonPortraitCoverage ?? []

    private static func loadTeamLogoEras() -> [TeamLogoEra] {
        loadManifest()?.teamLogos ?? []
    }

    private static func loadManifest() -> VisualManifest? {
        let bundles = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        for bundle in bundles {
            guard let url = bundle.url(forResource: "OfflineVisualManifest", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let manifest = try? JSONDecoder().decode(VisualManifest.self, from: data) else { continue }
            return manifest
        }
        assertionFailure("OfflineVisualManifest.json is missing or invalid")
        return nil
    }
}

struct PlayerPortrait: View {
    let playerID: String
    let playerName: String
    let position: String
    let size: CGFloat
    let context: OfflineVisualCatalog.PortraitContext
    let playerTeam: String?
    let playerSeason: String?

    init(player: SeasonRecord, size: CGFloat, context: OfflineVisualCatalog.PortraitContext = .standard) {
        self.playerID = player.playerID
        self.playerName = player.playerName
        self.position = player.position
        self.size = size
        self.context = context
        self.playerTeam = player.team
        self.playerSeason = player.season
    }

    init(playerID: String, playerName: String, position: String, size: CGFloat, context: OfflineVisualCatalog.PortraitContext = .standard) {
        self.playerID = playerID; self.playerName = playerName; self.position = position; self.size = size; self.context = context
        self.playerTeam = nil; self.playerSeason = nil
    }

    var body: some View {
        Group {
            if let imageName = OfflineVisualCatalog.portraitName(for: playerID, team: team, season: season, context: context) {
                Image(imageName).resizable().scaledToFill()
            } else {
                generatedAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.28), lineWidth: 1))
        .accessibilityLabel("\(playerName) portrait")
    }

    private var team: String? { context == .draftSelection ? playerTeam : nil }
    private var season: String? { context == .draftSelection ? playerSeason : nil }

    private var generatedAvatar: some View {
        let initials = playerName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        let palette = avatarPalette
        return ZStack {
            Circle().fill(LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(.white.opacity(0.12)).frame(width: size * 0.50, height: size * 0.50).offset(x: size * 0.22, y: -size * 0.24)
            VStack(spacing: size * 0.01) {
                Text(initials).font(.system(size: size * 0.30, weight: .black, design: .rounded))
                Text(position.split(separator: "-").first.map(String.init) ?? position).font(.system(size: size * 0.14, weight: .black, design: .rounded))
            }
            .foregroundStyle(.white)
        }
    }

    private var avatarPalette: [Color] {
        let seed = playerID.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        let colors: [(Color, Color)] = [(.indigo, .blue), (.purple, .indigo), (.teal, .blue), (.orange, .red), (.mint, .teal), (.pink, .purple)]
        return [colors[seed % colors.count].0.opacity(0.92), colors[seed % colors.count].1.opacity(0.82)]
    }
}

struct TeamLogo: View {
    let team: String
    let season: String
    let size: CGFloat

    var body: some View {
        Group {
            if let imageName = OfflineVisualCatalog.teamLogoName(team: team, season: season) {
                Image(imageName).resizable().scaledToFit().padding(size * 0.06)
            } else {
                TeamBadge(team: team, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(TeamBrand.name(for: team)) \(season) logo")
    }
}
