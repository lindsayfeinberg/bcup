import SwiftUI

struct FeedView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Text("BitchCUP")
                    .font(.title.bold())
                Spacer()
                Circle()
                    .frame(width: 40, height: 40)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Feed
            ScrollView {
                VStack {
                    Text("Feed placeholder - scrollable photos here")
                        .padding()
                    Spacer()
                }
            }

            // Bottom nav
            HStack {
                Button("Your Communities") {
                    // navigate to communities
                }
                .frame(maxWidth: .infinity)
                .padding()

                Divider()
                    .frame(height: 30)

                Button("Submit Game") {
                    // navigate to log game
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .background(Color(.systemGray5))
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
}