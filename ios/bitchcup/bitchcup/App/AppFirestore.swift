import FirebaseCore
import FirebaseFirestore

/// Single place for Firestore **database ID** so the app matches `firebase.json` → `firestore.database` and the GCP **(default)** instance.
///
/// **Do not** use the string `"default"` here — that is a *different* named database (e.g. Enterprise) than **`(default)`** (Standard).
enum AppFirestore {
    /// Same ID as Firestore → Databases → `(default)` in Google Cloud / Firebase Console.
    static let databaseId = "(default)"

    /// Use this instead of `Firestore.firestore()` so all reads/writes hit the intended database.
    static func db() -> Firestore {
        Firestore.firestore(database: databaseId)
    }

    /// One-line fingerprint for Xcode console (no PII). Call after `FirebaseApp.configure()`.
    static func logRuntimeFingerprint() {
        let project = FirebaseApp.app()?.options.projectID ?? "?"
        let settings = db().settings
        AppDebugLog.log(
            "Firestore fingerprint — projectID=\(project) databaseId=\(databaseId) host=\(settings.host) ssl=\(settings.isSSLEnabled)"
        )
    }
}
