import Foundation

actor ImagePrefetcher {
    static let shared = ImagePrefetcher()

    private var inFlight: Set<String> = []

    private init() {}

    func prefetch(urls: [URL], limit: Int = 3) async {
        guard limit > 0 else { return }
        var unique: [URL] = []
        var seen: Set<String> = []
        for url in urls where seen.insert(url.absoluteString).inserted {
            unique.append(url)
            if unique.count >= limit { break }
        }
        guard !unique.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for url in unique {
                group.addTask { [url] in
                    await self.prefetch(url: url)
                }
            }
        }
    }

    private func prefetch(url: URL) async {
        let key = url.absoluteString
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 20
        _ = try? await URLSession.shared.data(for: request)
    }
}
