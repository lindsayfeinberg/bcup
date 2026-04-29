import SwiftUI

/// Static reference for how built-in game types work in Bitchcup (odds, logging, stats).
struct GameRulesExplainerView: View {
    private let titleFont = Font.custom("NeueHaasDisplay-Bold", size: 28)
    private let sectionTitleFont = Font.custom("NeueHaasDisplay-Mediu", size: 22)
    private let bodyFont = Font.custom("NeueHaasDisplay-Roman", size: 16)
    private let ink = Color.black
    private let border = Color(red: 220.0 / 255.0, green: 220.0 / 255.0, blue: 222.0 / 255.0)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("How each game works")
                    .font(titleFont)
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(
                    "When you log a game, Bitchcup records winners and losers and updates odds in that league for the game type you pick. Stats you enter (cups, hits, cans, etc.) show on the game card and in summaries."
                )
                .font(bodyFont)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)

                ForEach(GameType.allCases) { type in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(type.displayName)
                            .font(sectionTitleFont)
                            .foregroundStyle(ink)
                        Text(type.explainerText)
                            .font(bodyFont)
                            .foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(border, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollContentBackground(.hidden)
        .background(Color.white)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                CommunityFlowBackToolbarButton()
            }
        }
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            AppAnalytics.logGameRulesExplainerScreen()
        }
    }
}
