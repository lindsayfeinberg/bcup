import FirebaseFirestore
import SwiftUI

struct CommunityDetailView: View {
    let communityId: String

    private let pageTitleFont = Font.custom("NeueHaasDisplay-Bold", size: 42)
    private let sectionHeaderFont = Font.custom("NeueHaasDisplay-Mediu", size: 28)
    private let memberRankFont = Font.custom("NeueHaasDisplay-Mediu", size: 18)
    private let memberNameFont = Font.custom("NeueHaasDisplay-Mediu", size: 17)
    private let memberDetailFont = Font.custom("NeueHaasDisplay-Light", size: 15)

    @EnvironmentObject private var container: DependencyContainer
    @State private var communityName: String = ""
    @State private var inviteCode: String?
    @State private var members: [CommunityMemberRosterRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var copiedInviteCode = false

    @State private var feedRows: [FeedRow] = []
    @State private var selectedSeedMethod: SeedMethod = .communityOdds
    @State private var selectedTeamSize: Int = 1
    @State private var isCreatingBracket = false
    @State private var bracketErrorMessage: String?
    @State private var brackets: [BracketListItem] = []
    @State private var isLoadingBrackets = false
    @State private var bracketsErrorMessage: String?
    @State private var selectedBracketForNavigation: BracketListItem?
    @State private var pendingManualBracket: BracketListItem?
    @State private var showManualSeedFlow = false
    @State private var showCreateBracketPopup = false
    @State private var isLoadingFeed = false
    @State private var feedErrorMessage: String?
    @State private var feedCursor: FeedPageCursor?
    @State private var hasMoreFeed = false
    @State private var isLoadingMoreFeed = false
    @State private var loadMoreFeedErrorMessage: String?
    @State private var visibleActiveBracketsCount = 3
    @State private var visiblePastBracketsCount = 3
    private let uiTestMembers: [CommunityMemberRosterRow] = [
        .init(profileId: "ui-test-user", displayName: "You", profilePhotoUrl: nil, communityOdds: 0.75, communityGamesPlayed: 4),
        .init(profileId: "ui-opponent-1", displayName: "Alex", profilePhotoUrl: nil, communityOdds: 0.62, communityGamesPlayed: 3),
        .init(profileId: "ui-opponent-2", displayName: "Riley", profilePhotoUrl: nil, communityOdds: 0.51, communityGamesPlayed: 2),
        .init(profileId: "ui-opponent-3", displayName: "Jordan", profilePhotoUrl: nil, communityOdds: 0.41, communityGamesPlayed: 2)
    ]

    private var bracketAccentColor: Color {
        // Kept consistent with the existing community join/create flows.
        Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)
    }

    private var bracketAccentTextDisabledColor: Color {
        Color(red: 207.0 / 255.0, green: 106.0 / 255.0, blue: 84.0 / 255.0)
    }

    private var displayCommunityName: String {
        let trimmed = communityName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "League" : trimmed
    }

    /// Matches server rule: at least `2 * teamSize` members for one full match.
    private var minMembersForBracket: Int {
        2 * selectedTeamSize
    }

    private var canCreateBracket: Bool {
        members.count >= minMembersForBracket
    }

    /// Highest `communityOdds` first (best → worst); ties broken by `profileId` for stable order.
    private var membersOrderedByOdds: [CommunityMemberRosterRow] {
        members.sorted { lhs, rhs in
            if lhs.communityOdds != rhs.communityOdds {
                return lhs.communityOdds > rhs.communityOdds
            }
            return lhs.profileId < rhs.profileId
        }
    }

