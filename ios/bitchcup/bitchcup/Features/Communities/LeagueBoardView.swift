import FirebaseFirestore
import SwiftUI

/// Single-thread league board (Phase C3): live listener for recent messages, load-older pagination, composer.
@MainActor
struct LeagueBoardView: View {
    let communityId: String

    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var sessionManager: AppSessionManager

    private let pageSize = 40

    private var bracketAccentColor: Color {
        Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)
    }

    private var fieldPlaceholderColor: Color {
        Color(red: 207.0 / 255.0, green: 106.0 / 255.0, blue: 84.0 / 255.0)
    }

    @State private var listenerDocs: [QueryDocumentSnapshot] = []
    @State private var olderDocs: [QueryDocumentSnapshot] = []
    @State private var nameMap: [String: String] = [:]
    @State private var listenerRegistration: ListenerRegistration?
    @State private var hasMoreOlder = false
    @State private var isLoadingOlder = false
    @State private var olderLoadError: String?
    @State private var composeText = ""
    @State private var isSending = false
    @State private var sendError: String?
    @State private var listenerError: String?
    @FocusState private var composeFieldFocused: Bool
    @State private var messagePendingDeletion: LeagueBoardMessage?
    @State private var showDeleteMessageConfirm = false
    @State private var deleteMessageError: String?

    private var combinedSnapshots: [QueryDocumentSnapshot] {
        var byId: [String: QueryDocumentSnapshot] = [:]
        for d in olderDocs + listenerDocs {
            byId[d.documentID] = d
        }
        return byId.values.sorted { a, b in
            let ta = (a.data()["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
            let tb = (b.data()["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
            if ta != tb { return ta < tb }
            return a.documentID < b.documentID
        }
    }

    private var displayRows: [LeagueBoardMessage] {
        combinedSnapshots.compactMap { doc in
            Self.leagueBoardMessage(from: doc, authorDisplayName: authorDisplayLabel(forAuthorId: doc))
        }
    }

    /// Roster- and membership-resolved names; never show raw `profileId` in the UI.
    private func authorDisplayLabel(forAuthorId doc: QueryDocumentSnapshot) -> String {
        guard let authorId = doc.data()["authorProfileId"] as? String else {
            return "Member"
        }
        return authorDisplayLabel(forProfileId: authorId)
    }

    private func authorDisplayLabel(forProfileId authorId: String) -> String {
        if let raw = nameMap[authorId] {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "Member"
    }

    private func preloadRosterDisplayNames() async {
        do {
            let rows = try await container.communityService.fetchMembers(communityId: communityId)
            var next = nameMap
            for row in rows {
                let trimmed = row.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    next[row.profileId] = row.displayName
                }
            }
            nameMap = next
        } catch {
            // Roster is best-effort; listener + resolveBoardAuthorDisplayNames still backfill.
        }
    }

    private var canSend: Bool {
        !isSending && !composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if let deleteMessageError {
                Text(deleteMessageError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }
            if let listenerError {
                Text(listenerError)
                    .font(.custom("NeueHaasDisplay-Light", size: 14))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if hasMoreOlder {
                            Button {
                                Task { await loadOlder() }
                            } label: {
                                if isLoadingOlder {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Text("Load older messages")
                                        .font(.custom("NeueHaasDisplay-Mediu", size: 15))
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .disabled(isLoadingOlder)
                            .padding(.vertical, 8)
                        }
                        if let olderLoadError {
                            Text(olderLoadError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        ForEach(displayRows) { row in
                            messageBubble(row: row)
                                .id(row.id)
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: displayRows.count) { _, _ in
                    if let id = displayRows.last?.id {
                        withAnimation {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .navigationTitle("Board")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                CommunityFlowBackToolbarButton()
            }
        }
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .background(Color.white)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack(alignment: .bottom, spacing: 12) {
                    TextField(
                        "",
                        text: $composeText,
                        prompt: Text("Message").foregroundStyle(fieldPlaceholderColor),
                        axis: .vertical
                    )
                    .font(.custom("NeueHaasDisplay-Roman", size: 20))
                    .foregroundStyle(bracketAccentColor)
                    .textFieldStyle(.plain)
                    .lineLimit(1 ... 6)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(bracketAccentColor, lineWidth: 2)
                    )
                    .tint(bracketAccentColor)
                    .focused($composeFieldFocused)

                    Button {
                        Task { await send() }
                    } label: {
                        if isSending {
                            ProgressView()
                                .frame(width: 56, height: 48)
                        } else {
                            Text("Send")
                                .font(.custom("NeueHaasDisplay-Mediu", size: 20))
                                .frame(minWidth: 72, minHeight: 48)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(canSend ? Color.white : fieldPlaceholderColor)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(canSend ? bracketAccentColor : Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(canSend ? Color.clear : bracketAccentColor.opacity(0.45), lineWidth: 2)
                    )
                    .disabled(!canSend)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(UIColor.systemBackground))

                if let sendError {
                    Text(sendError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
        }
        .task(id: communityId) {
            await preloadRosterDisplayNames()
        }
        .onAppear { attachListener() }
        .onDisappear {
            listenerRegistration?.remove()
            listenerRegistration = nil
        }
        .refreshable {
            olderDocs = []
            attachListener()
        }
        .alert("Remove this message?", isPresented: $showDeleteMessageConfirm) {
            Button("Cancel", role: .cancel) {
                messagePendingDeletion = nil
            }
            Button("Remove", role: .destructive) {
                if let m = messagePendingDeletion {
                    Task { await deleteBoardMessage(m) }
                }
                messagePendingDeletion = nil
            }
        } message: {
            Text("The message is permanently removed and the action is logged.")
        }
    }

    private func messageBubble(row: LeagueBoardMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.authorDisplayName)
                    .font(.custom("NeueHaasDisplay-Bold", size: 14))
                    .foregroundStyle(bracketAccentColor)
                Spacer()
                Text(row.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(row.text)
                .font(.custom("NeueHaasDisplay-Mediu", size: 16))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
        .contextMenu {
            if sessionManager.isPlatformAdmin {
                Button("Remove message", role: .destructive) {
                    deleteMessageError = nil
                    messagePendingDeletion = row
                    showDeleteMessageConfirm = true
                }
            }
        }
    }

    private func deleteBoardMessage(_ message: LeagueBoardMessage) async {
        deleteMessageError = nil
        do {
            try await container.platformAdminService.deleteLeagueMessage(
                communityId: communityId,
                messageId: message.id
            )
        } catch {
            deleteMessageError = error.localizedDescription
        }
    }

    private func attachListener() {
        listenerRegistration?.remove()
        listenerRegistration = nil
        let db = AppFirestore.db()
        let q = db.collection("communities").document(communityId).collection("messages")
            .whereField("deleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .order(by: FieldPath.documentID(), descending: true)
            .limit(to: pageSize)
        listenerRegistration = q.addSnapshotListener { snapshot, error in
            Task { @MainActor in
                if let error {
                    listenerError = error.localizedDescription
                    return
                }
                guard let snapshot else { return }
                listenerError = nil
                listenerDocs = snapshot.documents
                hasMoreOlder = !snapshot.documents.isEmpty && snapshot.documents.count == pageSize
                await refreshNames(for: snapshot.documents)
            }
        }
    }

    private func refreshNames(for docs: [QueryDocumentSnapshot]) async {
        let ids = docs.compactMap { $0.data()["authorProfileId"] as? String }
        let mergedIds = Array(Set(ids))
        let fetched = await container.communityService.resolveBoardAuthorDisplayNames(
            communityId: communityId,
            profileIds: mergedIds
        )
        for (k, v) in fetched { nameMap[k] = v }
    }

    private func loadOlder() async {
        guard let oldestSnap = combinedSnapshots.first else { return }
        guard !isLoadingOlder else { return }
        isLoadingOlder = true
        olderLoadError = nil
        defer { isLoadingOlder = false }
        do {
            let next = try await container.communityService.fetchLeagueBoardMessagesOlderThan(
                communityId: communityId,
                startAfter: oldestSnap,
                limit: pageSize
            )
            if next.isEmpty {
                hasMoreOlder = false
            } else {
                olderDocs.insert(contentsOf: next, at: 0)
                hasMoreOlder = next.count == pageSize
                await refreshNames(for: next)
            }
        } catch {
            olderLoadError = error.localizedDescription
        }
    }

    private func send() async {
        isSending = true
        sendError = nil
        defer { isSending = false }
        do {
            try await container.communityService.postLeagueBoardMessage(
                communityId: communityId,
                text: composeText
            )
            composeText = ""
            composeFieldFocused = false
        } catch {
            sendError = error.localizedDescription
        }
    }

    private static func leagueBoardMessage(
        from doc: QueryDocumentSnapshot,
        authorDisplayName: String
    ) -> LeagueBoardMessage? {
        let data = doc.data()
        guard let author = data["authorProfileId"] as? String,
              let text = data["text"] as? String,
              let ts = data["createdAt"] as? Timestamp
        else {
            return nil
        }
        let deleted = (data["deleted"] as? Bool) ?? false
        if deleted { return nil }
        return LeagueBoardMessage(
            id: doc.documentID,
            authorProfileId: author,
            authorDisplayName: authorDisplayName,
            text: text,
            createdAt: ts.dateValue()
        )
    }
}
