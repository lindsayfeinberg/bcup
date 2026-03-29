import Foundation

enum WhatIfMatchupMath {
    /// Mean Laplace-smoothed strength per player (`(wins+1)/(games+2)` in the same scope as league odds); nil if any ID is missing from `roster` or `memberIds` is empty.
    static func meanResolvedOdds(
        memberIds: Set<String>,
        roster: [CommunityMemberRosterRow],
        basis: LeagueRankingBasis
    ) -> Double? {
        guard !memberIds.isEmpty else { return nil }
        let byId = Dictionary(uniqueKeysWithValues: roster.map { ($0.profileId, $0) })
        var sum = 0.0
        for id in memberIds {
            guard let row = byId[id] else { return nil }
            sum += row.laplaceSmoothedStrengthForMatchup(basis: basis)
        }
        return sum / Double(memberIds.count)
    }

    static func winProbabilities(sideA: Double, sideB: Double) -> (pA: Double, pB: Double) {
        let sum = sideA + sideB
        if sum <= 0 { return (0.5, 0.5) }
        let pA = sideA / sum
        let pB = sideB / sum
        return (pA, pB)
    }

    /// Vig-free American moneyline from win probability; `p` clamped to `[0.02, 0.98]` only for this conversion.
    static func americanMoneyline(impliedWinProbability p: Double) -> Int {
        let clamped = min(max(p, 0.02), 0.98)
        if clamped >= 0.5 {
            return -Int((100 * clamped / (1 - clamped)).rounded())
        }
        return Int((100 * (1 - clamped) / clamped).rounded())
    }

    static func percentagePointEdge(pA: Double, pB: Double) -> Double {
        (pA - pB) * 100
    }
}
