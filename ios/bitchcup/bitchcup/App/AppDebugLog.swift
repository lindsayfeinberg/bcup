import Foundation

/// Debug-only console logging. Filter Xcode console with: `bcup`
enum AppDebugLog {
    static func log(_ message: String, file: String = #file, function: String = #function) {
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        print("[bcup] \(fileName) \(function) — \(message)")
        #endif
    }
}
