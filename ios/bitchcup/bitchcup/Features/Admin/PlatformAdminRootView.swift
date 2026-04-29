import SwiftUI
import FirebaseFirestore

/// Typography and accent aligned with league / feed surfaces (`CommunityDetailView`, `CommunitiesListView`).
private enum AdminChrome {
    static let accent = Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)
    static let title = Font.custom("NeueHaasDisplay-Bold", size: 28)
    static let sectionHeader = Font.custom("NeueHaasDisplay-Bold", size: 15)
    static let rowTitle = Font.custom("NeueHaasDisplay-Mediu", size: 20)
    static let rowMeta = Font.custom("NeueHaasDisplay-Light", size: 15)
    static let body = Font.custom("NeueHaasDisplay-Roman", size: 16)
    static let button = Font.custom("NeueHaasDisplay-Mediu", size: 18)
}

/// Phase D1 identity + Phase D2 operator tools (lists, league detail, log delete).
struct PlatformAdminRootView: View {
    @EnvironmentObject private var sessionManager: AppSessionManager

    var body: some View {
        List {
            Section {
                if sessionManager.isPlatformAdmin {
                    Label {
                        Text("Operator token active")
                            .font(AdminChrome.body)
                    } icon: {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(AdminChrome.accent)
                    }
                    .foregroundStyle(.primary)
                } else {
                    Label {
                        Text("No platform operator claim on this token")
                            .font(AdminChrome.body)
                    } icon: {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundStyle(AdminChrome.accent)
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("Identity")
                    .font(AdminChrome.sectionHeader)
                    .foregroundStyle(AdminChrome.accent)
                    .textCase(nil)
            } footer: {
                Text("Claims are set with the Firebase Admin SDK (see functions/scripts/setPlatformAdminClaim.js). Use Refresh after assigning or revoking.")
                    .font(AdminChrome.rowMeta)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.white)

            Section {
                Button {
                    Task { await sessionManager.refreshPlatformAdminTokenFromServer() }
                } label: {
                    Text("Refresh operator token")
                        .font(AdminChrome.button)
                        .foregroundStyle(AdminChrome.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            } header: {
                Text("Token")
                    .font(AdminChrome.sectionHeader)
                    .foregroundStyle(AdminChrome.accent)
                    .textCase(nil)
            }
            .listRowBackground(Color.white)

            if sessionManager.isPlatformAdmin {
                Section {
                    NavigationLink {
                        PlatformAdminLeaguesListView()
                    } label: {
                        HStack {
                            Text("Leagues")
                                .font(AdminChrome.rowTitle)
                                .foregroundStyle(.black)
                            Spacer()
                        }
                    }
                    NavigationLink {
                        PlatformAdminGameLogsListView()
                    } label: {
                        HStack {
                            Text("Game logs")
                                .font(AdminChrome.rowTitle)
                                .foregroundStyle(.black)
                            Spacer()
                        }
                    }
                    NavigationLink {
                        PlatformAdminAuditActionsListView()
                    } label: {
                        HStack {
                            Text("Audit log")
                                .font(AdminChrome.rowTitle)
                                .foregroundStyle(.black)
                            Spacer()
                        }
                    }
                } header: {
                    Text("Directory")
                        .font(AdminChrome.sectionHeader)
                        .foregroundStyle(AdminChrome.accent)
                        .textCase(nil)
                } footer: {
                    Text("Open a league to use the roster kick control or the league board message menu.")
                        .font(AdminChrome.rowMeta)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.white)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.white)
        .navigationTitle("Platform admin")
        .navigationBarTitleDisplayMode(.inline)
        .platformAdminNavigationMatchedBackButton()
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - Leagues

@MainActor
private struct PlatformAdminLeaguesListView: View {
    @EnvironmentObject private var container: DependencyContainer

    @State private var rows: [AdminCommunitySummary] = []
    @State private var nextCursor: String?
    @State private var hasMore = false
    @State private var isLoadingFirst = false
    @State private var isLoadingMore = false
    @State private var listError: String?

    private let pageSize = 25

    var body: some View {
        Group {
            if isLoadingFirst && rows.isEmpty {
                ProgressView("Loading leagues…")
                    .font(AdminChrome.rowMeta)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let listError {
                ContentUnavailableView(
                    "Couldn’t load leagues",
                    systemImage: "exclamationmark.triangle",
                    description: Text(listError).font(AdminChrome.rowMeta)
                )
            } else {
                List {
                    ForEach(rows) { league in
                        NavigationLink {
                            CommunityDetailView(communityId: league.communityId)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(league.name.isEmpty ? league.communityId : league.name)
                                    .font(AdminChrome.rowTitle)
                                    .foregroundStyle(.black)
                                Text("\(league.memberCount) members · \(league.communityId)")
                                    .font(AdminChrome.rowMeta)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .listRowBackground(Color.white)
                    }
                    if hasMore || isLoadingMore {
                        HStack {
                            Spacer()
                            if isLoadingMore {
                                ProgressView()
                            } else {
                                Button("Load more") {
                                    Task { await loadMore() }
                                }
                                .font(AdminChrome.button)
                                .foregroundStyle(AdminChrome.accent)
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.white)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.white)
            }
        }
        .background(Color.white)
        .navigationTitle("Leagues")
        .navigationBarTitleDisplayMode(.inline)
        .platformAdminNavigationMatchedBackButton()
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            await refresh(reset: true)
        }
        .refreshable {
            await refresh(reset: true)
        }
    }

    private func refresh(reset: Bool) async {
        if reset {
            isLoadingFirst = true
            listError = nil
            nextCursor = nil
            hasMore = false
            rows = []
        }
        defer { if reset { isLoadingFirst = false } }
        do {
            let page = try await container.platformAdminService.listCommunitiesPage(
                startAfterCommunityId: nil,
                pageSize: pageSize
            )
            rows = page.items
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            listError = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard let cursor = nextCursor, !cursor.isEmpty else { return }
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await container.platformAdminService.listCommunitiesPage(
                startAfterCommunityId: cursor,
                pageSize: pageSize
            )
            let existing = Set(rows.map(\.communityId))
            let merged = page.items.filter { !existing.contains($0.communityId) }
            rows.append(contentsOf: merged)
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            listError = error.localizedDescription
        }
    }
}

// MARK: - Game logs

private struct AdminGameLogEditSheetItem: Identifiable {
    let id: String
}

@MainActor
private struct PlatformAdminGameLogsListView: View {
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var sessionManager: AppSessionManager

    @State private var filterLeagueName: String = ""
    @State private var appliedLeagueName: String = ""
    @State private var rows: [AdminGameLogSummary] = []
    @State private var nextCursor: AdminGameLogsCursor?
    @State private var hasMore = false
    @State private var isLoadingFirst = false
    @State private var isLoadingMore = false
    @State private var listError: String?
    @State private var logPendingDelete: AdminGameLogSummary?
    @State private var deleteError: String?
    @State private var gameLogEditSheet: AdminGameLogEditSheetItem?

    private let pageSize = 25

    private var leagueNameFilterNormalized: String {
        appliedLeagueName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredRows: [AdminGameLogSummary] {
        let filter = leagueNameFilterNormalized
        guard !filter.isEmpty else { return rows }
        return rows.filter { row in
            row.leagueDisplayTitle.lowercased().contains(filter)
        }
    }

    var body: some View {
        Group {
            if isLoadingFirst && rows.isEmpty {
                ProgressView("Loading game logs…")
                    .font(AdminChrome.rowMeta)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let listError {
                ContentUnavailableView(
                    "Couldn’t load logs",
                    systemImage: "exclamationmark.triangle",
                    description: Text(listError).font(AdminChrome.rowMeta)
                )
            } else {
                List {
                    Section {
                        TextField("Optional league name filter", text: $filterLeagueName)
                            .font(AdminChrome.body)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Apply filter") {
                            appliedLeagueName = filterLeagueName
                        }
                        .font(AdminChrome.button)
                        .foregroundStyle(AdminChrome.accent)
                        if let deleteError {
                            Text(deleteError)
                                .font(AdminChrome.rowMeta)
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text("Filter")
                            .font(AdminChrome.sectionHeader)
                            .foregroundStyle(AdminChrome.accent)
                            .textCase(nil)
                    } footer: {
                        Text("Leave blank for all leagues.")
                            .font(AdminChrome.rowMeta)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.white)

                    ForEach(filteredRows) { log in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(log.gameType.replacingOccurrences(of: "_", with: " "))
                                .font(AdminChrome.rowTitle)
                                .foregroundStyle(.black)
                            Text(log.gameLogId)
                                .font(.custom("NeueHaasDisplay-Light", size: 13))
                                .foregroundStyle(.secondary)
                            Text(log.leagueDisplayTitle)
                                .font(AdminChrome.rowMeta)
                                .foregroundStyle(.primary)
                            Text(dateString(millis: log.createdAtMillis))
                                .font(AdminChrome.rowMeta)
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.white)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Edit") {
                                gameLogEditSheet = AdminGameLogEditSheetItem(id: log.gameLogId)
                            }
                            .tint(AdminChrome.accent)
                            Button("Delete", role: .destructive) {
                                logPendingDelete = log
                            }
                        }
                    }

                    if hasMore || isLoadingMore {
                        HStack {
                            Spacer()
                            if isLoadingMore {
                                ProgressView()
                            } else {
                                Button("Load more") {
                                    Task { await loadMore() }
                                }
                                .font(AdminChrome.button)
                                .foregroundStyle(AdminChrome.accent)
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.white)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.white)
            }
        }
        .background(Color.white)
        .navigationTitle("Game logs")
        .navigationBarTitleDisplayMode(.inline)
        .platformAdminNavigationMatchedBackButton()
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            await reloadFromStart()
        }
        .refreshable {
            await reloadFromStart()
        }
        .sheet(item: $gameLogEditSheet) { item in
            NavigationStack {
                NewGameLogFormView(editingGameLogId: item.id)
                    .environmentObject(container)
                    .environmentObject(sessionManager)
                    .navigationTitle("Edit game (admin)")
                    .navigationBarTitleDisplayMode(.inline)
                    .communityFlowNavigationBarChrome()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            CommunityFlowCloseToolbarButton {
                                gameLogEditSheet = nil
                            }
                        }
                    }
            }
        }
        .alert("Delete this game log?", isPresented: Binding(
            get: { logPendingDelete != nil },
            set: { if !$0 { logPendingDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                logPendingDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let log = logPendingDelete {
                    Task { await deleteLog(log) }
                }
                logPendingDelete = nil
            }
        } message: {
            Text("Odds and bracket state are reconciled on the server.")
                .font(AdminChrome.rowMeta)
        }
    }

    private func dateString(millis: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
        return d.formatted(date: .abbreviated, time: .shortened)
    }

    private func reloadFromStart() async {
        isLoadingFirst = true
        listError = nil
        nextCursor = nil
        hasMore = false
        rows = []
        defer { isLoadingFirst = false }
        do {
            let page = try await container.platformAdminService.listGameLogsPage(
                communityId: nil,
                cursor: nil,
                pageSize: pageSize
            )
            rows = await enrichRowsWithCommunityNamesIfNeeded(page.items)
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            listError = error.localizedDescription
        }
    }

    /// Callable may omit `communityName` on older deployments; operators can read `communities` directly.
    private func enrichRowsWithCommunityNamesIfNeeded(_ items: [AdminGameLogSummary]) async -> [AdminGameLogSummary] {
        let idsToResolve = Set(items.compactMap { item -> String? in
            let name = item.communityName.trimmingCharacters(in: .whitespacesAndNewlines)
            let cid = item.communityId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cid.isEmpty, name.isEmpty else { return nil }
            return cid
        })
        guard !idsToResolve.isEmpty else { return items }

        var nameByCommunityId: [String: String] = [:]
        let db = AppFirestore.db()
        await withTaskGroup(of: (String, String?).self) { group in
            for cid in idsToResolve {
                group.addTask {
                    let snap = try? await db.collection("communities").document(cid).getDocument()
                    guard let data = snap?.data() else { return (cid, nil) }
                    let raw = data["name"] as? String ?? ""
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (cid, trimmed.isEmpty ? nil : trimmed)
                }
            }
            for await (cid, name) in group {
                if let name {
                    nameByCommunityId[cid] = name
                }
            }
        }

        return items.map { item in
            guard let resolved = nameByCommunityId[item.communityId] else { return item }
            return AdminGameLogSummary(
                gameLogId: item.gameLogId,
                communityId: item.communityId,
                communityName: resolved,
                gameType: item.gameType,
                createdByProfileId: item.createdByProfileId,
                createdAtMillis: item.createdAtMillis
            )
        }
    }

    private func loadMore() async {
        guard let cursor = nextCursor else { return }
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await container.platformAdminService.listGameLogsPage(
                communityId: nil,
                cursor: cursor,
                pageSize: pageSize
            )
            let existing = Set(rows.map(\.gameLogId))
            let merged = page.items.filter { !existing.contains($0.gameLogId) }
            let enriched = await enrichRowsWithCommunityNamesIfNeeded(merged)
            rows.append(contentsOf: enriched)
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            listError = error.localizedDescription
        }
    }

    private func deleteLog(_ log: AdminGameLogSummary) async {
        deleteError = nil
        do {
            try await container.platformAdminService.deleteGameLog(gameLogId: log.gameLogId)
            rows.removeAll { $0.gameLogId == log.gameLogId }
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

// MARK: - Audit log

@MainActor
private struct PlatformAdminAuditActionsListView: View {
    @EnvironmentObject private var container: DependencyContainer

    @State private var filterAction: String = ""
    @State private var filterLeagueId: String = ""
    @State private var filterActorName: String = ""
    @State private var appliedAction: String = ""
    @State private var appliedLeagueId: String = ""
    @State private var appliedActorName: String = ""
    @State private var rows: [AdminActionSummary] = []
    @State private var nextCursor: AdminActionsCursor?
    @State private var hasMore = false
    @State private var isLoadingFirst = false
    @State private var isLoadingMore = false
    @State private var listError: String?

    private let pageSize = 25

    private var actionForQuery: String? {
        let t = appliedAction.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private var leagueForQuery: String? {
        let t = appliedLeagueId.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private var actorNameFilterNormalized: String {
        appliedActorName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredRows: [AdminActionSummary] {
        let actorFilter = actorNameFilterNormalized
        guard !actorFilter.isEmpty else { return rows }
        return rows.filter { row in
            let displayName = row.actorDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = row.actorUid.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = (displayName.isEmpty ? fallback : displayName).lowercased()
            return candidate.contains(actorFilter)
        }
    }

    var body: some View {
        Group {
            if isLoadingFirst && rows.isEmpty {
                ProgressView("Loading audit log…")
                    .font(AdminChrome.rowMeta)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let listError {
                ContentUnavailableView(
                    "Couldn’t load audit actions",
                    systemImage: "exclamationmark.triangle",
                    description: Text(listError).font(AdminChrome.rowMeta)
                )
            } else {
                List {
                    Section {
                        TextField("Optional action filter (e.g. deleteGameLog)", text: $filterAction)
                            .font(AdminChrome.body)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Optional league ID filter", text: $filterLeagueId)
                            .font(AdminChrome.body)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Optional actor username filter", text: $filterActorName)
                            .font(AdminChrome.body)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Apply filters") {
                            appliedAction = filterAction
                            appliedLeagueId = filterLeagueId
                            appliedActorName = filterActorName
                            Task { await reloadFromStart() }
                        }
                        .font(AdminChrome.button)
                        .foregroundStyle(AdminChrome.accent)
                    } header: {
                        Text("Filters")
                            .font(AdminChrome.sectionHeader)
                            .foregroundStyle(AdminChrome.accent)
                            .textCase(nil)
                    } footer: {
                        Text("Leave blank to view all operator actions.")
                            .font(AdminChrome.rowMeta)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.white)

                    ForEach(filteredRows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.action.isEmpty ? "unknownAction" : row.action)
                                .font(AdminChrome.rowTitle)
                                .foregroundStyle(.black)
                            Text("Actor: \(actorLabel(for: row))")
                                .font(AdminChrome.rowMeta)
                                .foregroundStyle(.secondary)
                            if !row.targetCommunityId.isEmpty {
                                Text("League: \(row.targetCommunityId)")
                                    .font(AdminChrome.rowMeta)
                                    .foregroundStyle(.secondary)
                            }
                            if !row.targetProfileId.isEmpty {
                                Text("Profile: \(row.targetProfileId)")
                                    .font(AdminChrome.rowMeta)
                                    .foregroundStyle(.secondary)
                            }
                            if !row.targetGameLogId.isEmpty {
                                Text("Game log: \(row.targetGameLogId)")
                                    .font(AdminChrome.rowMeta)
                                    .foregroundStyle(.secondary)
                            }
                            if !row.targetMessageId.isEmpty {
                                Text("Message: \(row.targetMessageId)")
                                    .font(AdminChrome.rowMeta)
                                    .foregroundStyle(.secondary)
                            }
                            Text(dateString(millis: row.createdAtMillis))
                                .font(AdminChrome.rowMeta)
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.white)
                    }

                    if hasMore || isLoadingMore {
                        HStack {
                            Spacer()
                            if isLoadingMore {
                                ProgressView()
                            } else {
                                Button("Load more") {
                                    Task { await loadMore() }
                                }
                                .font(AdminChrome.button)
                                .foregroundStyle(AdminChrome.accent)
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.white)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.white)
            }
        }
        .background(Color.white)
        .navigationTitle("Audit log")
        .navigationBarTitleDisplayMode(.inline)
        .platformAdminNavigationMatchedBackButton()
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            await reloadFromStart()
        }
        .refreshable {
            await reloadFromStart()
        }
    }

    private func dateString(millis: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
        return d.formatted(date: .abbreviated, time: .shortened)
    }

    private func actorLabel(for row: AdminActionSummary) -> String {
        let displayName = row.actorDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty { return displayName }
        let uid = row.actorUid.trimmingCharacters(in: .whitespacesAndNewlines)
        return uid.isEmpty ? "unknown" : uid
    }

    private func reloadFromStart() async {
        isLoadingFirst = true
        listError = nil
        nextCursor = nil
        hasMore = false
        rows = []
        defer { isLoadingFirst = false }
        do {
            let page = try await container.platformAdminService.listAdminActionsPage(
                action: actionForQuery,
                targetCommunityId: leagueForQuery,
                cursor: nil,
                pageSize: pageSize
            )
            rows = page.items
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            listError = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard let cursor = nextCursor else { return }
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await container.platformAdminService.listAdminActionsPage(
                action: actionForQuery,
                targetCommunityId: leagueForQuery,
                cursor: cursor,
                pageSize: pageSize
            )
            let existing = Set(rows.map(\.adminActionId))
            let merged = page.items.filter { !existing.contains($0.adminActionId) }
            rows.append(contentsOf: merged)
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            listError = error.localizedDescription
        }
    }
}

// MARK: - Navigation chrome

private extension View {
    /// Same leading control as league list / detail (`CommunityFlowBackToolbarButton`).
    func platformAdminNavigationMatchedBackButton() -> some View {
        navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    CommunityFlowBackToolbarButton()
                }
            }
    }
}
