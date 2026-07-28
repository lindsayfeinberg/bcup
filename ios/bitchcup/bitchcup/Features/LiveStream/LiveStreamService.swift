import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Join credentials for a LiveKit room (returned by `startLiveStream` / `joinLiveStreamAsViewer`).
struct LiveStreamSession: Hashable {
    let streamId: String
    let roomName: String
    let livekitUrl: String
    let token: String
}

struct LiveStreamSummary: Identifiable, Hashable {
    let streamId: String
    let communityId: String
    let hostUserId: String
    let hostDisplayName: String
    let viewerCount: Int
    let startedAt: Date
    var id: String { streamId }
}

enum LiveStreamMessageType: String {
    case chat
    case reaction
}

struct LiveStreamMessage: Identifiable, Hashable {
    let id: String
    let authorProfileId: String
    let type: LiveStreamMessageType
    let text: String?
    let emoji: String?
    let createdAt: Date
}

/// Live-updating status + viewer count for a stream doc (host and viewer screens both show this).
struct LiveStreamStatusUpdate: Equatable {
    let status: String
    let viewerCount: Int
}

enum LiveStreamServiceError: LocalizedError {
    case invalidResponse
    case emptyCommunityId
    case emptyStreamId

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Unexpected response from server."
        case .emptyCommunityId: return "Choose a league to go live in."
        case .emptyStreamId: return "Missing stream id."
        }
    }
}

@MainActor
protocol LiveStreamServiceProtocol: AnyObject {
    func startLiveStream(communityId: String) async throws -> LiveStreamSession
    func endLiveStream(streamId: String) async throws
    func joinLiveStreamAsViewer(streamId: String) async throws -> LiveStreamSession
    func leaveLiveStreamAsViewer(streamId: String) async throws
    /// Streams currently live across the given leagues (feed "live now" banner); yields the
    /// merged list on every change so the banner appears/disappears without a manual refresh.
    func observeActiveLiveStreams(communityIds: [String]) -> AsyncStream<[LiveStreamSummary]>
    func sendChatMessage(streamId: String, text: String) async throws
    func sendReaction(streamId: String, emoji: String) async throws
    /// Yields the full message list on every change; stream ends when the caller stops iterating.
    func observeMessages(streamId: String) -> AsyncStream<[LiveStreamMessage]>
    /// Yields `status` ("live" / "ended") and `viewerCount` on every change to the stream doc.
    func observeStream(streamId: String) -> AsyncStream<LiveStreamStatusUpdate>
}

@MainActor
final class LiveStreamService: LiveStreamServiceProtocol {
    /// Firestore `whereIn` hard limit (matches the chunking convention in `GameLogService`'s feed queries).
    private static let whereInChunkSize = 10

    func startLiveStream(communityId: String) async throws -> LiveStreamSession {
        let cid = communityId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { throw LiveStreamServiceError.emptyCommunityId }
        do {
            let result = try await CallableTransport.post(
                functionName: "startLiveStream",
                payload: ["communityId": cid]
            )
            let data = try CallableTransport.unwrapEnvelope(result)
            return try Self.session(from: data)
        } catch {
            throw CallableTransport.mapCallableNetworkError(error)
        }
    }

    func endLiveStream(streamId: String) async throws {
        let sid = streamId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty else { throw LiveStreamServiceError.emptyStreamId }
        do {
            let result = try await CallableTransport.post(functionName: "endLiveStream", payload: ["streamId": sid])
            _ = try CallableTransport.unwrapEnvelope(result)
        } catch {
            throw CallableTransport.mapCallableNetworkError(error)
        }
    }

    func joinLiveStreamAsViewer(streamId: String) async throws -> LiveStreamSession {
        let sid = streamId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty else { throw LiveStreamServiceError.emptyStreamId }
        do {
            let result = try await CallableTransport.post(
                functionName: "joinLiveStreamAsViewer",
                payload: ["streamId": sid]
            )
            let data = try CallableTransport.unwrapEnvelope(result)
            return try Self.session(from: data)
        } catch {
            throw CallableTransport.mapCallableNetworkError(error)
        }
    }

    func leaveLiveStreamAsViewer(streamId: String) async throws {
        let sid = streamId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty else { throw LiveStreamServiceError.emptyStreamId }
        do {
            let result = try await CallableTransport.post(
                functionName: "leaveLiveStreamAsViewer",
                payload: ["streamId": sid]
            )
            _ = try CallableTransport.unwrapEnvelope(result)
        } catch {
            throw CallableTransport.mapCallableNetworkError(error)
        }
    }

