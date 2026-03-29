//
//  bitchcupTests.swift
//  bitchcupTests
//
//  Created by Lindsay Feinberg on 3/21/26.
//

import Testing
@testable import bitchcup

struct bitchcupTests {

    @Test func perGameTypeCases_excludesAllGames() {
        #expect(!LeagueRankingBasis.perGameTypeCases.contains(.allGames))
        #expect(LeagueRankingBasis.perGameTypeCases.count == LeagueRankingBasis.allCases.count - 1)
    }

    @Test func resolvedOddsForMatchup_usesTypeWhenGamesInType() {
        let row = CommunityMemberRosterRow(
            profileId: "a",
            displayName: "A",
            profilePhotoUrl: nil,
            communityOdds: 0.25,
            communityGamesPlayed: 10,
            communityOddsByGameType: ["PONG": 0.9],
            communityGamesPlayedByGameType: ["PONG": 4]
        )
        #expect(row.resolvedOddsForMatchup(basis: .pong) == 0.9)
    }

    @Test func resolvedOddsForMatchup_fallsBackWhenNoGamesInType() {
        let row = CommunityMemberRosterRow(
            profileId: "a",
            displayName: "A",
            profilePhotoUrl: nil,
            communityOdds: 0.4,
            communityGamesPlayed: 5,
            communityOddsByGameType: ["PONG": 0.99],
            communityGamesPlayedByGameType: ["PONG": 0]
        )
        #expect(row.resolvedOddsForMatchup(basis: .pong) == 0.4)
    }

    @Test func laplaceSmoothedStrength_oneAndOhRecordNotExtreme() {
        let perfect = CommunityMemberRosterRow(
            profileId: "a",
            displayName: "A",
            profilePhotoUrl: nil,
            communityOdds: 1.0,
            communityGamesPlayed: 1
        )
        #expect(abs(perfect.laplaceSmoothedStrengthForMatchup(basis: .allGames) - 2.0 / 3.0) < 0.0001)
        let winless = CommunityMemberRosterRow(
            profileId: "b",
            displayName: "B",
            profilePhotoUrl: nil,
            communityOdds: 0.0,
            communityGamesPlayed: 1
        )
        #expect(abs(winless.laplaceSmoothedStrengthForMatchup(basis: .allGames) - 1.0 / 3.0) < 0.0001)
    }

    @Test func laplaceSmoothedStrength_noGamesIsFiftyFiftyPrior() {
        let row = CommunityMemberRosterRow(
            profileId: "a",
            displayName: "A",
            profilePhotoUrl: nil,
            communityOdds: 0.0,
            communityGamesPlayed: 0
        )
        #expect(abs(row.laplaceSmoothedStrengthForMatchup(basis: .allGames) - 0.5) < 0.0001)
    }

    @Test func meanResolvedOdds_averagesSides() {
        let roster = [
            CommunityMemberRosterRow(
                profileId: "a",
                displayName: "A",
                profilePhotoUrl: nil,
                communityOdds: 0.2,
                communityGamesPlayed: 1
            ),
            CommunityMemberRosterRow(
                profileId: "b",
                displayName: "B",
                profilePhotoUrl: nil,
                communityOdds: 0.8,
                communityGamesPlayed: 1
            )
        ]
        let mean = WhatIfMatchupMath.meanResolvedOdds(
            memberIds: ["a", "b"],
            roster: roster,
            basis: .allGames
        )
        #expect(mean != nil)
        #expect(abs(mean! - 0.5) < 0.0001)
    }

    @Test func winProbabilities_evenWhenBothStrengthsZero() {
        let (pA, pB) = WhatIfMatchupMath.winProbabilities(sideA: 0, sideB: 0)
        #expect(pA == 0.5 && pB == 0.5)
    }

    @Test func winProbabilities_ratio() {
        let (pA, pB) = WhatIfMatchupMath.winProbabilities(sideA: 0.75, sideB: 0.25)
        #expect(abs(pA - 0.75) < 0.0001)
        #expect(abs(pB - 0.25) < 0.0001)
    }

    @Test func americanMoneyline_knownValues() {
        #expect(WhatIfMatchupMath.americanMoneyline(impliedWinProbability: 0.6) == -150)
        #expect(WhatIfMatchupMath.americanMoneyline(impliedWinProbability: 0.4) == 150)
        #expect(WhatIfMatchupMath.americanMoneyline(impliedWinProbability: 0.5) == -100)
    }

    @Test func percentagePointEdge() {
        let edge = WhatIfMatchupMath.percentagePointEdge(pA: 0.68, pB: 0.32)
        #expect(abs(edge - 36) < 0.0001)
    }
}
