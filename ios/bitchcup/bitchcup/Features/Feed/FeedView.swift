import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var sessionManager: AppSessionManager
    @EnvironmentObject private var container: DependencyContainer

    @State private var showCommunitiesFlow = false
    @State private var showCommunitiesList = false
    @State private var showGameLog = false
    @State private var showProfile = false

    @State private var isLoading = false
    @State private var hasError = false
    @State private var isEmpty = true
    private let headerFont = Font.custom("NeueHaasDisplay-Bold", size: 34)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("BitchCUP")
                        .font(headerFont)
                    Spacer()
                    Menu {
                        Button {
                            showProfile = true
                        } label: {
                            Label("View profile", systemImage: "person")
                        }
                        Button {
                            showCommunitiesList = true
                        } label: {
                            Label("View leagues", systemImage: "person.3")
                        }
                        Divider()
                        Button(role: .destructive) {
                            sessionManager.signOut()
                        } label: {
                            Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Account menu")
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                if isLoading {
                    LoadingView(message: "Loading feed...")
                } else if hasError {
                    ErrorView(message: "Could not load feed.") {
                        // TODO: retry fetch in T08
                    }
                } else if isEmpty {
                    EmptyStateView(
                        title: "No games yet",
                        message: "Log a game or join a league to see activity here.",
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

                HStack {
                    Button("Create/Join a League") {
                        showCommunitiesFlow = true
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
            .fullScreenCover(isPresented: $showCommunitiesFlow) {
                CommunitiesFlowStack()
                    .environmentObject(container)
            }
            .navigationDestination(isPresented: $showCommunitiesList) {
                CommunitiesListView()
            }
            .navigationDestination(isPresented: $showGameLog) {
                GameLogCaptureEntryView()
            }
            .navigationDestination(isPresented: $showProfile) {
                ProfileView()
            }
            .task {
                await sessionManager.ensureOnboardingCompleteOrRouteToOnboarding()
            }
        }
    }
}
