import SwiftUI

struct NewGameLogFormView: View {
    @EnvironmentObject private var container: DependencyContainer

    @State private var communities: [(communityId: String, name: String)] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var selectedCommunityId: String = ""
    @State private var selectedGameType: GameType = .pong

    var body: some View {
        Group {
            if isLoading {
                LoadingView(message: "Loading communities...")
            } else if let errorMessage {
                ErrorView(message: errorMessage) {
                    Task { await load() }
                }
            } else if communities.isEmpty {
                EmptyStateView(
                    title: "No communities yet",
                    message: "Create or join a community to log a game.",
                    actionLabel: nil
                )
            } else {
                Form {
                    Section("Choose community") {
                        Picker("Community", selection: $selectedCommunityId) {
                            ForEach(communities, id: \.communityId) { community in
                                Text(community.name)
                                    .tag(community.communityId)
                            }
                        }
                    }

                    Section("Choose game type") {
                        Picker("Game type", selection: $selectedGameType) {
                            ForEach(GameType.allCases) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section("Pick participants") {
                        Text("Next: select winners/losers from community members.")
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("New Game")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task { await loadIfNeeded() }
    }

    private func loadIfNeeded() async {
        // Prevent re-fetching when SwiftUI re-renders.
        guard communities.isEmpty && isLoading else { return }
        await load()
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            communities = try await container.communityService.fetchCommunities()
            selectedCommunityId = communities.first?.communityId ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private enum GameType: String, CaseIterable, Identifiable {
    case pong = "PONG"
    case beerBall = "BEER_BALL"
    case battlePong = "BATTLE_PONG"
    case baseball = "BASEBALL"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pong: return "Pong"
        case .beerBall: return "Beer Ball"
        case .battlePong: return "Battle Pong"
        case .baseball: return "Baseball"
        }
    }
}

