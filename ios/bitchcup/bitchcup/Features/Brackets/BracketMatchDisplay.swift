import Foundation

/// Which side won (for two-slot bracket UI). `ambiguous` covers odd bye outcomes.
enum BracketWinningSide {
    case top
    case bottom
    case ambiguous
}

struct BracketMatchUIState {
    let effectiveParticipantProfileIds: [String]
    let topParticipantIds: [String]
    let bottomParticipantIds: [String]
    let isPlayed: Bool
    let canLogResult: Bool
    let isWaitingOnFeeders: Bool
    let winningSide: BracketWinningSide?
    /// Auto-advanced bye — hide in round list; show compact in tree.
    let isAutoAdvancedBye: Bool
}

enum BracketMatchDisplay {
    /// Same rule as legacy `shouldShowMatchInRound`: hide winner-only bye rows from the rounds list.
    static func hideFromRoundsList(match: BracketMatchSnapshot, teamSize: Int) -> Bool {
        isAutoAdvancedBye(match: match, teamSize: teamSize)
    }

    static func isAutoAdvancedBye(match: BracketMatchSnapshot, teamSize: Int) -> Bool {
        let participants = match.participantProfileIds ?? []
        let winners = match.winnerProfileIds ?? []
        let losers = match.loserProfileIds ?? []
        return !winners.isEmpty &&
            losers.isEmpty &&
            participants.count == teamSize &&
            winners.count == teamSize
    }

    static func uiState(
        match: BracketMatchSnapshot,
        matchById: [String: BracketMatchSnapshot],
        teamSize: Int,
        currentUserId: String?,
        viewerProfileIds: Set<String>? = nil
    ) -> BracketMatchUIState {
        let merged = resolvedRosterForLogging(match: match, matchById: matchById, teamSize: teamSize)
        let top = Array(merged.prefix(teamSize))
        let bottom = Array(merged.dropFirst(teamSize).prefix(teamSize))
        let played = isPlayed(match: match)
        let waiting = merged.isEmpty && (match.feederMatchIds?.isEmpty == false)
        let canLog = canLogResult(
            match: match,
            matchById: matchById,
            teamSize: teamSize,
            currentUserId: currentUserId,
            viewerProfileIds: viewerProfileIds
        )
        let winSide = winningSide(match: match, top: top, bottom: bottom, teamSize: teamSize)
        let bye = isAutoAdvancedBye(match: match, teamSize: teamSize)
        return BracketMatchUIState(
            effectiveParticipantProfileIds: merged,
            topParticipantIds: top,
            bottomParticipantIds: bottom,
            isPlayed: played,
            canLogResult: canLog,
            isWaitingOnFeeders: waiting,
            winningSide: winSide,
            isAutoAdvancedBye: bye
        )
    }

    /// Roster order passed into `GameLogBracketContext` and used for top/bottom slots. Prefer a full stored list for
    /// scheduled matches; for active placeholders prefer the merged feeder-aware list when it is complete.
    static func resolvedRosterForLogging(
        match: BracketMatchSnapshot,
        matchById: [String: BracketMatchSnapshot],
        teamSize: Int
    ) -> [String] {
        let expected = 2 * teamSize
        let decoded = match.participantProfileIds ?? []
        let merged = effectiveParticipantProfileIds(match: match, matchById: matchById, teamSize: teamSize)
        let hasActiveFeeders = match.feederMatchIds?.isEmpty == false

        if !hasActiveFeeders {
            if decoded.count == expected { return decoded }
            return decoded
        }
        if merged.count == expected { return merged }
        if decoded.count == expected { return decoded }
        return merged
    }

    static func effectiveParticipantProfileIds(
        match: BracketMatchSnapshot,
        matchById: [String: BracketMatchSnapshot],
        teamSize: Int
    ) -> [String] {
        let decoded = match.participantProfileIds ?? []
        guard let feederIds = match.feederMatchIds, !feederIds.isEmpty else {
            return decoded
        }

        func advancingIds(from feeder: BracketMatchSnapshot) -> [String] {
            if let winners = feeder.winnerProfileIds, !winners.isEmpty {
                return winners
            }
            if let losers = feeder.loserProfileIds, !losers.isEmpty {
                return losers
            }
            let participants = feeder.participantProfileIds ?? []
            return participants.count == teamSize ? participants : []
        }

        // Placeholders may have bye-prefilled `participantProfileIds` plus feeders; merge like the server
        // so the effective roster reaches 2 * teamSize when both sides are known.
        var out: [String] = []
        var seen = Set<String>()
        for id in decoded where seen.insert(id).inserted {
            out.append(id)
        }
        let expected = 2 * teamSize
        if out.count >= expected {
            return out
        }
        for feederId in feederIds {
            guard out.count < expected else { break }
            guard let feeder = matchById[feederId] else { continue }
            for id in advancingIds(from: feeder) where seen.insert(id).inserted {
                out.append(id)
            }
        }
        return out
    }

    static func isPlayed(match: BracketMatchSnapshot) -> Bool {
        let winners = match.winnerProfileIds ?? []
        let losers = match.loserProfileIds ?? []
        return !winners.isEmpty || !losers.isEmpty
    }

    static func placeholderReadyToLog(match: BracketMatchSnapshot, effectiveCount: Int, teamSize: Int) -> Bool {
        guard let feeders = match.feederMatchIds, !feeders.isEmpty else { return true }
        return effectiveCount == 2 * teamSize
    }

    /// Whether the current user may open the log-game flow for this match. Submit validation still happens on the form / backend.
    static func canLogResult(
        match: BracketMatchSnapshot,
        matchById: [String: BracketMatchSnapshot],
        teamSize: Int,
        currentUserId: String?,
        viewerProfileIds: Set<String>? = nil
    ) -> Bool {
        let roster = resolvedRosterForLogging(match: match, matchById: matchById, teamSize: teamSize)
        let expected = 2 * teamSize
        guard !isPlayed(match: match), roster.count == expected else { return false }

        let viewers: Set<String> = viewerProfileIds ?? Set([currentUserId].compactMap { $0 })
        guard !viewers.isEmpty else { return false }
        let userOk = viewers.contains { roster.contains($0) }
        guard userOk else { return false }

        return placeholderReadyToLog(
            match: match,
            effectiveCount: roster.count,
            teamSize: teamSize
        )
    }

    static func winningSide(
        match: BracketMatchSnapshot,
        top: [String],
        bottom: [String],
        teamSize: Int
    ) -> BracketWinningSide? {
        guard isPlayed(match: match) else { return nil }
        let w = Set(match.winnerProfileIds ?? [])
        if w.isEmpty { return nil }
        let topSet = Set(top)
        let bottomSet = Set(bottom)
        let topFull = top.count == teamSize
        let bottomFull = bottom.count == teamSize
        if topFull && w == topSet { return .top }
        if bottomFull && w == bottomSet { return .bottom }
        if topFull && bottomFull { return .ambiguous }
        if !top.isEmpty && w.isSubset(of: topSet) { return .top }
        if !bottom.isEmpty && w.isSubset(of: bottomSet) { return .bottom }
        return .ambiguous
    }
}
