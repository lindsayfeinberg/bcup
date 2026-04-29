import Foundation

/// Built-in game kinds stored on `gameLogs.gameType` (matches server / `LeagueRankingBasis`).
enum GameType: String, CaseIterable, Identifiable {
    case pong = "PONG"
    case beerBall = "BEER_BALL"
    case battlePong = "BATTLE_PONG"
    case baseball = "BASEBALL"
    case crossfire = "CROSSFIRE"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pong: return "Pong"
        case .beerBall: return "Beer Ball"
        case .battlePong: return "Battle Pong"
        case .baseball: return "Baseball"
        case .crossfire: return "Crossfire"
        }
    }

    var leagueRankingBasis: LeagueRankingBasis {
        switch self {
        case .pong: return .pong
        case .beerBall: return .beerBall
        case .battlePong: return .battlePong
        case .baseball: return .baseball
        case .crossfire: return .crossfire
        }
    }

    /// Short explainer for the Home “how games work” screen.
    var explainerText: String {
        switch self {
        case .pong:
            return """
            Teams (most commonly 2v2, but 1v1 or larger formats work too) face off in classic cup pong. Players take turns shooting into the opposing team’s cups to eliminate them. Games often use 6 or 10 cup setups, with options like one re-rack, bounce shots counting, and redemption where a team keeps shooting until they miss. Clear all opposing cups first to win.
            """

        case .beerBall:
            return """
            Two teams sit on opposite sides of the table with a can for each player. Teams throw a ball trying to hit the opposing cans. If a can is hit, the thrower drinks their can until both defenders touch the ball, return it to the table, and call “down.” If a can is knocked off the table, that player starts a fresh can. To finish, players must prove the can is empty with no drops left. First team with both cans finished wins.
            """

        case .battlePong:
            return """
            Battle Pong combines cup pong with flip cup. Two players battle in pong while their teammates wait in a flip cup line beside them. When a pong shot lands in a cup, that side immediately starts flip cup. If the shooting team wins flip cup, the cup is removed. If they lose, the cup stays. Play continues until one side’s pong cups are all gone.
            """

        case .baseball:
            return """
            Baseball uses baseball scoring with cups as targets. Players shoot at arranged cups for singles, doubles, triples, and home runs to score runs over typically 9 innings. Making a cup earns the matching hit. Hitting a cup without sinking it counts as a strike, while missing completely counts as an out. Standard baseball inning and scoring rules apply.
            """

        case .crossfire:
            return """
            Also known as Fiddle, Crossfire is a fast-paced partner game with teammates positioned diagonally across from each other. When a player makes a cup, they call “Crossfire” or “Fiddle.” The opponent next to that cup must drink it and complete flip cup while their team pauses shooting. Once a partnership clears all cups on both sides, all players race for the final center cup by bouncing the ball on the table and into the cup in sequence to win.
            """
        }
    }
}
