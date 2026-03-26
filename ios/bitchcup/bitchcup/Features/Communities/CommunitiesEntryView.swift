import SwiftUI

struct CommunitiesEntryView: View {
    @Binding var path: NavigationPath

    var body: some View {
        VStack(spacing: 24) {
            Text("Leagues")
                .font(.custom("NeueHaasDisplay-Bold", size: 42))

            Text("Create a new league or join one with an invite code.")
                .font(.custom("NeueHaasDisplay-Light", size: 18))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer(minLength: 18)

            VStack(spacing: 12) {
                Button {
                    path.append(CommunityRoute.create)
                } label: {
                    Text("Create a League")
                        .font(.custom("NeueHaasDisplay-Bold", size: 42))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(CommunityPrimaryTextButtonStyle())

                Button {
                    path.append(CommunityRoute.join)
                } label: {
                    Text("Join a League")
                        .font(.custom("NeueHaasDisplay-Bold", size: 42))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(CommunityPrimaryTextButtonStyle())
            }
            .padding(.horizontal)

            Spacer()

            Button {
                path.append(CommunityRoute.list)
            } label: {
                Text("View Leagues")
                    .font(.custom("NeueHaasDisplay-Mediu", size: 28))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .contentShape(Rectangle())
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

private struct CommunityPrimaryTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0))
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
