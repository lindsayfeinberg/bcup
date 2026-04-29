import Foundation

struct AdminCommunitySummary: Identifiable, Hashable {
    let communityId: String
    let name: String
    let memberCount: Int
    let createdByProfileId: String

    var id: String { communityId }
}

struct AdminCommunitiesPageResult {
    let items: [AdminCommunitySummary]
    let nextCursor: String?
    let hasMore: Bool
}

struct AdminGameLogSummary: Identifiable, Hashable {
    let gameLogId: String
    let communityId: String
    /// `communities/{communityId}.name` when resolved by `adminListGameLogs`.
    let communityName: String
    let gameType: String
    let createdByProfileId: String
    let createdAtMillis: Int64

    var id: String { gameLogId }

    /// Primary label for the league row (name, or a short fallback).
    var leagueDisplayTitle: String {
        let n = communityName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { return n }
        let id = communityId.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty { return "Unknown league" }
        return "League \(id)"
    }
}

struct AdminGameLogsCursor: Equatable {
    let createdAtMillis: Int64
    let documentId: String
}

struct AdminGameLogsPageResult {
    let items: [AdminGameLogSummary]
    let nextCursor: AdminGameLogsCursor?
    let hasMore: Bool
}

struct AdminActionSummary: Identifiable, Hashable {
    let adminActionId: String
    let actorUid: String
    let actorDisplayName: String
    let action: String
    let targetCommunityId: String
    let targetProfileId: String
    let targetGameLogId: String
    let targetMessageId: String
    let createdAtMillis: Int64

    var id: String { adminActionId }
}

struct AdminActionsCursor: Equatable {
    let createdAtMillis: Int64
    let documentId: String
}

struct AdminActionsPageResult {
    let items: [AdminActionSummary]
    let nextCursor: AdminActionsCursor?
    let hasMore: Bool
}

@MainActor
protocol PlatformAdminServiceProtocol: AnyObject {
    func listCommunitiesPage(startAfterCommunityId: String?, pageSize: Int) async throws -> AdminCommunitiesPageResult
    func listGameLogsPage(
        communityId: String?,
        cursor: AdminGameLogsCursor?,
        pageSize: Int
    ) async throws -> AdminGameLogsPageResult
    func listAdminActionsPage(
        action: String?,
        targetCommunityId: String?,
        cursor: AdminActionsCursor?,
        pageSize: Int
    ) async throws -> AdminActionsPageResult
    func kickMember(communityId: String, profileId: String) async throws
    func deleteGameLog(gameLogId: String) async throws
    /// Operator-only: writes outcome fields via Cloud Function (Admin SDK).
    func adminUpdateGameLog(payload: GameLogUpdatePayload) async throws
    func deleteLeagueMessage(communityId: String, messageId: String) async throws
}

@MainActor
final class PlatformAdminService: PlatformAdminServiceProtocol {
    func listCommunitiesPage(startAfterCommunityId: String?, pageSize: Int) async throws -> AdminCommunitiesPageResult {
        var payload: [String: Any] = ["pageSize": pageSize]
        if let s = startAfterCommunityId, !s.isEmpty {
            payload["startAfterCommunityId"] = s
        }
        let result = try await CallableTransport.post(functionName: "adminListCommunities", payload: payload)
        let data = try CallableTransport.unwrapEnvelope(result)
        let rawItems = data["items"] as? [[String: Any]] ?? []
        let items = rawItems.compactMap { row -> AdminCommunitySummary? in
            guard let id = row["communityId"] as? String else { return nil }
            return AdminCommunitySummary(
                communityId: id,
                name: row["name"] as? String ?? "",
                memberCount: Self.intValue(row["memberCount"]),
                createdByProfileId: row["createdByProfileId"] as? String ?? ""
            )
        }
        let next = data["nextCursor"] as? String
        let hasMore = data["hasMore"] as? Bool ?? false
        return AdminCommunitiesPageResult(items: items, nextCursor: next, hasMore: hasMore)
    }