    func observeActiveLiveStreams(communityIds: [String]) -> AsyncStream<[LiveStreamSummary]> {
        let unique = Array(Set(
            communityIds
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        ))
        return AsyncStream { continuation in
            guard !unique.isEmpty else {
                continuation.yield([])
                continuation.finish()
                return
            }

            let chunks = unique.chunked(into: Self.whereInChunkSize)
            var summariesByChunkIndex: [Int: [LiveStreamSummary]] = [:]
            var listeners: [ListenerRegistration] = []

            func emitMerged() {
                let merged = summariesByChunkIndex.values.flatMap { $0 }
                continuation.yield(merged.sorted { $0.startedAt > $1.startedAt })
            }

            for (index, chunk) in chunks.enumerated() {
                let listener = AppFirestore.db()
                    .collection("liveStreams")
                    .whereField("communityId", in: chunk)
                    .whereField("status", isEqualTo: "live")
                    .addSnapshotListener { snapshot, _ in
                        guard let snapshot else { return }
                        summariesByChunkIndex[index] = snapshot.documents.compactMap(Self.summary(from:))
                        emitMerged()
                    }
                listeners.append(listener)
            }

            continuation.onTermination = { _ in
                listeners.forEach { $0.remove() }
            }
        }
    }

    func sendChatMessage(streamId: String, text: String) async throws {
        let sid = streamId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty, !trimmed.isEmpty else { return }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw LiveStreamServiceError.invalidResponse
        }
        let doc = AppFirestore.db()
            .collection("liveStreams").document(sid)
            .collection("messages").document()
        try await doc.setData([
            "id": doc.documentID,
            "streamId": sid,
            "authorProfileId": uid,
            "type": LiveStreamMessageType.chat.rawValue,
            "text": String(trimmed.prefix(500)),
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    func sendReaction(streamId: String, emoji: String) async throws {
        let sid = streamId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty, !trimmedEmoji.isEmpty else { return }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw LiveStreamServiceError.invalidResponse
        }
        let doc = AppFirestore.db()
            .collection("liveStreams").document(sid)
            .collection("messages").document()
        try await doc.setData([
            "id": doc.documentID,
            "streamId": sid,
            "authorProfileId": uid,
            "type": LiveStreamMessageType.reaction.rawValue,
            "emoji": String(trimmedEmoji.prefix(8)),
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    func observeMessages(streamId: String) -> AsyncStream<[LiveStreamMessage]> {
        let sid = streamId.trimmingCharacters(in: .whitespacesAndNewlines)
        return AsyncStream { continuation in
            guard !sid.isEmpty else {
                continuation.finish()
                return
            }
            let listener = AppFirestore.db()
                .collection("liveStreams").document(sid)
                .collection("messages")
                .order(by: "createdAt", descending: false)
                .limit(toLast: 200)
                .addSnapshotListener { snapshot, _ in
                    guard let snapshot else { return }
                    continuation.yield(snapshot.documents.compactMap(Self.message(from:)))
                }
            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    func observeStream(streamId: String) -> AsyncStream<LiveStreamStatusUpdate> {
        let sid = streamId.trimmingCharacters(in: .whitespacesAndNewlines)
        return AsyncStream { continuation in
            guard !sid.isEmpty else {
                continuation.finish()
                return
            }
            let listener = AppFirestore.db()
                .collection("liveStreams").document(sid)
                .addSnapshotListener { snapshot, _ in
                    guard let data = snapshot?.data(), let status = data["status"] as? String else { return }
                    let viewerCount = (data["viewerCount"] as? Int) ?? (data["viewerCount"] as? NSNumber)?.intValue ?? 0
                    continuation.yield(LiveStreamStatusUpdate(status: status, viewerCount: viewerCount))
                }
            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    private static func session(from data: [String: Any]) throws -> LiveStreamSession {
        guard let streamId = data["streamId"] as? String,
              let roomName = data["roomName"] as? String,
              let livekitUrl = data["livekitUrl"] as? String,
              let token = data["token"] as? String
        else {
            throw LiveStreamServiceError.invalidResponse
        }
        return LiveStreamSession(streamId: streamId, roomName: roomName, livekitUrl: livekitUrl, token: token)
    }

    private static func summary(from document: QueryDocumentSnapshot) -> LiveStreamSummary? {
        let d = document.data()
        guard let communityId = d["communityId"] as? String,
              let hostUserId = d["hostUserId"] as? String
        else {
            return nil
        }
        let hostDisplayName = d["hostDisplayName"] as? String ?? ""
        let viewerCount = (d["viewerCount"] as? Int) ?? (d["viewerCount"] as? NSNumber)?.intValue ?? 0
        let startedAt = (d["startedAt"] as? Timestamp)?.dateValue() ?? Date()
        return LiveStreamSummary(
            streamId: document.documentID,
            communityId: communityId,
            hostUserId: hostUserId,
            hostDisplayName: hostDisplayName,
            viewerCount: viewerCount,
            startedAt: startedAt
        )
    }

    private static func message(from document: QueryDocumentSnapshot) -> LiveStreamMessage? {
        let d = document.data()
        guard let authorProfileId = d["authorProfileId"] as? String,
              let typeRaw = d["type"] as? String,
              let type = LiveStreamMessageType(rawValue: typeRaw)
        else {
            return nil
        }
        let createdAt = (d["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        return LiveStreamMessage(
            id: document.documentID,
            authorProfileId: authorProfileId,
            type: type,
            text: d["text"] as? String,
            emoji: d["emoji"] as? String,
            createdAt: createdAt
        )
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
