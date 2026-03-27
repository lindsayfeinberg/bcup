import Foundation

enum ImageVariant: String {
    case feedThumb
    case avatar
    case full

    fileprivate var suffix: String {
        switch self {
        case .feedThumb:
            return "_800x800"
        case .avatar:
            return "_400x400"
        case .full:
            return ""
        }
    }
}

enum ImageDeliveryConfig {
    // Feature flag: enable transformed URL usage (Firebase Resize Images convention).
    static var isTransformedDeliveryEnabled: Bool {
        let key = "feature.image.transformedDelivery"
        let defaults = UserDefaults.standard
        // If unset, default to ON (so TestFlight/Release uses resized variants).
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }
}

enum ImageVariantURLBuilder {
    /// Rewrites only the `/o/...` object path for a Firebase Storage download URL.
    ///
    /// Each object has its own download `token` query parameter. Path rewriting alone reuses the original token, so the
    /// variant object will not load. Call `ImageVariantURLResolver.resolveURL` (or `StorageReference.downloadURL`) for a
    /// valid variant URL.
    static func variantURL(from originalURL: URL, variant: ImageVariant) -> URL {
        guard ImageDeliveryConfig.isTransformedDeliveryEnabled else { return originalURL }
        guard variant != .full else { return originalURL }

        guard
            originalURL.host == "firebasestorage.googleapis.com",
            let transformedPath = transformedObjectPath(from: originalURL, variant: variant),
            let encodedPath = extractEncodedObjectPath(from: originalURL)
        else { return originalURL }

        let decodedPath = encodedPath.removingPercentEncoding ?? encodedPath
        guard transformedPath != decodedPath else { return originalURL }

        let reEncodedPath = encodeStorageObjectPath(transformedPath)
        var components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false)
        let existingPath = components?.path ?? ""
        guard let oRange = existingPath.range(of: "/o/\(encodedPath)") else { return originalURL }
        components?.path = existingPath.replacingCharacters(in: oRange, with: "/o/\(reEncodedPath)")

        // Keep query params (alt/token/etc) if present.
        return components?.url ?? originalURL
    }

    static func transformedObjectPath(from originalURL: URL, variant: ImageVariant) -> String? {
        guard ImageDeliveryConfig.isTransformedDeliveryEnabled else { return nil }
        guard variant != .full else { return nil }
        guard
            originalURL.host == "firebasestorage.googleapis.com",
            let encodedPath = extractEncodedObjectPath(from: originalURL)
        else {
            return nil
        }

        let decodedPath = encodedPath.removingPercentEncoding ?? encodedPath
        return appendSuffix(variant.suffix, toObjectPath: decodedPath)
    }

    private static func extractEncodedObjectPath(from url: URL) -> String? {
        let path = url.path
        guard let oRange = path.range(of: "/o/") else { return nil }
        return String(path[oRange.upperBound...])
    }

    private static func appendSuffix(_ suffix: String, toObjectPath objectPath: String) -> String {
        guard !suffix.isEmpty else { return objectPath }
        guard let dotIndex = objectPath.lastIndex(of: ".") else {
            return objectPath + suffix
        }
        let fileName = objectPath[..<dotIndex]
        let ext = objectPath[dotIndex...]
        return "\(fileName)\(suffix)\(ext)"
    }

    private static func encodeStorageObjectPath(_ path: String) -> String {
        // Firebase download URLs require an encoded object path where "/" is represented as "%2F".
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "/")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }
}
