import SwiftUI

/// "🔴 Live now" rows shown above the feed for any stream currently live in one of the user's leagues.
struct LiveNowBannerView: View {
    let streams: [LiveStreamSummary]
    let communityName: (String) -> String
    var joiningStreamId: String? = nil
    let onSelect: (LiveStreamSummary) -> Void

    private var accentRed: Color {
        Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(streams) { stream in
                Button {
                    onSelect(stream)
                } label: {
                    HStack(spacing: 12) {
                        Text("🔴")
                            .font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(communityName(stream.communityId))
                                .font(.custom("NeueHaasDisplay-Mediu", size: 17))
                                .foregroundStyle(.white)
                            Text(hostLine(for: stream))
                                .font(.custom("NeueHaasDisplay-Light", size: 13))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        Spacer()
                        if joiningStreamId == stream.streamId {
                            ProgressView().tint(.white)
                        } else if stream.viewerCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "eye.fill")
                                    .font(.system(size: 12))
                                Text("\(stream.viewerCount)")
                                    .font(.custom("NeueHaasDisplay-Mediu", size: 13))
                            }
                            .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(accentRed)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(joiningStreamId != nil)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func hostLine(for stream: LiveStreamSummary) -> String {
        let host = stream.hostDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return host.isEmpty ? "Live now" : "\(host) is live"
    }
}
