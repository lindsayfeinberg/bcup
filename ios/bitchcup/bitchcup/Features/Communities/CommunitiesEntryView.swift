import SwiftUI

struct CommunitiesEntryView: View {
    @Binding var path: NavigationPath

    var body: some View {
        VStack(spacing: 24) {
            Text("Leagues")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Create a new league or join one with an invite code.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer(minLength: 28)

            VStack(spacing: 12) {
                Button {
                    path.append(CommunityRoute.create)
                } label: {
                    Text("Create a League")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.plain)

                Button {
                    path.append(CommunityRoute.join)
                } label: {
                    Text("Join a League")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            Spacer()

            Button {
                path.append(CommunityRoute.list)
            } label: {
                Text("View Leagues")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 12)

            /*
             Keep bottom action separated so primary actions
             remain centered and visually focused.
             */
        }
        .padding(.top, 24)
    }
}
