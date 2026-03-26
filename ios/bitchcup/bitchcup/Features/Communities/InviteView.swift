import SwiftUI

struct InviteView: View {
    @Environment(\.dismiss) private var dismiss
    let communityId: String
    let leagueName: String?
    let inviteCode: String
    let inviteLink: String

    @State private var showShareSheet = false
    @State private var copied = false
    var onDone: () -> Void
    
    private var createdTitle: String {
        let trimmed = leagueName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "League Created!" : "\(trimmed) League Created!"
    }

    var body: some View {
        VStack(spacing: 24) {
            Text(createdTitle)
                .font(.custom("NeueHaasDisplay-Bold", size: 48))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            VStack(spacing: 8) {
                Text("Invite Code")
                    .font(.custom("NeueHaasDisplay-Light", size: 18))
                    .foregroundColor(.black)
                Text(inviteCode)
                    .font(.custom("NeueHaasDisplay-Bold", size: 36))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color(red: 207.0 / 255.0, green: 106.0 / 255.0, blue: 84.0 / 255.0))
                    .cornerRadius(12)
            }

            Button {
                UIPasteboard.general.string = inviteCode
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copied = false
                }
            } label: {
                Label(copied ? "Copied!" : "Copy Code", systemImage: "doc.on.doc")
                    .font(.custom("NeueHaasDisplay-Mediu", size: 24))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }

            Button {
                showShareSheet = true
            } label: {
                Label("Share Invite Link", systemImage: "square.and.arrow.up")
                    .font(.custom("NeueHaasDisplay-Mediu", size: 24))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }

            Spacer()

            Button("Go to League") {
                onDone()
            }
            .font(.custom("NeueHaasDisplay-Bold", size: 28))
            .frame(maxWidth: .infinity)
            .padding()
            .foregroundColor(.black)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
        }
        .padding()
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Text("Back")
                        .font(.custom("NeueHaasDisplay-Mediu", size: 16))
                        .foregroundStyle(Color(red: 41.0 / 255.0, green: 0.0 / 255.0, blue: 3.0 / 255.0))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .contentShape(Rectangle())
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [inviteLink])
        }
    }
}

// UIKit share sheet wrapper
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
