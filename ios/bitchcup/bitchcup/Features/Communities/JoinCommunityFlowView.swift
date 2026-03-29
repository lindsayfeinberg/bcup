import SwiftUI

struct JoinCommunityFlowView: View {
    @EnvironmentObject private var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    @State private var inviteCode = ""
    @State private var isWorking = false
    @State private var showJoinConfirmation = false
    @State private var pendingPreview: CommunityJoinPreview?
    @State private var errorMessage: String?
    
    private var isInviteCodeValid: Bool {
        !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var fieldAccentColor: Color {
        Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)
    }
    
    private var fieldPlaceholderColor: Color {
        Color(red: 207.0 / 255.0, green: 106.0 / 255.0, blue: 84.0 / 255.0)
    }

    private var previewLeagueName: String {
        pendingPreview?.name ?? "this"
    }

    private var previewMemberCount: String {
        String(pendingPreview?.memberCount ?? 0)
    }
    
    let onSuccess: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            TextField(
                "",
                text: $inviteCode,
                prompt: Text("Invite code").foregroundStyle(fieldPlaceholderColor)
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
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled(true)
            .onChange(of: inviteCode) { _, newValue in
                let uppercased = newValue.uppercased()
                if newValue != uppercased {
                    inviteCode = uppercased
                }
            }

            Text("Leagues are limited to 350 members. If the league is full, you cannot join.")
                .font(.custom("NeueHaasDisplay-Light", size: 17))
                .foregroundStyle(Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            Button {
                Task {
                    isWorking = true
                    errorMessage = nil
                    do {
                        let preview = try await container.communityService.previewJoinCommunity(inviteCode: inviteCode)
                        pendingPreview = preview
                        showJoinConfirmation = true
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    isWorking = false
                }
            } label: {
                Text("Join League")
                    .font(.custom("NeueHaasDisplay-Bold", size: 30))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(
                        isInviteCodeValid
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
            .disabled(isWorking || !isInviteCodeValid)
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
        .alert("Could not join", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .overlay {
            if showJoinConfirmation {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showJoinConfirmation = false
                        }

                    VStack(alignment: .center, spacing: 18) {
                        (
                            Text("Do you want to join ")
                                .foregroundStyle(.black)
                            + Text(previewLeagueName).foregroundStyle(.black)
                            + Text(" with ")
                                .foregroundStyle(.black)
                            + Text(previewMemberCount).foregroundStyle(.black)
                            + Text(" members?")
                                .foregroundStyle(.black)
                        )
                        .font(.custom("NeueHaasDisplay-Mediu", size: 30))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)

                        HStack(spacing: 12) {
                            Button("Cancel") {
                                showJoinConfirmation = false
                            }
                            .font(.custom("NeueHaasDisplay-Mediu", size: 22))
                            .foregroundStyle(fieldAccentColor)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(fieldAccentColor, lineWidth: 2)
                            )
                            .contentShape(Rectangle())
                            .buttonStyle(.plain)

                            Button("Join") {
                                Task {
                                    isWorking = true
                                    errorMessage = nil
                                    do {
                                        let id = try await container.communityService.joinCommunity(inviteCode: inviteCode)
                                        showJoinConfirmation = false
                                        onSuccess(id)
                                    } catch {
                                        errorMessage = error.localizedDescription
                                        showJoinConfirmation = false
                                    }
                                    isWorking = false
                                }
                            }
                            .font(.custom("NeueHaasDisplay-Mediu", size: 22))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(fieldAccentColor)
                            )
                            .contentShape(Rectangle())
                            .buttonStyle(.plain)
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
