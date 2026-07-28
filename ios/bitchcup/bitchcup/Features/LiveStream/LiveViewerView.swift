import LiveKit
import SwiftUI

/// Full-screen live video + chat/reactions for a viewer. Subscribes to the host's camera track,
/// mirrors the broadcaster's control-bar visual language, and shows a graceful ended state if the
/// host stops streaming while someone's watching.
struct LiveViewerView: View {
    let stream: LiveStreamSummary
    let communityName: String
    let session: LiveStreamSession
    let onLeave: () -> Void

    @EnvironmentObject private var container: DependencyContainer

    @StateObject private var room = Room()
    @StateObject private var reactionBursts = ReactionBurstController()
    @StateObject private var chatController = LiveChatAndReactionsController()

    @State private var isConnecting = true
    @State private var connectErrorMessage: String?
    @State private var streamStatus = "live"
    @State private var viewerCount = 0
    @State private var authorNamesByProfileId: [String: String] = [:]
    @State private var chatText = ""
    @State private var hasLeft = false

    private static let reactionEmojis = ["❤️", "🔥", "😂", "👏", "🍺"]

    private var fieldAccentColor: Color {
        Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)
    }

    private var hostVideoTrack: (any VideoTrack)? {
        room.remoteParticipants.values.first?.firstCameraVideoTrack
    }

    private var hostLine: String {
        let host = stream.hostDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return host.isEmpty ? "Live now" : "\(host) is live"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let hostVideoTrack {
                SwiftUIVideoView(hostVideoTrack)
                    .ignoresSafeArea()
            } else if isConnecting {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("Joining stream...")
                        .font(.custom("NeueHaasDisplay-Mediu", size: 16))
                        .foregroundStyle(.white)
                }
            }

            ReactionBurstOverlayView(bursts: reactionBursts.bursts)

            VStack(spacing: 0) {
                topBar
                Spacer()
                if let connectErrorMessage {
                    Text(connectErrorMessage)
                        .font(.custom("NeueHaasDisplay-Light", size: 13))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 8)
                }
                if streamStatus == "ended" {
                    streamEndedOverlay
                } else {
                    chatAndControls
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await connect()
            await loadAuthorNames()
        }
        .task { await observeMessages() }
        .task { await observeStream() }
    }

    // MARK: - Top bar / ended state

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(streamStatus == "ended" ? "Stream ended" : "🔴 \(communityName)")
                        .font(.custom("NeueHaasDisplay-Bold", size: 16))
                        .foregroundStyle(.white)
                    if streamStatus != "ended" {
                        LiveViewerCountChip(viewerCount: viewerCount)
                    }
                }
                Text(hostLine)
                    .font(.custom("NeueHaasDisplay-Light", size: 12))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            Spacer()
            Button {
                leave()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
    }

    private var streamEndedOverlay: some View {
        VStack(spacing: 12) {
            Text("This stream has ended.")
                .font(.custom("NeueHaasDisplay-Mediu", size: 16))
                .foregroundStyle(.white)
            Button("Close") {
                leave()
            }
            .font(.custom("NeueHaasDisplay-Bold", size: 16))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Capsule().fill(fieldAccentColor))
            .contentShape(Rectangle())
            .buttonStyle(.plain)
        }
        .padding(.bottom, 40)
    }

    // MARK: - Chat + reactions

    private var chatAndControls: some View {
        VStack(spacing: 8) {
            LiveChatListView(
                messages: chatController.chatMessages,
                authorName: { authorNamesByProfileId[$0]?.isEmpty == false ? authorNamesByProfileId[$0]! : "Member" }
            )
            reactionRow
            chatInputRow
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 20)
    }

    private var reactionRow: some View {
        HStack(spacing: 12) {
            ForEach(Self.reactionEmojis, id: \.self) { emoji in
                Button {
                    sendReactionTap(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 26))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var chatInputRow: some View {
        HStack(spacing: 8) {
            TextField("", text: $chatText, prompt: Text("Say something...").foregroundStyle(.white.opacity(0.5)))
                .font(.custom("NeueHaasDisplay-Roman", size: 15))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .tint(.white)
                .onSubmit { Task { await sendChat() } }

            Button {
                Task { await sendChat() }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(fieldAccentColor, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(chatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Connection / data

    private func connect() async {
        do {
            try await room.connect(url: session.livekitUrl, token: session.token)
            isConnecting = false
        } catch {
            isConnecting = false
            connectErrorMessage = error.localizedDescription
        }
    }

    private func loadAuthorNames() async {
        guard let members = try? await container.communityService.fetchMembers(communityId: stream.communityId) else {
            return
        }
        authorNamesByProfileId = Dictionary(uniqueKeysWithValues: members.map { ($0.profileId, $0.displayName) })
    }

    private func observeMessages() async {
        for await allMessages in container.liveStreamService.observeMessages(streamId: stream.streamId) {
            chatController.handle(allMessages, bursts: reactionBursts)
        }
    }

    private func observeStream() async {
        for await update in container.liveStreamService.observeStream(streamId: stream.streamId) {
            streamStatus = update.status
            viewerCount = update.viewerCount
        }
    }

    private func sendChat() async {
        let text = chatText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chatText = ""
        try? await container.liveStreamService.sendChatMessage(streamId: stream.streamId, text: text)
    }

    private func sendReactionTap(_ emoji: String) {
        Task {
            try? await container.liveStreamService.sendReaction(streamId: stream.streamId, emoji: emoji)
        }
    }

    private func leave() {
        guard !hasLeft else { return }
        hasLeft = true
        Task {
            await room.disconnect()
            try? await container.liveStreamService.leaveLiveStreamAsViewer(streamId: stream.streamId)
        }
        onLeave()
    }
}
