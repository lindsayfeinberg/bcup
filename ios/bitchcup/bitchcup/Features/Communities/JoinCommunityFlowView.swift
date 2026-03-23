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

    private var previewLeagueName: String {
        pendingPreview?.name ?? "this"
    }

    private var previewMemberCount: String {
        String(pendingPreview?.memberCount ?? 0)
    }
    
    let onSuccess: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            TextField("Invite code", text: $inviteCode)
                .font(.custom("NeueHaasDisplay-Roman", size: 24))
                .foregroundStyle(Color(red: 41.0 / 255.0, green: 0.0 / 255.0, blue: 3.0 / 255.0))
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0), lineWidth: 2)
                )
                .tint(.black)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)

            Text("Leagues are limited to 350 members. If the league is full, you cannot join.")
                .font(.custom("NeueHaasDisplay-Light", size: 17))
                .foregroundStyle(Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0))

            Button("Join League") {
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
            }
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
                        .font(.custom("NeueHaasDisplay-Mediu", size: 18))
                        .foregroundStyle(Color(red: 41.0 / 255.0, green: 0.0 / 255.0, blue: 3.0 / 255.0))
                }
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
                            + Text(" league with ")
                                .foregroundStyle(.black)
                            + Text(previewMemberCount).foregroundStyle(.black)
                            + Text(" members?")
                                .foregroundStyle(.black)
                        )
                        .font(.custom("NeueHaasDisplay-Bold", size: 30))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)

                        HStack(spacing: 12) {
                            Button("Cancel") {
                                showJoinConfirmation = false
                            }
                            .font(.custom("NeueHaasDisplay-Mediu", size: 22))
                            .foregroundStyle(Color(red: 41.0 / 255.0, green: 0.0 / 255.0, blue: 3.0 / 255.0))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(red: 207.0 / 255.0, green: 106.0 / 255.0, blue: 84.0 / 255.0))
                            )
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
                                    .fill(Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0))
                            )
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
                            .stroke(.black, lineWidth: 2)
                    )
                    .padding(.horizontal, 24)
                }
            }
        }
    }
}