    func listGameLogsPage(
        communityId: String?,
        cursor: AdminGameLogsCursor?,
        pageSize: Int
    ) async throws -> AdminGameLogsPageResult {
        var payload: [String: Any] = ["pageSize": pageSize]
        if let cid = communityId?.trimmingCharacters(in: .whitespacesAndNewlines), !cid.isEmpty {
            payload["communityId"] = cid
        }
        if let cursor {
            payload["cursor"] = [
                "createdAtMillis": cursor.createdAtMillis,
                "documentId": cursor.documentId,
            ]
        }
        let result = try await CallableTransport.post(functionName: "adminListGameLogs", payload: payload)
        let data = try CallableTransport.unwrapEnvelope(result)
        let rawItems = data["items"] as? [[String: Any]] ?? []
        let items = rawItems.compactMap { row -> AdminGameLogSummary? in
            guard let id = row["gameLogId"] as? String else { return nil }
            return AdminGameLogSummary(
                gameLogId: id,
                communityId: row["communityId"] as? String ?? "",
                communityName: row["communityName"] as? String ?? "",
                gameType: row["gameType"] as? String ?? "",
                createdByProfileId: row["createdByProfileId"] as? String ?? "",
                createdAtMillis: Self.int64Value(row["createdAtMillis"])
            )
        }
        var nextCursor: AdminGameLogsCursor?
        if let cur = data["nextCursor"] as? [String: Any],
           let docId = cur["documentId"] as? String {
            let millis = Self.int64Value(cur["createdAtMillis"])
            nextCursor = AdminGameLogsCursor(createdAtMillis: millis, documentId: docId)
        }
        let hasMore = data["hasMore"] as? Bool ?? false
        return AdminGameLogsPageResult(items: items, nextCursor: nextCursor, hasMore: hasMore)
    }

    func listAdminActionsPage(
        action: String?,
        targetCommunityId: String?,
        cursor: AdminActionsCursor?,
        pageSize: Int
    ) async throws -> AdminActionsPageResult {
        var payload: [String: Any] = ["pageSize": pageSize]
        if let action = action?.trimmingCharacters(in: .whitespacesAndNewlines), !action.isEmpty {
            payload["action"] = action
        }
        if let cid = targetCommunityId?.trimmingCharacters(in: .whitespacesAndNewlines), !cid.isEmpty {
            payload["targetCommunityId"] = cid
        }
        if let cursor {
            payload["cursor"] = [
                "createdAtMillis": cursor.createdAtMillis,
                "documentId": cursor.documentId,
            ]
        }
        let result = try await CallableTransport.post(functionName: "adminListActions", payload: payload)
        let data = try CallableTransport.unwrapEnvelope(result)
        let rawItems = data["items"] as? [[String: Any]] ?? []
        let items = rawItems.compactMap { row -> AdminActionSummary? in
            guard let id = row["adminActionId"] as? String else { return nil }
            return AdminActionSummary(
                adminActionId: id,
                actorUid: row["actorUid"] as? String ?? "",
                actorDisplayName: row["actorDisplayName"] as? String ?? "",
                action: row["action"] as? String ?? "",
                targetCommunityId: row["targetCommunityId"] as? String ?? "",
                targetProfileId: row["targetProfileId"] as? String ?? "",
                targetGameLogId: row["targetGameLogId"] as? String ?? "",
                targetMessageId: row["targetMessageId"] as? String ?? "",
                createdAtMillis: Self.int64Value(row["createdAtMillis"])
            )
        }
        var nextCursor: AdminActionsCursor?
        if let cur = data["nextCursor"] as? [String: Any],
           let docId = cur["documentId"] as? String {
            let millis = Self.int64Value(cur["createdAtMillis"])
            nextCursor = AdminActionsCursor(createdAtMillis: millis, documentId: docId)
        }
        let hasMore = data["hasMore"] as? Bool ?? false
        return AdminActionsPageResult(items: items, nextCursor: nextCursor, hasMore: hasMore)
    }

    func kickMember(communityId: String, profileId: String) async throws {
        let cid = communityId.trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = profileId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty, !pid.isEmpty else { throw CommunityServiceError.invalidResponse }
        let result = try await CallableTransport.post(
            functionName: "adminKickMember",
            payload: ["communityId": cid, "profileId": pid]
        )
        _ = try CallableTransport.unwrapEnvelope(result)
    }

