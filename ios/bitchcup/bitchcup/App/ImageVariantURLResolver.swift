import Foundation
import FirebaseStorage

actor ImageVariantURLResolver {
    static let shared = ImageVariantURLResolver()

    private var cache: [String: URL] = [:]

    private init() {}

    func resolveURL(originalURL: URL, variant: ImageVariant) async -> URL {
        guard ImageDeliveryConfig.isTransformedDeliveryEnabled else { return originalURL }
        guard variant != .full else { return originalURL }

        let cacheKey = "\(variant.rawValue)|\(originalURL.absoluteString)"
        if let cached = cache[cacheKey] {
            return cached
        }

        guard let transformedPath = ImageVariantURLBuilder.transformedObjectPath(from: originalURL, variant: variant) else {
            cache[cacheKey] = originalURL
            return originalURL
        }

        do {
            let transformedURL = try await Storage.storage().reference(withPath: transformedPath).downloadURL()
            cache[cacheKey] = transformedURL
            AppDebugLog.log("image_variant_resolver resolved variant=\(variant.rawValue) path=\(transformedPath)")
            return transformedURL
        } catch {
            cache[cacheKey] = originalURL
            AppDebugLog.log("image_variant_resolver fallback variant=\(variant.rawValue) path=\(transformedPath) reason=\(error.localizedDescription)")
            return originalURL
        }
    }
}
