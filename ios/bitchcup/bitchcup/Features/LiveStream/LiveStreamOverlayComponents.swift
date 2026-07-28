import SwiftUI

/// Shared chat/reaction/viewer-count UI for both the broadcaster and viewer screens, so hosts and
/// viewers see the same comments, reaction bursts, and live viewer count.

struct ReactionBurstItem: Identifiable {
    let id: String
    let emoji: String
    let xOffset: CGFloat
}

/// Appends a reaction, auto-removing it after its float-up animation finishes.
@MainActor
final class ReactionBurstController: ObservableObject {
    @Published private(set) var bursts: [ReactionBurstItem] = []

    func trigger(emoji: String) {
        let item = ReactionBurstItem(id: UUID().uuidString, emoji: emoji, xOffset: CGFloat.random(in: -70...70))
        bursts.append(item)
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            bursts.removeAll { $0.id == item.id }
        }
    }
}

private struct FloatingReactionView: View {
    let emoji: String
    let xOffset: CGFloat

    @State private var animate = false

    var body: some View {
        Text(emoji)
            .font(.system(size: 40))
            .offset(x: xOffset, y: animate ? -260 : 0)
            .opacity(animate ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 2.0)) {
                    animate = true
                }
            }
    }
}

struct ReactionBurstOverlayView: View {
    let bursts: [ReactionBurstItem]

    var body: some View {
        ZStack {
            ForEach(bursts) { item in
                FloatingReactionView(emoji: item.emoji, xOffset: item.xOffset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 24)
        .padding(.bottom, 170)
        .allowsHitTesting(false)
    }
}

private struct LiveChatMessageRow: View {
    let message: LiveStreamMessage
    let authorName: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(authorName)
                .font(.custom("NeueHaasDisplay-Bold", size: 13))
                .foregroundStyle(.white)
            Text(message.text ?? "")
                .font(.custom("NeueHaasDisplay-Light", size: 13))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct LiveChatListView: View {
    let messages: [LiveStreamMessage]
    let authorName: (String) -> String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(messages.suffix(30)) { message in
                        LiveChatMessageRow(message: message, authorName: authorName(message.authorProfileId))
                            .id(message.id)
                    }
                }
            }
            .frame(maxHeight: 180)
            .onChange(of: messages) { _, _ in
                guard let lastId = messages.last?.id else { return }
                withAnimation {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }
}

/// "👁 12" viewer-count chip shown next to the LIVE pill on both screens.
struct LiveViewerCountChip: View {
    let viewerCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.fill")
                .font(.system(size: 12))
            Text("\(viewerCount)")
                .font(.custom("NeueHaasDisplay-Mediu", size: 13))
        }
        .foregroundStyle(.white.opacity(0.9))
    }
}

/// Drives a message stream into chat rows (for `type == .chat`) plus reaction bursts (for
/// `type == .reaction`), suppressing bursts for history that already existed when first subscribed.
@MainActor
final class LiveChatAndReactionsController: ObservableObject {
    @Published private(set) var chatMessages: [LiveStreamMessage] = []

    private var processedMessageIds: Set<String> = []
    private var isInitialLoad = true

    func handle(_ allMessages: [LiveStreamMessage], bursts: ReactionBurstController) {
        let fresh = allMessages.filter { !processedMessageIds.contains($0.id) }
        for message in fresh {
            processedMessageIds.insert(message.id)
            if !isInitialLoad, message.type == .reaction, let emoji = message.emoji {
                bursts.trigger(emoji: emoji)
            }
        }
        chatMessages = allMessages.filter { $0.type == .chat }
        isInitialLoad = false
    }
}