    func deleteGameLog(gameLogId: String) async throws {
        let id = gameLogId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw CommunityServiceError.invalidResponse }
        let result = try await CallableTransport.post(
            functionName: "adminDeleteGameLog",
            payload: ["gameLogId": id]
        )
        _ = try CallableTransport.unwrapEnvelope(result)
    }

    func adminUpdateGameLog(payload: GameLogUpdatePayload) async throws {
        let body = Self.encodeGameLogUpdatePayloadForAdminCallable(payload)
        let result = try await CallableTransport.post(
            functionName: "adminUpdateGameLog",
            payload: body
        )
        _ = try CallableTransport.unwrapEnvelope(result)
    }

    func deleteLeagueMessage(communityId: String, messageId: String) async throws {
        let cid = communityId.trimmingCharacters(in: .whitespacesAndNewlines)
        let mid = messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty, !mid.isEmpty else { throw CommunityServiceError.invalidResponse }
        let result = try await CallableTransport.post(
            functionName: "adminDeleteLeagueMessage",
            payload: ["communityId": cid, "messageId": mid]
        )
        _ = try CallableTransport.unwrapEnvelope(result)
    }

    private static func intValue(_ v: Any?) -> Int {
        if let i = v as? Int { return i }
        if let n = v as? NSNumber { return n.intValue }
        if let d = v as? Double { return Int(d) }
        return 0
    }

    private static func int64Value(_ v: Any?) -> Int64 {
        if let i = v as? Int64 { return i }
        if let i = v as? Int { return Int64(i) }
        if let n = v as? NSNumber { return n.int64Value }
        if let d = v as? Double { return Int64(d) }
        return 0
    }

    /// Mirrors `GameLogService.updateGameLog` field set so the callable can validate and apply the same patch.
    private static func encodeGameLogUpdatePayloadForAdminCallable(_ p: GameLogUpdatePayload) -> [String: Any] {
        var d: [String: Any] = [
            "gameLogId": p.gameLogId,
            "participantProfileIds": p.participantProfileIds,
            "winnerProfileIds": p.winnerProfileIds,
            "loserProfileIds": p.loserProfileIds,
            "photoUrls": p.photoUrls,
            "pongStats": p.pongStats ?? NSNull(),
            "beerBallStats": p.beerBallStats ?? NSNull(),
            "battlePongStats": p.battlePongStats ?? NSNull(),
            "baseballStats": p.baseballStats ?? NSNull(),
            "crossfireStats": p.crossfireStats ?? NSNull()
        ]
        if let m = p.mvpProfileId {
            d["mvpProfileId"] = m
        } else {
            d["mvpProfileId"] = NSNull()
        }
        if let m = p.lvpProfileId {
            d["lvpProfileId"] = m
        } else {
            d["lvpProfileId"] = NSNull()
        }
        if let n = p.notes {
            d["notes"] = n
        } else {
            d["notes"] = NSNull()
        }
        return sanitizeJSONObjectForCallable(d) as? [String: Any] ?? d
    }

    /// `JSONSerialization` rejects some nested Swift/Firestore-bridged values; normalize to JSON-safe plist types.
    private static func sanitizeJSONObjectForCallable(_ value: Any) -> Any {
        switch value {
        case is NSNull:
            return NSNull()
        case let s as String:
            return s
        case let b as Bool:
            return b
        case let i as Int:
            return i
        case let i as Int8:
            return Int(i)
        case let i as Int16:
            return Int(i)
        case let i as Int32:
            return Int(i)
        case let i as Int64:
            return NSNumber(value: i)
        case let i as UInt:
            return NSNumber(value: i)
        case let i as UInt32:
            return NSNumber(value: i)
        case let i as UInt64:
            return NSNumber(value: i)
        case let d as Double:
            return d.isFinite ? d : 0.0
        case let f as Float:
            let d = Double(f)
            return d.isFinite ? d : 0.0
        case let n as NSNumber:
            return n
        case let m as [String: Int]:
            var o: [String: Any] = [:]
            o.reserveCapacity(m.count)
            for (k, v) in m {
                o[k] = NSNumber(value: v)
            }
            return o
        case let m as [String: Double]:
            return m
        case let arr as [Any]:
            return arr.map { sanitizeJSONObjectForCallable($0) }
        case let dict as [String: Any]:
            var o: [String: Any] = [:]
            o.reserveCapacity(dict.count)
            for (k, v) in dict {
                o[k] = sanitizeJSONObjectForCallable(v)
            }
            return o
        case let dict as NSDictionary:
            var o: [String: Any] = [:]
            dict.enumerateKeysAndObjects { key, val, _ in
                guard let k = key as? String else { return }
                o[k] = sanitizeJSONObjectForCallable(val)
            }
            return o
        default:
            return String(describing: value)
        }
    }
}
