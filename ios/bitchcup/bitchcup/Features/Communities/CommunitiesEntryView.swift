import SwiftUI

/// Step 1: choose to create a new community or join with an invite.
struct CommunitiesEntryView: View {
    @Binding var path: NavigationPath

    var body: some View {
        VStack(spacing: 24) {
            Text("Communities")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create a new community or join one with an invite code.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                Button {
                    path.append(CommunityRoute.create)
                } label: {
                    Text("Create a community")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    path.append(CommunityRoute.join)
                } label: {
                    Text("Join a community")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 24)
    }
}
