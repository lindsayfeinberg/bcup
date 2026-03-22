import Foundation

/// Serializes `profiles/{uid}` reads so concurrent callers share one Firestore `getDocument` (avoids offline storms at launch).
actor ProfileFetchGate {
    static let shared = ProfileFetchGate()

    private var inflight: [String: Task<ProfileRecord?, Error>] = [:]

    func run(userId: String, operation: @Sendable @escaping () async throws -> ProfileRecord?) async throws -> ProfileRecord? {
        if let existing = inflight[userId] {
            return try await existing.value
        }
        let task = Task { try await operation() }
        inflight[userId] = task
        defer { inflight[userId] = nil }
        return try await task.value
    }
}
