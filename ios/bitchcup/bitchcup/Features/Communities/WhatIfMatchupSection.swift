import SwiftUI
import UIKit

/// Hypothetical NvN matchup using league stats for **one game type** (never aggregate all games).
struct WhatIfMatchupSection: View {
    let members: [CommunityMemberRosterRow]
    let gameDefinitions: [GameDefinitionRecord]
    let accentColor: Color
    let sectionHeaderFont: Font

    private let subsectionTitleFont = Font.custom("NeueHaasDisplay-Bold", size: 15)
    private let pickerRowFont = Font.custom("NeueHaasDisplay-Mediu", size: 17)
    private let detailFont = Font.custom("NeueHaasDisplay-Light", size: 15)
    private let resultTitleFont = Font.custom("NeueHaasDisplay-Mediu", size: 17)
    private let gameTypeChipFont = Font.custom("NeueHaasDisplay-Mediu", size: 14)
    private let gameTypeGridSpacing: CGFloat = 8

    @State private var matchupChip: LeagueRankingChip = .builtIn(.pong)
    @State private var teamSize = 1
    @State private var sideA: Set<String> = []
    @State private var sideB: Set<String> = []
    @State private var queryA = ""
    @State private var queryB = ""
    @State private var openA = false
    @State private var openB = false

    private var whatIfGameChips: [LeagueRankingChip] {
        LeagueRankingChip.whatIfGameChips(gameDefinitions: gameDefinitions)
    }

    private var teamSizeRange: ClosedRange<Int> {
        matchupChip.whatIfTeamSizeRange(memberCount: members.count)
    }

    private var canPickFullSides: Bool {
        members.count >= teamSize * 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What-if matchup")
                .font(sectionHeaderFont)
                .foregroundStyle(.black)

            Text("Uses league stats for the game type below (not your Rank by setting). This is not head-to-head history.")
                .font(detailFont)
                .foregroundStyle(.secondary)

            gameTypeChipGrid

            VStack(alignment: .leading, spacing: 8) {
                Text("Team size")
                    .font(subsectionTitleFont)
                    .foregroundStyle(accentColor)

                Stepper(value: $teamSize, in: teamSizeRange) {
                    Text("\(teamSize)")
                        .font(.custom("NeueHaasDisplay-Mediu", size: 18))
                        .foregroundStyle(.black)
                }
                .disabled(members.isEmpty)
                .accessibilityIdentifier("community.whatIf.teamSize")
                .onChange(of: teamSize) { _, _ in
                    trimSidesIfNeeded()
                }
            }

            if !members.isEmpty, !canPickFullSides {
                Text("Need at least \(teamSize * 2) members for \(teamSize)v\(teamSize).")
                    .font(detailFont)
                    .foregroundStyle(.secondary)
            }

            sidePickerBlock(
                title: "Side A",
                selected: sideA,
                other: sideB,
                query: $queryA,
                isOpen: $openA,
                otherOpen: $openB,
                accessibilityId: "community.whatIf.sideA",
                onToggle: { profileId, isSelected in
                    toggleSideA(profileId: profileId, isSelected: isSelected)
                }
            )

            sidePickerBlock(
                title: "Side B",
                selected: sideB,
                other: sideA,
                query: $queryB,
                isOpen: $openB,
                otherOpen: $openA,
                accessibilityId: "community.whatIf.sideB",
                onToggle: { profileId, isSelected in
                    toggleSideB(profileId: profileId, isSelected: isSelected)
                }
            )

            if let result = matchupResult {
                resultCard(result)
            }

            Text("Estimate from league win rates. Few games use a mild prior (+1 win and +1 loss) so short streaks don’t dominate.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            reconcileMatchupChipWithDefinitions()
            syncTeamSizeToRange()
        }
        .onChange(of: matchupChip) { _, _ in
            syncTeamSizeToRange()
        }
        .onChange(of: gameDefinitions) { _, _ in
            reconcileMatchupChipWithDefinitions()
            syncTeamSizeToRange()
        }
        .onChange(of: members.count) { _, _ in
            syncTeamSizeToRange()
        }
    }

