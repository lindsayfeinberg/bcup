import SwiftUI

@main
struct bitchcupApp: App {
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(router)
                .onAppear {
                    // TODO: replace with real value from Firestore in T05
                    let onboardingCompleteAt: Date? = nil
                    router.resolve(onboardingCompleteAt: onboardingCompleteAt)
                }
        }
    }
}