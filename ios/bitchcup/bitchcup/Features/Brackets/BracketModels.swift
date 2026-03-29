import Foundation

struct BracketSnapshot: Decodable {
    let communityId: String
    let seedMethod: SeedMethod?
    let status: String
    let teamSize: Int
    let rounds: [BracketRoundSnapshot]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        communityId = try c.decode(String.self, forKey: .communityId)
        status = try c.decode(String.self, forKey: .status)
        teamSize = try c.decode(Int.self, forKey: .teamSize)
        rounds = try c.decode([BracketRoundSnapshot].self, forKey: .rounds)
        if let rawSeedMethod = try c.decodeIfPresent(String.self, forKey: .seedMethod) {
            seedMethod = SeedMethod(rawValue: rawSeedMethod)
        } else {
            seedMethod = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case communityId
        case seedMethod
        case status
        case teamSize
        case rounds
    }
}

struct BracketRoundSnapshot: Decodable {
    let roundNumber: Int
    let matches: [BracketMatchSnapshot]
}

struct BracketMatchSnapshot: Decodable, Identifiable {
    let matchId: String
    let roundNumber: Int
    let participantProfileIds: [String]?
    let winnerProfileIds: [String]?
    let loserProfileIds: [String]?
    let feederMatchIds: [String]?

    var id: String { matchId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        matchId = try c.decode(String.self, forKey: .matchId)
        roundNumber = try c.decode(Int.self, forKey: .roundNumber)
        participantProfileIds = try c.decodeIfPresent([String].self, forKey: .participantProfileIds)
        winnerProfileIds = try c.decodeIfPresent([String].self, forKey: .winnerProfileIds)
        loserProfileIds = try c.decodeIfPresent([String].self, forKey: .loserProfileIds)
        feederMatchIds = try c.decodeIfPresent([String].self, forKey: .feederMatchIds)
    }

    enum CodingKeys: String, CodingKey {
        case matchId
        case roundNumber
        case participantProfileIds
        case winnerProfileIds
        case loserProfileIds
        case feederMatchIds
    }
}
