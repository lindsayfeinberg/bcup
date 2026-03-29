import SwiftUI

/// Matches league / game-log accent (`CommunityDetailView` bracket red, `GameLogBrandColor.lostRed`).
enum BracketBrandColor {
    static let accent = Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)
    /// Same as game log “won” styling for advancing sides.
    static let winnerGreen = Color(red: 0.0, green: 128.0 / 255.0, blue: 0.0)
}
