import SwiftUI

/// Shown after a successful create or join (T06 will load real data).
struct CommunityDetailView: View {
    let communityId: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Community")
                    .font(.title2)
                    .fontWeight(.semibold)

                LabeledContent("ID") {
                    Text(communityId)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Text("Member list, logs, and bracket entry will appear here (T06).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Community detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}
