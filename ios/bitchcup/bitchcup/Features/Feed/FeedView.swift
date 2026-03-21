import SwiftUI

struct FeedView: View {
    @State private var showCommunities = false
    @State private var showGameLog = false
    @State private var showProfile = false

    // TODO: replace with real state from view model in T08
    @State private var isLoading = false
    @State private var hasError = false
    @State private var isEmpty = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Text("BitchCUP")
                        .font(.title.bold())
                    Spacer()
                    Button {
                        showProfile = true
                    } label: {
                        Circle()
                            .frame(width: 40, height: 40)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Feed content
                if isLoading {
                    LoadingView(message: "Loading feed...")
                } else if hasError {
                    ErrorView(message: "Could not load feed.") {
                        // TODO: retry fetch in T08
                    }
                } else if isEmpty {
                    EmptyStateView(
                        title: "No games yet",
                        message: "Log a game or join a community to see activity here.",
                        actionLabel: "Log a Game"
                    ) {
                        showGameLog = true
                    }
                } else {
                    ScrollView {
                        VStack {
                            Text("Feed placeholder - scrollable photos here")
                                .padding()
                        }
                    }
                }

                // Bottom nav
                HStack {
                    Button("Your Communities") {
                        showCommunities = true
                    }
                    .frame(maxWidth: .infinity)
                    .padding()

                    Divider()
                        .frame(height: 30)

                    Button("Submit Game") {
                        showGameLog = true
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .background(Color(.systemGray5))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationDestination(isPresented: $showCommunities) {
                CommunitiesView()
            }
            .navigationDestination(isPresented: $showGameLog) {
                GameLogView()
            }
            .navigationDestination(isPresented: $showProfile) {
                ProfileView()
            }
        }
    }
}