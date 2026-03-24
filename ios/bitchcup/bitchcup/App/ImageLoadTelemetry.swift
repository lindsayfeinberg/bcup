import Foundation

enum ImageLoadEvent: String {
    case firstLoadSuccess = "first_load_success"
    case firstLoadFailure = "first_load_failure"
    case retrySuccess = "retry_success"
    case finalFailure = "final_failure"
}

actor ImageLoadTelemetry {
    static let shared = ImageLoadTelemetry()

    private var feedTimeToVisibleMs: [Int] = []

    private init() {}

    func recordEvent(
        _ event: ImageLoadEvent,
        surface: String,
        imageID: String,
        attemptCount: Int,
        urlHost: String?
    ) {
        let host = urlHost ?? "unknown_host"
        AppDebugLog.log(
            "image_metric event=\(event.rawValue) surface=\(surface) imageId=\(imageID) attempts=\(attemptCount) host=\(host)"
        )
    }

    func recordTimeToVisible(
        surface: String,
        imageID: String,
        attemptCount: Int,
        urlHost: String?,
        milliseconds: Int
    ) {
        let host = urlHost ?? "unknown_host"
        if surface == "feed" {
            feedTimeToVisibleMs.append(milliseconds)
        }
        AppDebugLog.log(
            "image_metric event=time_to_visible_ms surface=\(surface) imageId=\(imageID) attempts=\(attemptCount) host=\(host) value=\(milliseconds)"
        )
    }

    func flushFeedSessionMedian(reason: String) {
        guard !feedTimeToVisibleMs.isEmpty else {
            AppDebugLog.log("image_metric session_median surface=feed reason=\(reason) value=none sample=0")
            return
        }
        let sorted = feedTimeToVisibleMs.sorted()
        let mid = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
        AppDebugLog.log(
            "image_metric session_median surface=feed reason=\(reason) value=\(median) sample=\(sorted.count)"
        )
    }
}
