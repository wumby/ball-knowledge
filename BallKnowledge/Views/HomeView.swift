import SwiftUI

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
                            TeamBadge(team: "NBA", size: compact ? 54 : 64)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("FIVE ALIVE").font(.title3.weight(.black))
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.45))
                        }
                        Text("Bid on legendary team-years, draft the right player, and outbuild your rival.")
                            .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.70))
                        Button { route = .gameSetup } label: { Label("PLAY FIVE ALIVE", systemImage: "banknote.fill").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle(compact: compact))
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
                            Text("More ways to test your basketball knowledge are in the works.")
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
    @Binding var difficulty: MatchDifficulty

    @State private var selectedMode: PlayMode?
    @State private var selectedDifficulty: MatchDifficulty?

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 700
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 14 : 20) {
                    HStack { Button { route = .home } label: { Image(systemName: "chevron.left").font(.headline.bold()).frame(width: 42, height: 42).background(.white.opacity(0.08)).clipShape(Circle()) }; Spacer() }
                    BrandHeader(compact: compact, title: "FIVE ALIVE", tagline: "BUILD THE BEST FIVE")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PLAY MODE").scoreLabel()
                        PlayModeCard(title: "VERSUS AI", subtitle: "Draft against a computer rival", icon: "cpu", available: true, isSelected: selectedMode == .versusAI) {
                            selectedMode = .versusAI
                        }
                        PlayModeCard(title: "RANKED LADDER", subtitle: "Face random players and climb", icon: "trophy.fill", available: false)
                        PlayModeCard(title: "FRIEND MATCH", subtitle: "Send a private challenge", icon: "person.2.fill", available: false)
                    }
                    if selectedMode == .versusAI {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SCOUTING LEVEL").scoreLabel()
                            ForEach(MatchDifficulty.allCases) { difficultyCard($0, compact: compact) }
                        }
                    }
                    if let selectedDifficulty {
                        Button {
                            difficulty = selectedDifficulty
                            route = .game
                        } label: {
                            Label("START VS AI", systemImage: "banknote.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle(compact: compact))
                    }
                }.padding(.horizontal, 20).padding(.vertical, compact ? 14 : 22)
            }.scrollIndicators(.hidden).frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
    private func difficultyCard(_ level: MatchDifficulty, compact: Bool) -> some View {
        Button { selectedDifficulty = level } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.rawValue).font(compact ? .subheadline.weight(.black) : .headline.weight(.black))
                    Text(level.subtitle).font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: selectedDifficulty == level ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selectedDifficulty == level ? Color.accent : .white.opacity(0.3))
            }
            .padding(.horizontal, 14).padding(.vertical, compact ? 10 : 13)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(selectedDifficulty == level ? Color.accent.opacity(0.14) : .white.opacity(0.055))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selectedDifficulty == level ? Color.accent.opacity(0.8) : .white.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

private enum PlayMode {
    case versusAI
}

private struct PlayModeCard: View {
    let title: String; let subtitle: String; let icon: String; let available: Bool
    var isSelected = false
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) { card }
                    .buttonStyle(.plain)
            } else {
                card
            }
        }
        .accessibilityAddTraits(action == nil ? .isStaticText : [])
    }

    private var card: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3.weight(.black)).foregroundStyle(isSelected ? Color.accent : .white.opacity(available ? 0.62 : 0.3)).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.subheadline.weight(.black)); Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.58)) }
            Spacer()
            Text(available ? (isSelected ? "SELECTED" : "SELECT") : "SOON").scoreLabel().foregroundStyle(isSelected ? Color.accent : .white.opacity(available ? 0.52 : 0.34))
        }.padding(13).background(isSelected ? Color.accent.opacity(0.16) : .white.opacity(available ? 0.055 : 0.045)).overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Color.accent.opacity(0.8) : .white.opacity(available ? 0.14 : 0.08))).clipShape(RoundedRectangle(cornerRadius: 14))
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
    var title: String = "BALL KNOWLEDGE"
    var tagline: String?

    var body: some View {
        HStack(spacing: compact ? 10 : 12) {
            Image("BrandMark")
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
struct PrimaryButtonStyle: ButtonStyle { let compact: Bool; init(compact: Bool = false) { self.compact = compact }; func makeBody(configuration: Configuration) -> some View { configuration.label.font(.headline.weight(.black)).foregroundStyle(.black).padding(compact ? 13 : 17).background(Color.accent).clipShape(RoundedRectangle(cornerRadius: 15)).scaleEffect(configuration.isPressed ? 0.98 : 1) } }
struct SecondaryButtonStyle: ButtonStyle { let compact: Bool; init(compact: Bool = false) { self.compact = compact }; func makeBody(configuration: Configuration) -> some View { configuration.label.font(.headline.weight(.bold)).foregroundStyle(.white).padding(compact ? 12 : 16).frame(maxWidth: .infinity).background(.white.opacity(configuration.isPressed ? 0.1 : 0.04)).overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.14))).clipShape(RoundedRectangle(cornerRadius: 15)) } }
extension View { func scoreLabel() -> some View { font(.caption2.weight(.black)).tracking(1.4).foregroundStyle(.white.opacity(0.48)) } }
