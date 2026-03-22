import Foundation
import FirebaseFirestore
import FirebaseStorage

/// Explains Firestore/Firebase errors for users and logs. Does not log tokens or PII.
///
/// **Common meanings:**
/// - **"Failed to get document because the client is offline"** — The SDK couldn’t complete a **server** read right now. Often: no network, VPN/DNS issues, too many parallel reads, or the backend returned **unavailable** and the client surfaced it as “offline.”
/// - **Firestore `unavailable` (14)** — Transient: network blip or Firestore busy; retry.
/// - **Permission denied (7)** — Security rules blocked the operation for this user/path.
/// - **"Database … does not exist"** (in underlying error) — Cloud Firestore database not created for the GCP project, or wrong project.
enum FirestoreErrorMapper {
    /// One line per NSError in the chain: `domain[code]: description` (for `AppDebugLog`).
    static func developerDebugLine(for error: Error) -> String {
        chainLines(for: error).joined(separator: " || ")
    }

    /// User-visible message: specific when we recognize the failure; includes domain/code on the last line for support.
    static func userFacingMessage(for error: Error) -> String {
        let chain = chainLines(for: error).joined(separator: " ").lowercased()
        let ns = error as NSError

        if chain.contains("does not exist"), chain.contains("database") {
            return "Cloud Firestore isn’t set up for this Firebase project (or the app points at the wrong project). In Firebase Console → Firestore → Create database (Native mode), then rebuild with the matching GoogleService-Info.plist."
        }

        if chain.contains("offline") || chain.contains("network connection was lost") {
            return "Couldn’t reach Firestore over the network. Check Wi‑Fi on the Mac (simulator uses the Mac’s connection), try without VPN, then try again. (SDK often reports this as “client is offline.”)"
        }

        if ns.domain == FirestoreErrorDomain {
            switch ns.code {
            case FirestoreErrorCode.unavailable.rawValue:
                return "Firestore is temporarily unavailable or unreachable. Check connection and try again. (Code: unavailable)"
            case FirestoreErrorCode.permissionDenied.rawValue:
                return "Firestore blocked this read (security rules). Confirm you’re signed in, rules allow `profiles/{your uid}`, and the app uses the matching Firebase project. Try signing out and back in. (Code: permission_denied)"
            case FirestoreErrorCode.unauthenticated.rawValue:
                return "Not signed in for Firestore. Sign out and sign in again. (Code: unauthenticated)"
            case FirestoreErrorCode.deadlineExceeded.rawValue:
                return "Firestore request timed out. Check network. (Code: deadline_exceeded)"
            case FirestoreErrorCode.resourceExhausted.rawValue:
                return "Firestore quota or rate limit. Try again in a moment. (Code: resource_exhausted)"
            case FirestoreErrorCode.notFound.rawValue:
                return "Requested document or database was not found. If this mentions “database”, create Firestore in Console. (Code: not_found)"
            default:
                break
            }
        }

        let summary = (error as NSError).localizedDescription
        return "Firestore: \(summary) — \(ns.domain) [\(ns.code)]"
    }

    /// Use for onboarding steps that may throw **Firestore** or **Storage** (e.g. profile photo).
    static func userFacingMessageForFirebaseServices(for error: Error) -> String {
        let ns = error as NSError
        if ns.domain == FirestoreErrorDomain {
            return userFacingMessage(for: error)
        }
        if ns.domain == StorageErrorDomain {
            return "Cloud Storage: \(ns.localizedDescription) — \(ns.domain) [\(ns.code)]"
        }
        return "\(ns.domain) [\(ns.code)]: \(ns.localizedDescription)"
    }

    private static func chainLines(for error: Error) -> [String] {
        var lines: [String] = []
        var current: Error? = error
        var depth = 0
        while let e = current, depth < 8 {
            depth += 1
            let ns = e as NSError
            lines.append("\(ns.domain)[\(ns.code)]: \(ns.localizedDescription)")
            current = ns.userInfo[NSUnderlyingErrorKey] as? Error
        }
        return lines
    }
}
