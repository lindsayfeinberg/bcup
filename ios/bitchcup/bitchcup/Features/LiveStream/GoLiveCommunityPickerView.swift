import SwiftUI

/// Pairs a started session with the league it's streaming to (`LiveStreamSession` alone doesn't carry `communityId`).
private struct ActiveGoLiveSession: Hashable {
    let session: LiveStreamSession
    let communityId: String
}

/// "Which league is this stream for?" — first step of the Go Live flow.
struct GoLiveCommunityPickerView: View {
    /// Called after the stream ends, with the league it was streaming to — lets the caller
    /// pop this whole flow and hand off to the game-log capture flow from a clean stack.
    let onStreamEnded: (String) -> Void

    @EnvironmentObject private var container: DependencyContainer

    @State private var communities: [CommunityListItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var startingCommunityId: String?
    @State private var activeGoLive: ActiveGoLiveSession?

    private let pageTitleFont = Font.custom("NeueHaasDisplay-Bold", size: 34)
    private let rowFont = Font.custom("NeueHaasDisplay-Mediu", size: 24)

    private var fieldAccentColor: Color {
        Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Go Live")
                .font(pageTitleFont)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 24)
                .padding(.bottom, 4)
            Text("Choose which league you're streaming to.")
                .font(.custom("NeueHaasDisplay-Light", size: 16))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 16)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color.white)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .communityFlowNavigationBarChrome()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                CommunityFlowBackToolbarButton()
            }
        }
        .navigationDestination(item: $activeGoLive) { active in
            LiveBroadcastView(
                session: active.session,
                communityId: active.communityId,
                onStreamEnded: onStreamEnded
            )
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            LoadingView(message: "Loading leagues...")
        } else if let errorMessage, communities.isEmpty {
            ErrorView(message: errorMessage) {
                Task { await load() }
            }
        } else if communities.isEmpty {
            emptyState
        } else {
            leagueList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("No leagues yet")
                .font(.custom("NeueHaasDisplay-Bold", size: 28))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
            Text("Join or create a league before going live.")
                .font(.custom("NeueHaasDisplay-Light", size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var leagueList: some View {
        List(communities, id: \.communityId) { community in
            Button {
                Task { await startStream(communityId: community.communityId) }
            } label: {
                HStack {
                    Text(community.name)
                        .font(rowFont)
                        .foregroundStyle(.black)
                    Spacer()
                    if startingCommunityId == community.communityId {
                        ProgressView()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(startingCommunityId != nil)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.white)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.custom("NeueHaasDisplay-Light", size: 13))
                    .foregroundStyle(fieldAccentColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.white)
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            communities = try await container.communityService.fetchCommunities()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func startStream(communityId: String) async {
        startingCommunityId = communityId
        errorMessage = nil
        defer { startingCommunityId = nil }
        do {
            let session = try await container.liveStreamService.startLiveStream(communityId: communityId)
            activeGoLive = ActiveGoLiveSession(session: session, communityId: communityId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
