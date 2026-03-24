import SwiftUI

/// Neue Haas Display — register names match `Resources/Fonts` PostScript names.
enum AppFont {
    static let navigationTitle = Font.custom("NeueHaasDisplay-Bold", size: 17)
    static let title = Font.custom("NeueHaasDisplay-Bold", size: 20)
    static let headline = Font.custom("NeueHaasDisplay-Bold", size: 17)
    static let body = Font.custom("NeueHaasDisplay-Roman", size: 17)
    static let bodyMedium = Font.custom("NeueHaasDisplay-Mediu", size: 17)
    static let subheadline = Font.custom("NeueHaasDisplay-Mediu", size: 15)
    static let subheadlineBold = Font.custom("NeueHaasDisplay-Bold", size: 15)
    static let footnote = Font.custom("NeueHaasDisplay-Light", size: 13)
    static let caption = Font.custom("NeueHaasDisplay-Light", size: 12)
    /// Grouped form section headers (small, emphasized).
    static let sectionHeader = Font.custom("NeueHaasDisplay-Bold", size: 13)
    static let button = Font.custom("NeueHaasDisplay-Mediu", size: 17)
    static let buttonProminent = Font.custom("NeueHaasDisplay-Mediu", size: 17)
    static let emptyStateTitle = Font.custom("NeueHaasDisplay-Bold", size: 17)
}
