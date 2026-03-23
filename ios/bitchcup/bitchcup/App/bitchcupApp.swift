import SwiftUI
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn

class AppDelegate: NSObject, UIApplicationDelegate {
    #if DEBUG
    private func logRegisteredFonts(matching prefix: String) {
        var matches: [String] = []
        for family in UIFont.familyNames {
            for fontName in UIFont.fontNames(forFamilyName: family) where fontName.hasPrefix(prefix) {
                matches.append(fontName)
            }
        }
        let sorted = matches.sorted()
        if sorted.isEmpty {
            AppDebugLog.log("Font check: no registered fonts found with prefix '\(prefix)'")
        } else {
            AppDebugLog.log("Font check: found \(sorted.count) fonts with prefix '\(prefix)'")
            for fontName in sorted {
                AppDebugLog.log("Font check: \(fontName)")
            }
        }
    }
    #endif

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppDebugLog.log("AppDelegate: starting Firebase configure")
        FirebaseApp.configure()

        if let app = FirebaseApp.app() {
            AppDebugLog.log("Firebase configured — projectID=\(app.options.projectID ?? "?") bundleID=\(app.options.bundleID)")
        }

        AppFirestore.logRuntimeFingerprint()

        AppFirestore.db().enableNetwork { error in
            if let error {
                AppDebugLog.log("Firestore enableNetwork failed: \(error.localizedDescription)")
            } else {
                AppDebugLog.log("Firestore enableNetwork: OK")
            }
        }

        // Auth, Firestore, and Storage use Firebase cloud endpoints from GoogleService-Info.plist.

        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            AppDebugLog.log("Google Sign-In configured with clientID prefix=\(String(clientID.prefix(12)))…")
        } else {
            AppDebugLog.log("Google Sign-In: no clientID (check GoogleService-Info.plist)")
        }

        #if DEBUG
        logRegisteredFonts(matching: "NeueHaas")
        #endif
        return true
    }
}

@main
struct bitchcupApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var router = AppRouter()
    @StateObject private var container: DependencyContainer
    @StateObject private var sessionManager: AppSessionManager

    init() {
        AppDebugLog.log("bitchcupApp.init: creating router, container, sessionManager")
        let router = AppRouter()
        let container = DependencyContainer()
        _router = StateObject(wrappedValue: router)
        _container = StateObject(wrappedValue: container)
        _sessionManager = StateObject(
            wrappedValue: AppSessionManager(
                router: router,
                authService: container.authService,
                userService: container.userService
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(router)
                .environmentObject(container)
                .environmentObject(sessionManager)
                .task {
                    AppDebugLog.log("WindowGroup.task: calling restoreSession()")
                    await sessionManager.restoreSession()
                    AppDebugLog.log("WindowGroup.task: restoreSession() finished — sessionState=\(String(describing: sessionManager.sessionState)) route=\(String(describing: router.route))")
                }
        }
    }
}
