import AVFoundation
import LiveKit
import SwiftUI

/// Full-screen broadcaster: connects to the LiveKit room and publishes camera + mic.
/// Ending the stream pops the whole Go Live flow and hands off to `FeedView`, which pushes the
/// game-log capture flow fresh — so canceling out of it returns to Feed, not back to this screen.
struct LiveBroadcastView: View {
    let session: LiveStreamSession
    let communityId: String
    let onStreamEnded: (String) -> Void

    @EnvironmentObject private var container: DependencyContainer

    @StateObject private var room: Room
    @StateObject private var localMedia: LocalMedia
    @StateObject private var reactionBursts = ReactionBurstController()
    @StateObject private var chatController = LiveChatAndReactionsController()

    @State private var isConnecting = true
    @State private var isLive = false
    @State private var isEnding = false
    @State private var errorMessage: String?
    @State private var viewerCount = 0
    @State private var authorNamesByProfileId: [String: String] = [:]

    init(session: LiveStreamSession, communityId: String, onStreamEnded: @escaping (String) -> Void) {
        self.session = session
        self.communityId = communityId
        self.onStreamEnded = onStreamEnded
        let room = Room()
        _room = StateObject(wrappedValue: room)
        _localMedia = StateObject(wrappedValue: LocalMedia(room: room))
    }

    private var fieldAccentColor: Color {
        Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let cameraTrack = localMedia.cameraTrack {
                SwiftUIVideoView(cameraTrack)
                    .ignoresSafeArea()
            }

            ReactionBurstOverlayView(bursts: reactionBursts.bursts)

            VStack(spacing: 0) {
                topBar
                Spacer()
                if let errorMessage {
                    Text(errorMessage)
                        .font(.custom("NeueHaasDisplay-Light", size: 13))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 8)
                }
                LiveChatListView(
                    messages: chatController.chatMessages,
                    authorName: { authorNamesByProfileId[$0]?.isEmpty == false ? authorNamesByProfileId[$0]! : "Member" }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                bottomControls
            }

            if isConnecting {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Going live...")
                        .font(.custom("NeueHaasDisplay-Mediu", size: 16))
                        .foregroundStyle(.white)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await connect()
            await loadAuthorNames()
        }
        .task { await observeMessages() }
        .task { await observeViewerCount() }
        .onDisappear {
            Task { await room.disconnect() }
        }
    }

    private var topBar: some View {
        HStack {
            if isLive {
                HStack(spacing: 8) {
                    Text("🔴 LIVE")
                        .font(.custom("NeueHaasDisplay-Bold", size: 14))
                        .foregroundStyle(.white)
                    LiveViewerCountChip(viewerCount: viewerCount)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
    }

    private var bottomControls: some View {
        HStack(spacing: 16) {
            broadcastControlButton(
                systemImage: localMedia.isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill"
            ) {
                Task { await localMedia.toggleMicrophone() }
            }
            broadcastControlButton(systemImage: "arrow.triangle.2.circlepath.camera.fill") {
                Task { await localMedia.switchCamera() }
            }
            Spacer()
            Button(isEnding ? "Ending..." : "End Stream") {
                Task { await endStream() }
            }
            .font(.custom("NeueHaasDisplay-Bold", size: 18))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Capsule().fill(fieldAccentColor))
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .disabled(isEnding)
            .opacity(isEnding ? 0.65 : 1.0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    private func broadcastControlButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func connect() async {
        let cameraStatus = await CameraPermissionCoordinator.ensureVideoPermission()
        guard cameraStatus == .authorized else {
            isConnecting = false
            errorMessage = "Camera access is required to go live. Enable it in Settings."
            return
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            isConnecting = false
            errorMessage = "Microphone access is required to go live. Enable it in Settings."
            return
        }

        do {
            try await room.connect(url: session.livekitUrl, token: session.token)
        } catch {
            isConnecting = false
            errorMessage = "Could not connect: \(error.localizedDescription)"
            return
        }

        await localMedia.toggleCamera()
        // `LocalMedia.error` is set synchronously in the same catch block that would fail this
        // call — more reliable than `isCameraEnabled`, which updates via a separate async
        // participant-change notification and can still read stale/false right after a real success.
        if let cameraError = localMedia.error {
            isConnecting = false
            errorMessage = cameraError.localizedDescription
            localMedia.dismissError()
            return
        }

        await localMedia.toggleMicrophone()
        if let micError = localMedia.error {
            // Video is live even if audio failed to enable — surface the error but don't block going live.
            errorMessage = micError.localizedDescription
            localMedia.dismissError()
        }

        isConnecting = false
        isLive = true
    }

    private func loadAuthorNames() async {
        guard let members = try? await container.communityService.fetchMembers(communityId: communityId) else {
            return
        }
        authorNamesByProfileId = Dictionary(uniqueKeysWithValues: members.map { ($0.profileId, $0.displayName) })
    }

    private func observeMessages() async {
        for await allMessages in container.liveStreamService.observeMessages(streamId: session.streamId) {
            chatController.handle(allMessages, bursts: reactionBursts)
        }
    }

    private func observeViewerCount() async {
        for await update in container.liveStreamService.observeStream(streamId: session.streamId) {
            viewerCount = update.viewerCount
        }
    }

    private func endStream() async {
        isEnding = true
        errorMessage = nil
        defer { isEnding = false }
        await room.disconnect()
        do {
            try await container.liveStreamService.endLiveStream(streamId: session.streamId)
            onStreamEnded(communityId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
