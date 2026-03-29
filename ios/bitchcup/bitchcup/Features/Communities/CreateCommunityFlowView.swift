import SwiftUI

struct CreateCommunityFlowView: View {
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var navigator: CommunitiesNavigator
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var createdCommunity: (communityId: String, inviteCode: String, inviteLink: String)?
    
    private var isNameValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var fieldAccentColor: Color {
        Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)
    }
    
    private var fieldPlaceholderColor: Color {
        Color(red: 207.0 / 255.0, green: 106.0 / 255.0, blue: 84.0 / 255.0)
    }
    
    let onSuccess: (String, String, String) -> Void

    var body: some View {
        if let community = createdCommunity {
            InviteView(
                communityId: community.communityId,
                leagueName: name,
                inviteCode: community.inviteCode,
                inviteLink: community.inviteLink
            ) {
                navigator.navigateToDetail(communityId: community.communityId)
            }
        } else {
            VStack(alignment: .leading, spacing: 22) {
                        TextField(
                            "",
                            text: $name,
                            prompt: Text("League name").foregroundStyle(fieldPlaceholderColor)
                        )
                        .font(.custom("NeueHaasDisplay-Roman", size: 24))
                        .foregroundStyle(fieldAccentColor)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(fieldAccentColor, lineWidth: 2)
                        )
                        .tint(fieldAccentColor)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)

                        Text("Enter a league name above to create a league.")
                            .font(.custom("NeueHaasDisplay-Light", size: 17))
                            .foregroundStyle(Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Button {
                            guard !isWorking else { return }
                            Task {
                                isWorking = true
                                errorMessage = nil
                                defer { isWorking = false }
                                do {
                                    let result = try await container.communityService.createCommunity(name: name)
                                    await MainActor.run {
                                        createdCommunity = (result.communityId, result.inviteCode, result.inviteLink)
                                    }
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        } label: {
                            Text("Create League")
                                .font(.custom("NeueHaasDisplay-Bold", size: 30))
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .foregroundStyle(
                                    isNameValid
                                        ? .white
                                        : Color(red: 207.0 / 255.0, green: 106.0 / 255.0, blue: 84.0 / 255.0)
                                )
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0))
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking || !isNameValid)
                        .opacity(isWorking ? 0.65 : 1.0)

                Spacer()

                Image("create_below")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, -20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 130)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Back")
                            .font(.custom("NeueHaasDisplay-Mediu", size: 16))
                            .foregroundStyle(CommunityFlowToolbarChrome.accentRed)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Could not create", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}