    private var gameTypeChipGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: gameTypeGridSpacing),
            GridItem(.flexible(), spacing: gameTypeGridSpacing),
            GridItem(.flexible(), spacing: gameTypeGridSpacing)
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Text("Game type")
                .font(subsectionTitleFont)
                .foregroundStyle(accentColor)

            LazyVGrid(columns: columns, spacing: gameTypeGridSpacing) {
                ForEach(whatIfGameChips) { chip in
                    let selected = matchupChip == chip
                    Button {
                        matchupChip = chip
                    } label: {
                        Text(chip.displayName)
                            .font(gameTypeChipFont)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 6)
                            .foregroundStyle(selected ? accentColor : .primary)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selected ? Color.white : Color(UIColor.secondarySystemGroupedBackground))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        selected ? accentColor : Color.primary.opacity(0.12),
                                        lineWidth: selected ? 2 : 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chip.displayName)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("What-if game type")
            .accessibilityIdentifier("community.whatIf.gameType")
        }
    }

    /// Keeps `matchupChip` valid when definitions load, rename, or disappear (what-if never uses aggregate “all games”).
    private func reconcileMatchupChipWithDefinitions() {
        let chips = whatIfGameChips
        guard !chips.isEmpty else { return }
        switch matchupChip {
        case .allGames:
            matchupChip = chips[0]
        case .builtIn:
            if !chips.contains(matchupChip) {
                matchupChip = chips[0]
            }
        case .customDefinition(let id, _):
            if let def = gameDefinitions.first(where: { $0.gameDefinitionId == id }) {
                matchupChip = .customDefinition(id: def.gameDefinitionId, name: def.name)
            } else {
                matchupChip = chips[0]
            }
        }
    }

    private func syncTeamSizeToRange() {
        let r = teamSizeRange
        if teamSize < r.lowerBound { teamSize = r.lowerBound }
        if teamSize > r.upperBound { teamSize = r.upperBound }
        trimSidesIfNeeded()
    }

    private func trimSidesIfNeeded() {
        if sideA.count > teamSize {
            sideA = Set(Array(sideA).prefix(teamSize))
        }
        if sideB.count > teamSize {
            sideB = Set(Array(sideB).prefix(teamSize))
        }
    }

    private func toggleSideA(profileId: String, isSelected: Bool) {
        if isSelected {
            sideA.remove(profileId)
        } else {
            guard sideA.count < teamSize else { return }
            sideB.remove(profileId)
            sideA.insert(profileId)
        }
    }

    private func toggleSideB(profileId: String, isSelected: Bool) {
        if isSelected {
            sideB.remove(profileId)
        } else {
            guard sideB.count < teamSize else { return }
            sideA.remove(profileId)
            sideB.insert(profileId)
        }
    }

    // MARK: - Side pickers

    private func sidePickerBlock(
        title: String,
        selected: Set<String>,
        other: Set<String>,
        query: Binding<String>,
        isOpen: Binding<Bool>,
        otherOpen: Binding<Bool>,
        accessibilityId: String,
        onToggle: @escaping (String, Bool) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(subsectionTitleFont)
                .foregroundStyle(accentColor)

            Button {
                isOpen.wrappedValue.toggle()
                if isOpen.wrappedValue {
                    query.wrappedValue = ""
                    otherOpen.wrappedValue = false
                }
            } label: {
                HStack {
                    Spacer()
                    Text("\(selected.count)/\(teamSize)")
                        .font(.subheadline)
                        .foregroundStyle(.black)
                    Image(systemName: isOpen.wrappedValue ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.black)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canPickFullSides || teamSize <= 0)
            .accessibilityIdentifier(accessibilityId)

            if isOpen.wrappedValue {
                let filtered = members.filter { member in
                    let q = query.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard !q.isEmpty else { return true }
                    return member.displayName.lowercased().contains(q) || member.profileId.lowercased().contains(q)
                }

                TextField("Search...", text: query)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filtered, id: \.profileId) { member in
                            let profileId = member.profileId
                            let isSelected = selected.contains(profileId)
                            let onOther = other.contains(profileId)
                            let canAdd = isSelected || selected.count < teamSize
                            let rowDisabled = (!isSelected && onOther) || (!isSelected && !canAdd)

                            Button {
                                guard !rowDisabled else { return }
                                onToggle(profileId, isSelected)
                            } label: {
                                Group {
                                    if onOther, !isSelected {
                                        HStack(spacing: 12) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.black)
                                            Text(member.displayName.isEmpty ? "Unknown" : member.displayName)
                                                .font(pickerRowFont)
                                                .foregroundStyle(.primary)
                                            Text("Other side")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                            Spacer(minLength: 0)
                                        }
                                    } else {
                                        Text(member.displayName.isEmpty ? "Unknown" : member.displayName)
                                            .font(pickerRowFont)
                                            .foregroundStyle(isSelected ? accentColor : .black)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .background {
                                    if !onOther || isSelected, isSelected {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(accentColor.opacity(0.08))
                                    }
                                }
                                .overlay {
                                    if !onOther || isSelected, isSelected {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(accentColor.opacity(0.45), lineWidth: 1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(rowDisabled)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }

    // MARK: - Result

    private struct MatchupResultDisplay {
        let labelA: String
        let labelB: String
        let summaryA: String
        let summaryB: String
        let pA: Double
        let pB: Double
        let lineA: Int
        let lineB: Int
        let edgeCaption: String
    }

    private var matchupResult: MatchupResultDisplay? {
        guard sideA.count == teamSize,
              sideB.count == teamSize,
              sideA.isDisjoint(with: sideB),
              let sA = WhatIfMatchupMath.meanResolvedOdds(memberIds: sideA, roster: members, chip: matchupChip),
              let sB = WhatIfMatchupMath.meanResolvedOdds(memberIds: sideB, roster: members, chip: matchupChip)
        else { return nil }

        let (pA, pB) = WhatIfMatchupMath.winProbabilities(sideA: sA, sideB: sB)
        let lineA = WhatIfMatchupMath.americanMoneyline(impliedWinProbability: pA)
        let lineB = WhatIfMatchupMath.americanMoneyline(impliedWinProbability: pB)
        let edge = WhatIfMatchupMath.percentagePointEdge(pA: pA, pB: pB)

        let edgeCaption: String
        if abs(edge) < 0.5 {
            edgeCaption = "Roughly even on win %"
        } else if edge > 0 {
            edgeCaption = "Side A +\(String(format: "%.0f", edge)) pts vs Side B (percentage-point edge on win %)"
        } else {
            edgeCaption = "Side B +\(String(format: "%.0f", -edge)) pts vs Side A (percentage-point edge on win %)"
        }

        return MatchupResultDisplay(
            labelA: "Side A",
            labelB: "Side B",
            summaryA: namesLine(for: sideA),
            summaryB: namesLine(for: sideB),
            pA: pA,
            pB: pB,
            lineA: lineA,
            lineB: lineB,
            edgeCaption: edgeCaption
        )
    }

    private func namesLine(for ids: Set<String>) -> String {
        let byId = Dictionary(uniqueKeysWithValues: members.map { ($0.profileId, $0) })
        let names = ids.compactMap { byId[$0] }
            .map { $0.displayName.isEmpty ? "Unknown" : $0.displayName }
            .sorted()
        return names.joined(separator: ", ")
    }

    private func formatAmerican(_ n: Int) -> String {
        n > 0 ? "+\(n)" : "\(n)"
    }

    private func formatPct(_ p: Double) -> String {
        String(format: "~%.0f%%", p * 100)
    }

    @ViewBuilder
    private func resultCard(_ r: MatchupResultDisplay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(r.edgeCaption)
                .font(detailFont)
                .foregroundStyle(.primary)

            HStack(alignment: .top, spacing: 12) {
                sideResultColumn(
                    title: r.labelA,
                    names: r.summaryA,
                    pct: formatPct(r.pA),
                    american: formatAmerican(r.lineA)
                )
                sideResultColumn(
                    title: r.labelB,
                    names: r.summaryB,
                    pct: formatPct(r.pB),
                    american: formatAmerican(r.lineB)
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accentColor.opacity(0.35), lineWidth: 1.5)
        }
        .accessibilityIdentifier("community.whatIf.result")
    }

    private func sideResultColumn(title: String, names: String, pct: String, american: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(resultTitleFont)
                .foregroundStyle(accentColor)
            Text(names)
                .font(detailFont)
                .foregroundStyle(.primary)
                .lineLimit(3)
            Text("Win \(pct)")
                .font(resultTitleFont)
                .foregroundStyle(.black)
            Text("Implied line \(american)")
                .font(.custom("NeueHaasDisplay-Mediu", size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
