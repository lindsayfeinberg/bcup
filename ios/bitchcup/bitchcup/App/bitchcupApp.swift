import SwiftUI

@main
struct bitchcupApp: App {
    @StateObject private var router = AppRouter()
    @StateObject private var container = DependencyContainer.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(router)
                .environmentObject(container)
                .onAppear {
                    // TODO: replace with real value from Firestore in T05
                    let onboardingCompleteAt: Date? = Date()
                    router.resolve(onboardingCompleteAt: onboardingCompleteAt)
                }
        }
    }
}