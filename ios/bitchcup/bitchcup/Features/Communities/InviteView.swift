import SwiftUI

struct InviteView: View {
    let communityId: String
    let inviteCode: String
    let inviteLink: String

    @State private var showShareSheet = false
    @State private var copied = false
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("League Created!")
                .font(.title.bold())

            VStack(spacing: 8) {
                Text("Invite Code")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(inviteCode)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .padding()
                    .background(Color(.systemGray6))
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
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .cornerRadius(12)
            }

            Button {
                showShareSheet = true
            } label: {
                Label("Share Invite Link", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }

            Spacer()

            Button("Go to League") {
                onDone()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.black)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .padding()
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