    var body: some View {
        Group {
            if isLoading {
                LoadingView(message: "Loading league...")
            } else if let error = errorMessage {
                ErrorView(message: error) {
                    Task { await loadInitial() }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(displayCommunityName)
                        .font(pageTitleFont)
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal)
                        .padding(.top, 24)
                        .padding(.bottom, 28)
                        .accessibilityIdentifier("community.detail.title")

                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            inviteCodeSection
                            membersSection
                            recentGamesSection
                            bracketPlaceholder
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                    .refreshable {
                        await refreshAll()
                    }
                }
                .background(Color.white)
                .overlay {
                    if showCreateBracketPopup {
                        ZStack {
                            Color.black.opacity(0.35)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    bracketErrorMessage = nil
                                    showCreateBracketPopup = false
                                }

                            VStack(alignment: .center, spacing: 18) {
                                Text("Create Bracket")
                                    .font(sectionHeaderFont)
                                    .foregroundStyle(.black)
                                    .multilineTextAlignment(.center)

                                // Seed method picker
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Seeding method")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    Picker("Seeding", selection: $selectedSeedMethod) {
                                        ForEach(SeedMethod.allCases) { method in
                                            VStack(alignment: .leading) {
                                                Text(method.displayName)
                                            }
                                            .tag(method)
                                        }
                                    }
                                    .pickerStyle(.segmented)

                                    Text(selectedSeedMethod.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                // Team size picker
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Team size")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    Picker("Team size", selection: $selectedTeamSize) {
                                        Text("1v1").tag(1)
                                        Text("2v2").tag(2)
                                        Text("3v3").tag(3)
                                        Text("4v4").tag(4)
                                    }
                                    .pickerStyle(.segmented)

                                    Text("Players per side in each match")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                // Error
                                if let bracketErrorMessage {
                                    Text(bracketErrorMessage)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }

                                if !canCreateBracket {
                                    Text("Need at least \(minMembersForBracket) members for \(selectedTeamSize)v\(selectedTeamSize).")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                // Footer buttons
                                HStack(spacing: 12) {
                                    Button {
                                        bracketErrorMessage = nil
                                        showCreateBracketPopup = false
                                    } label: {
                                        Text("Cancel")
                                            .font(.custom("NeueHaasDisplay-Mediu", size: 22))
                                            .foregroundStyle(bracketAccentColor)
                                            .frame(maxWidth: .infinity, minHeight: 48)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .fill(Color.white)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .stroke(bracketAccentColor, lineWidth: 2)
                                            )
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        Task { await createBracket() }
                                    } label: {
                                        HStack(spacing: 8) {
                                            if isCreatingBracket {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                            }
                                            Text(isCreatingBracket ? "Creating" : "Create ")
                                        }
                                        .font(.custom("NeueHaasDisplay-Mediu", size: 22))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(bracketAccentColor)
                                        )
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!canCreateBracket || isCreatingBracket)
                                    .accessibilityIdentifier("community.popup.createBracket")
                                }
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(.white, lineWidth: 2)
                            )
                            .padding(.horizontal, 24)
                        }
                    }
                }
            }
        }
        .background(Color.white)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            await loadInitial()
        }
        .fullScreenCover(isPresented: $showManualSeedFlow) {
            if let pendingManualBracket {
                ManualBracketSeedingFlowView(
                    bracketId: pendingManualBracket.bracketId,
                    teamSize: pendingManualBracket.teamSize,
                    members: members
                ) {
                    showManualSeedFlow = false
                    selectedBracketForNavigation = BracketListItem(
                        bracketId: pendingManualBracket.bracketId,
                        communityId: pendingManualBracket.communityId,
                        seedMethod: pendingManualBracket.seedMethod,
                        status: "ACTIVE",
                        teamSize: pendingManualBracket.teamSize,
                        createdAt: pendingManualBracket.createdAt
                    )
                }
                .environmentObject(container)
            } else {
                EmptyView()
            }
        }
        .navigationDestination(item: $selectedBracketForNavigation) { bracket in
            BracketsView(
                bracketId: bracket.bracketId,
                seedMethod: bracket.seedMethod,
                teamSize: bracket.teamSize,
                members: members
            )
        }
    }

    private var bracketPlaceholder: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bracket Manager")
                .font(sectionHeaderFont)
                .foregroundStyle(.black)

            // Create bracket entrypoint (opens the popup).
            Button {
                bracketErrorMessage = nil
                showCreateBracketPopup = true
            } label: {
                Text(isCreatingBracket ? "Creating..." : "Create Bracket")
                    .font(.custom("NeueHaasDisplay-Bold", size: 26))
                    .foregroundStyle(
                        canCreateBracket
                            ? .white
                            : bracketAccentTextDisabledColor
                    )
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(bracketAccentColor)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canCreateBracket || isCreatingBracket || showCreateBracketPopup)
            .opacity((isCreatingBracket || showCreateBracketPopup) ? 0.65 : 1.0)
            .accessibilityIdentifier("community.createBracket")

            Text("Active Brackets")
                .font(sectionHeaderFont)
                .foregroundStyle(.black)

            if isLoadingBrackets {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let bracketsErrorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(bracketsErrorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await loadBracketsSection() }
                    }
                    .buttonStyle(.bordered)
                }
            } else if activeBrackets.isEmpty {
                Text("No active brackets yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleActiveBrackets) { bracket in
                    bracketRowButton(bracket)
                }
                if hasMoreActiveBrackets {
                    Button("Show more active brackets") {
                        visibleActiveBracketsCount += 3
                    }
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .font(Font.custom("NeueHaasDisplay-Light", size: 16))
                    .foregroundStyle(.secondary)
                    .underline()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white)
                }
            }

            Text("Past Brackets")
                .font(sectionHeaderFont)
                .foregroundStyle(.black)

            if !isLoadingBrackets, bracketsErrorMessage == nil {
                if pastBrackets.isEmpty {
                    Text("No past brackets yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visiblePastBrackets) { bracket in
                        bracketRowButton(bracket)
                    }
                    if hasMorePastBrackets {
                        Button("Show more past brackets") {
                            visiblePastBracketsCount += 3
                        }
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .font(Font.custom("NeueHaasDisplay-Light", size: 16))
                        .foregroundStyle(.secondary)
                        .underline()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white)
                    }
                }
            }

            if !canCreateBracket {
                Text("Need at least \(minMembersForBracket) members for \(selectedTeamSize)v\(selectedTeamSize).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Members (\(members.count))")
                .font(sectionHeaderFont)
                .foregroundStyle(.black)

            if members.isEmpty {
                Text("No members yet.")
                    .font(memberDetailFont)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(membersOrderedByOdds.enumerated()), id: \.element.id) { index, member in
                    HStack(alignment: .center, spacing: 10) {
                        Text("\(index + 1).")
                            .font(memberRankFont)
                            .foregroundStyle(.black)
                            .frame(minWidth: 36, alignment: .trailing)
                            .monospacedDigit()

                        memberAvatar(for: member)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName.isEmpty ? "Unknown" : member.displayName)
                                .font(memberNameFont)
                                .foregroundStyle(.black)
                            if member.communityGamesPlayed == 0 {
                                Text("No league games yet")
                                    .font(memberDetailFont)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(Self.oddsFormatter.string(
                                    from: NSNumber(value: member.communityOdds)
                                ) ?? "0.000")
                                    .font(memberDetailFont)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var inviteCodeDisplayText: String {
        let trimmed = inviteCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "League code unavailable" : trimmed
    }

    private var hasInviteCode: Bool {
        let trimmed = inviteCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmed.isEmpty
    }

    private var inviteCodeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Invite Code")
                .font(.custom("NeueHaasDisplay-Bold", size: 15))
                .foregroundStyle(bracketAccentColor)
                .frame(maxWidth: .infinity, alignment: .center)

            Text(inviteCodeDisplayText)
                .font(.custom("NeueHaasDisplay-Bold", size: hasInviteCode ? 32 : 18))
                .foregroundStyle(bracketAccentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(bracketAccentTextDisabledColor.opacity(0.28))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(bracketAccentColor.opacity(0.55), lineWidth: 1.5)
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("community.detail.inviteCode")

            Button {
                UIPasteboard.general.string = inviteCodeDisplayText
                copiedInviteCode = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copiedInviteCode = false
                }
            } label: {
                Label(copiedInviteCode ? "Copied!" : "Copy Code", systemImage: "doc.on.doc")
                    .font(.custom("NeueHaasDisplay-Mediu", size: 22))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.white)
                    )
                    .foregroundStyle(bracketAccentColor)
            }
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .disabled(!hasInviteCode)
            .opacity(hasInviteCode ? 1.0 : 0.65)
            .accessibilityIdentifier("community.detail.copyInviteCode")
        }
    }

    @ViewBuilder
    private func memberAvatar(for member: CommunityMemberRosterRow) -> some View {
        if let photoURLString = member.profilePhotoUrl,
           let photoURL = URL(string: photoURLString) {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Circle()
                        .foregroundStyle(Color(.systemGray4))
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            Circle()
                .frame(width: 36, height: 36)
                .foregroundStyle(Color(.systemGray4))
        }
    }

    private var recentGamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Games")
                .font(sectionHeaderFont)
                .foregroundStyle(.black)

            if isLoadingFeed && feedErrorMessage == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else if let feedError = feedErrorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(feedError)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await loadInitialFeedSection() }
                    }
                    .buttonStyle(.bordered)
                }
            } else if feedRows.isEmpty {
                Text("No games in this league yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 24) {
                    ForEach(feedRows) { row in
                        FeedCardView(row: row, showCommunityLabel: false)
                    }
                    feedFooter
                }
            }
        }
    }

    private func loadInitial() async {
        isLoading = true
        errorMessage = nil
        feedErrorMessage = nil
        bracketsErrorMessage = nil
        do {
            try await fetchCommunityAndMembers()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return
        }
        isLoading = false
        await loadInitialFeedSection()
        await loadBracketsSection()
    }

    private func fetchCommunityAndMembers() async throws {
        if UITestRuntime.participatesInUiTestHarness {
            // Never hit live data in UI tests.
            communityName = "UI Test League"
            inviteCode = "UI-TEST"
            members = uiTestMembers
            return
        }
        let db = AppFirestore.db()
        let communityDoc = try await db.collection("communities").document(communityId).getDocument()
        communityName = communityDoc.data()?["name"] as? String ?? "League"
        inviteCode = communityDoc.data()?["inviteCode"] as? String
        members = try await container.communityService.fetchMembers(communityId: communityId)
    }

    private func loadInitialFeedSection() async {
        isLoadingFeed = true
        feedErrorMessage = nil
        feedCursor = nil
        hasMoreFeed = false
        loadMoreFeedErrorMessage = nil
        do {
            let page = try await container.feedService.fetchFeedPage(
                forCommunityId: communityId,
                cursor: nil,
                pageSize: 2
            )
            feedRows = page.items
            feedCursor = page.nextCursor
            hasMoreFeed = page.hasMore
        } catch {
            feedRows = []
            feedErrorMessage = Self.mapFeedError(error)
        }
        isLoadingFeed = false
    }

    private func refreshAll() async {
        feedErrorMessage = nil
        errorMessage = nil
        bracketsErrorMessage = nil
        do {
            try await fetchCommunityAndMembers()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await loadInitialFeedSection()
        await loadBracketsSection()
    }

    private func loadMoreFeedIfNeeded(currentRow: FeedRow) async {
        guard hasMoreFeed, !isLoadingMoreFeed else { return }

        isLoadingMoreFeed = true
        loadMoreFeedErrorMessage = nil
        defer { isLoadingMoreFeed = false }

        do {
            let page = try await container.feedService.fetchFeedPage(
                forCommunityId: communityId,
                cursor: feedCursor,
                pageSize: 2
            )
            let unique = Dictionary(grouping: (feedRows + page.items), by: \.gameLogId).compactMap { $0.value.first }
            feedRows = unique.sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt { return lhs.gameLogId > rhs.gameLogId }
                return lhs.createdAt > rhs.createdAt
            }
            feedCursor = page.nextCursor
            hasMoreFeed = page.hasMore
        } catch {
            loadMoreFeedErrorMessage = Self.mapFeedError(error)
        }
    }
    private func createBracket() async {
        if UITestRuntime.participatesInUiTestHarness {
            let bracketId = "ui-bracket-\(brackets.count + 1)"
            let created = BracketListItem(
                bracketId: bracketId,
                communityId: communityId,
                seedMethod: selectedSeedMethod,
                status: selectedSeedMethod == .manual ? "DRAFT" : "ACTIVE",
                teamSize: selectedTeamSize,
                createdAt: Date()
            )
            showCreateBracketPopup = false
            brackets = [created] + brackets
            if selectedSeedMethod == .manual {
                pendingManualBracket = created
                showManualSeedFlow = true
            } else {
                showManualSeedFlow = false
                selectedBracketForNavigation = created
            }
            return
        }
        isCreatingBracket = true
        bracketErrorMessage = nil
        defer { isCreatingBracket = false }
        do {
            let bracketId = try await container.bracketService.createBracket(
                communityId: communityId,
                seedMethod: selectedSeedMethod,
                teamSize: selectedTeamSize
            )
            let created = BracketListItem(
                bracketId: bracketId,
                communityId: communityId,
                seedMethod: selectedSeedMethod,
                status: selectedSeedMethod == .manual ? "DRAFT" : "ACTIVE",
                teamSize: selectedTeamSize,
                createdAt: Date()
            )
            showCreateBracketPopup = false
            if selectedSeedMethod == .manual {
                pendingManualBracket = created
                showManualSeedFlow = true
            } else {
                showManualSeedFlow = false
                selectedBracketForNavigation = created
            }
            await loadBracketsSection()
        } catch {
            bracketErrorMessage = error.localizedDescription
        }
    }

    private func loadBracketsSection() async {
        if UITestRuntime.participatesInUiTestHarness {
            isLoadingBrackets = false
            bracketsErrorMessage = nil
            visibleActiveBracketsCount = 3
            visiblePastBracketsCount = 3
            return
        }
        isLoadingBrackets = true
        defer { isLoadingBrackets = false }
        do {
            brackets = try await container.communityService.fetchBrackets(communityId: communityId)
            bracketsErrorMessage = nil
            visibleActiveBracketsCount = 3
            visiblePastBracketsCount = 3
        } catch {
            brackets = []
            bracketsErrorMessage = error.localizedDescription
            visibleActiveBracketsCount = 3
            visiblePastBracketsCount = 3
        }
    }

    private var activeBrackets: [BracketListItem] {
        brackets.filter { $0.status != "COMPLETE" }
    }

    private var pastBrackets: [BracketListItem] {
        brackets.filter { $0.status == "COMPLETE" }
    }

    private var visibleActiveBrackets: [BracketListItem] {
        Array(activeBrackets.prefix(visibleActiveBracketsCount))
    }

    private var visiblePastBrackets: [BracketListItem] {
        Array(pastBrackets.prefix(visiblePastBracketsCount))
    }

    private var hasMoreActiveBrackets: Bool {
        activeBrackets.count > visibleActiveBrackets.count
    }

    private var hasMorePastBrackets: Bool {
        pastBrackets.count > visiblePastBrackets.count
    }

    @ViewBuilder
    private func bracketRowButton(_ bracket: BracketListItem) -> some View {
        Button {
            selectedBracketForNavigation = bracket
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(bracket.seedMethod.displayName) • \(bracket.teamSize)v\(bracket.teamSize)")
                        .font(.custom("NeueHaasDisplay-Mediu", size: 18))
                        .foregroundStyle(.black)
                    Text("Status: \(bracket.status)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let createdAt = bracket.createdAt {
                        Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("ID: \(bracket.bracketId)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityIdentifier("community.bracket.\(bracket.bracketId)")
    }

    private static func mapFeedError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == FirestoreErrorDomain,
           ns.code == FirestoreErrorCode.permissionDenied.rawValue {
            return "You can't view games in this league."
        }
        return ns.localizedDescription
    }

    @ViewBuilder
    private var feedFooter: some View {
        if isLoadingMoreFeed {
            ProgressView("Loading more...")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else if let loadMoreFeedErrorMessage {
            VStack(spacing: 8) {
                Text(loadMoreFeedErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Retry loading more") {
                    Task {
                        if let last = feedRows.last {
                            await loadMoreFeedIfNeeded(currentRow: last)
                        }
                    }
                }
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .font(sectionHeaderFont)
                .foregroundStyle(.black)
                .underline()
                .frame(maxWidth: .infinity)
                .background(Color.white)
            }
            .padding(.vertical, 8)
        } else if hasMoreFeed && !feedRows.isEmpty {
            Button("Show more games") {
                Task {
                    if let last = feedRows.last {
                        await loadMoreFeedIfNeeded(currentRow: last)
                    }
                }
            }
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .font(Font.custom("NeueHaasDisplay-Light", size: 16))              // or Font.custom("NeueHaasDisplay-Light", size: 16)
            .foregroundStyle(.secondary)    // gray
            .underline()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.white)
        } else if !hasMoreFeed, !feedRows.isEmpty {
            Text("No older games.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }
    
    
    private static let oddsFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 3
        f.maximumFractionDigits = 3
        f.numberStyle = .decimal
        return f
    }()
}
