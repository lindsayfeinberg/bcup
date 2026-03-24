import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

struct NewGameLogFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: DependencyContainer
    @State private var frontPhotoData: Data?
    @State private var backPhotoData: Data?
    @State private var showDualCapture = false

    init(frontPhotoData: Data? = nil, backPhotoData: Data? = nil) {
        _frontPhotoData = State(initialValue: frontPhotoData)
        _backPhotoData = State(initialValue: backPhotoData)
    }

    @State private var communities: [(communityId: String, name: String)] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var selectedCommunityId: String = ""
    @State private var selectedGameType: GameType = .pong

    // Members used for winners/losers and stat entry.
    @State private var members: [(profileId: String, displayName: String)] = []
    @State private var isMembersLoading = false
    @State private var membersErrorMessage: String?

    private enum Outcome {
        case won, lost
    }

    @State private var outcome: Outcome? = nil
    @State private var isTeammateDropdownOpen = false
    @State private var isOpponentDropdownOpen = false
    @State private var teammateQuery = ""
    @State private var opponentQuery = ""

    @State private var teamSize: Int = 1
    @State private var selectedWinnerProfileIds: Set<String> = []
    @State private var selectedLoserProfileIds: Set<String> = []
    @State private var selectedMVPProfileId: String = ""
    @State private var selectedLVPProfileId: String = ""
    @State private var photoUrls: [String] = []

    // T07.5 stats placeholders (persisted now).
    @State private var pongCupMode: PongCupMode = .ten
    @State private var pongCupsByProfileId: [String: Int] = [:]
    @State private var pongLastCupByProfileId: String = ""

    @State private var beerBallNewCansByProfileId: [String: Int] = [:]
    @State private var beerBallFirstFinishedByProfileId: String = ""

    @State private var battlePongCupsByProfileId: [String: Int] = [:]
    @State private var baseballHitsByProfileId: [String: Int] = [:]

    @State private var submitErrorMessage: String?
    @State private var isSubmitting = false
    @State private var showOpenSettingsAction = false
    @State private var submitAfterCapture = false

    var body: some View {
        Group {
            if isLoading {
                LoadingView(message: "Loading leagues...")
            } else if let errorMessage {
                ErrorView(message: errorMessage) {
                    Task { await load() }
                }
            } else if communities.isEmpty {
                EmptyStateView(
                    title: "No leagues yet",
                    message: "Create or join a league to log a game.",
                    actionLabel: nil
                )
            } else {
                Form {
                    Section("Game Photos") {
                        HStack(spacing: 12) {
                            photoPreview(data: frontPhotoData, title: "Front")
                            photoPreview(data: backPhotoData, title: "Back")
                        }

                        Button(frontPhotoData == nil && backPhotoData == nil ? "Capture both cameras" : "Retake both photos") {
                            showDualCapture = true
                        }
                        .buttonStyle(.borderedProminent)

                        Text("Camera only — dual capture when your device supports it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Choose league") {
                        Picker("League", selection: $selectedCommunityId) {
                            ForEach(communities, id: \.communityId) { community in
                                Text(community.name).tag(community.communityId)
                            }
                        }
                    }

                    Section("Choose game type") {
                        Picker("Game type", selection: $selectedGameType) {
                            ForEach(GameType.allCases) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section("Outcome") {
                        HStack(spacing: 12) {
                            Button {
                                outcome = .won
                                lockUserIntoOutcome()
                            } label: {
                                Text("I won").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(outcome == .won ? .blue : .gray)

                            Button {
                                outcome = .lost
                                lockUserIntoOutcome()
                            } label: {
                                Text("I lost").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(outcome == .lost ? .blue : .gray)
                        }
                    }

                    Section {
                        let range = teamSizeRange(for: selectedGameType)
                        Stepper(value: $teamSize, in: range, step: 1) {
                            Text("Team size: \(teamSize)")
                        }
                    }

                    Section {
                        fillSlotsContent
                    }

                    Section {
                        statsSectionContent
                    }

                    Section("Awards (Optional)") {
                        if participantProfileIds.isEmpty {
                            Text("Select winners and losers to choose MVP/LVP.")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("MVP", selection: $selectedMVPProfileId) {
                                Text("None").tag("")
                                ForEach(selectedParticipants, id: \.profileId) { participant in
                                    Text(displayName(for: participant.profileId)).tag(participant.profileId)
                                }
                            }
                            Picker("LVP", selection: $selectedLVPProfileId) {
                                Text("None").tag("")
                                ForEach(selectedParticipants, id: \.profileId) { participant in
                                    Text(displayName(for: participant.profileId)).tag(participant.profileId)
                                }
                            }
                        }
                    }

                    Section {
                        if let outcome {
                            let isMySideWinners = (outcome == .won)
                            let teammateSet = isMySideWinners ? selectedWinnerProfileIds : selectedLoserProfileIds
                            let opponentSet = isMySideWinners ? selectedLoserProfileIds : selectedWinnerProfileIds
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Teammates: \(teammateSet.count)/\(teamSize), Opponents: \(opponentSet.count)/\(teamSize)")
                                    .font(.subheadline)
                                    .bold()
                                Text("Winners: \(namesList(for: selectedWinnerProfileIds))")
                                    .font(.subheadline)
                                    .bold()
                                Text("Losers: \(namesList(for: selectedLoserProfileIds))")
                                    .font(.subheadline)
                                    .bold()
                            }
                        }
                    }

                    Section {
                        if !submitDisableReasons.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Missing before submit:")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                ForEach(submitDisableReasons, id: \.self) { reason in
                                    Text("• \(reason)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let statsError = currentStatsValidationError {
                            Text(statsError)
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }
                        if let submitErrorMessage {
                            Text(submitErrorMessage)
                                .foregroundStyle(.red)
                                .font(.footnote)
                            if showOpenSettingsAction {
                                Button("Open Settings") {
                                    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                                    UIApplication.shared.open(settingsURL)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        if isSubmitting {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Submitting game log...")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("Submit Game") {
                            Task { await handleSubmitTapped() }
                        }
                        .disabled(!canSubmitWithoutPhotos || isSubmitting)
                    }
                }
                .navigationTitle("New Game")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task { await loadIfNeeded() }
        .onChange(of: selectedCommunityId) { _, _ in
            resetSelectionForScopeChange()
            Task { await loadMembers() }
        }
        .onChange(of: selectedGameType) { _, _ in
            let newRange = teamSizeRange(for: selectedGameType)
            teamSize = newRange.lowerBound
            resetSelectionForScopeChange()
            syncStatsWithParticipants()
        }
        .onChange(of: teamSize) { _, newValue in
            if newValue <= 1 { isTeammateDropdownOpen = false }
            if selectedWinnerProfileIds.count > newValue || selectedLoserProfileIds.count > newValue {
                resetSelectionForScopeChange()
            }
            syncStatsWithParticipants()
        }
        .onChange(of: selectedWinnerProfileIds) { _, _ in
            syncStatsWithParticipants()
        }
        .onChange(of: selectedLoserProfileIds) { _, _ in
            syncStatsWithParticipants()
        }
        .fullScreenCover(isPresented: $showDualCapture) {
            DualCameraCaptureView(
                onCaptured: { front, back in
                    frontPhotoData = front
                    backPhotoData = back
                    showDualCapture = false
                    if submitAfterCapture {
                        submitAfterCapture = false
                        Task { await submitGameLog() }
                    }
                },
                onCancel: {
                    showDualCapture = false
                    if submitAfterCapture {
                        submitAfterCapture = false
                        submitErrorMessage = "Capture was canceled before submission."
                    }
                }
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var fillSlotsContent: some View {
        if isMembersLoading {
            LoadingView(message: "Loading members...")
        } else if let membersErrorMessage {
            ErrorView(message: membersErrorMessage) {
                Task { await loadMembers() }
            }
        } else if !members.isEmpty {
            let hasEnoughMembers = members.count >= (2 * teamSize)
            if let outcome, let myUserId = currentUserId {
                if !hasEnoughMembers {
                    Text("League doesn’t have enough members for a team of size \(teamSize).")
                        .foregroundStyle(.red)
                }

                let isMySideWinners = (outcome == .won)
                let teammateSet = isMySideWinners ? selectedWinnerProfileIds : selectedLoserProfileIds
                let opponentSet = isMySideWinners ? selectedLoserProfileIds : selectedWinnerProfileIds

                VStack(alignment: .leading, spacing: 12) {
                    if teamSize > 1 {
                        dropdownBlock(
                            title: "Teammates (\(isMySideWinners ? "Winners" : "Losers"))",
                            selectedCount: teammateSet.count,
                            query: $teammateQuery,
                            isOpen: $isTeammateDropdownOpen,
                            participants: members.filter { $0.profileId != myUserId },
                            onOpposite: opponentSet,
                            onCurrent: teammateSet,
                            oppositeLabel: "Opponents",
                            hasEnoughMembers: hasEnoughMembers
                        ) { profileId, isSelected in
                            toggleTeammate(profileId: profileId, isSelected: isSelected)
                        }
                    }

                    dropdownBlock(
                        title: "Opponents (\(isMySideWinners ? "Losers" : "Winners"))",
                        selectedCount: opponentSet.count,
                        query: $opponentQuery,
                        isOpen: $isOpponentDropdownOpen,
                        participants: members.filter { $0.profileId != myUserId },
                        onOpposite: teammateSet,
                        onCurrent: opponentSet,
                        oppositeLabel: "Teammates",
                        hasEnoughMembers: hasEnoughMembers
                    ) { profileId, isSelected in
                        toggleOpponent(profileId: profileId, isSelected: isSelected)
                    }
                }
            }
        } else {
            Text("No members found for this league.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func dropdownBlock(
        title: String,
        selectedCount: Int,
        query: Binding<String>,
        isOpen: Binding<Bool>,
        participants: [(profileId: String, displayName: String)],
        onOpposite: Set<String>,
        onCurrent: Set<String>,
        oppositeLabel: String,
        hasEnoughMembers: Bool,
        onToggle: @escaping (String, Bool) -> Void
    ) -> some View {
        Button {
            isOpen.wrappedValue.toggle()
            if isOpen.wrappedValue { query.wrappedValue = "" }
        } label: {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(selectedCount)/\(teamSize)")
                    .foregroundStyle(.secondary)
                Image(systemName: isOpen.wrappedValue ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!hasEnoughMembers)

        if isOpen.wrappedValue {
            let filtered = participants.filter { member in
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
                        let isSelected = onCurrent.contains(profileId)
                        let onOppositeSide = onOpposite.contains(profileId)
                        let disablePick = !isSelected && onOppositeSide
                        let canAdd = isSelected || onCurrent.count < teamSize
                        let rowDisabled = disablePick || !canAdd

                        Button {
                            guard !rowDisabled else { return }
                            onToggle(profileId, isSelected)
                        } label: {
                            HStack(spacing: 12) {
                                if onOppositeSide {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                } else {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? .blue : .secondary)
                                }
                                Text(member.displayName.isEmpty ? "Unknown" : member.displayName)
                                    .foregroundStyle(.primary)
                                if onOppositeSide {
                                    Text(oppositeLabel)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(rowDisabled)
                    }
                }
            }
            .frame(height: 260)
        }
    }

    @ViewBuilder
    private var statsSectionContent: some View {
        if participantProfileIds.isEmpty {
            Text("Select winners and losers to enter game stats.")
                .foregroundStyle(.secondary)
        } else {
            switch selectedGameType {
            case .pong:
                pongStatsView
            case .beerBall:
                beerBallStatsView
            case .battlePong:
                battlePongStatsView
            case .baseball:
                baseballStatsView
            }
        }
    }

    @ViewBuilder
    private var pongStatsView: some View {
        if teamSize == 1 {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Cup game", selection: $pongCupMode) {
                    ForEach(PongCupMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                ForEach(selectedParticipants, id: \.profileId) { participant in
                    Stepper(
                        value: binding(for: participant.profileId, in: $pongCupsByProfileId),
                        in: 0...pongCupMode.rawValue
                    ) {
                        Text("\(displayName(for: participant.profileId)): \(pongCupsByProfileId[participant.profileId] ?? 0) cups")
                    }
                }

                Picker("Last cup by", selection: $pongLastCupByProfileId) {
                    Text("None").tag("")
                    ForEach(Array(selectedWinnerProfileIds).sorted(), id: \.self) { winnerId in
                        Text(displayName(for: winnerId)).tag(winnerId)
                    }
                }

                let total = pongTotalCups
                Text("Pong total: \(total) / \(pongCupMode.rawValue)")
                    .font(.footnote)
                    .foregroundColor(total == pongCupMode.rawValue ? .secondary : .red)
            }
        }
    }

    @ViewBuilder
    private var beerBallStatsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(selectedParticipants, id: \.profileId) { participant in
                Stepper(
                    value: binding(for: participant.profileId, in: $beerBallNewCansByProfileId),
                    in: 0...99
                ) {
                    Text("\(displayName(for: participant.profileId)): \(beerBallNewCansByProfileId[participant.profileId] ?? 0) new cans")
                }
            }

            Picker("Finished first", selection: $beerBallFirstFinishedByProfileId) {
                Text("None").tag("")
                ForEach(selectedParticipants, id: \.profileId) { participant in
                    Text(displayName(for: participant.profileId)).tag(participant.profileId)
                }
            }
        }
    }

    @ViewBuilder
    private var battlePongStatsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(selectedParticipants, id: \.profileId) { participant in
                Stepper(
                    value: binding(for: participant.profileId, in: $battlePongCupsByProfileId),
                    in: 0...99
                ) {
                    Text("\(displayName(for: participant.profileId)): \(battlePongCupsByProfileId[participant.profileId] ?? 0) cups made")
                }
            }
        }
    }

    @ViewBuilder
    private var baseballStatsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(selectedParticipants, id: \.profileId) { participant in
                Stepper(
                    value: binding(for: participant.profileId, in: $baseballHitsByProfileId),
                    in: 0...99
                ) {
                    Text("\(displayName(for: participant.profileId)): \(baseballHitsByProfileId[participant.profileId] ?? 0) hits")
                }
            }
        }
    }

    private var canSubmitGameLog: Bool {
        !selectedCommunityId.isEmpty &&
        outcome != nil &&
        selectedWinnerProfileIds.count == teamSize &&
        selectedLoserProfileIds.count == teamSize &&
        hasRequiredPhotos &&
        currentStatsValidationError == nil
    }

    private var canSubmitWithoutPhotos: Bool {
        !selectedCommunityId.isEmpty &&
        outcome != nil &&
        selectedWinnerProfileIds.count == teamSize &&
        selectedLoserProfileIds.count == teamSize &&
        currentStatsValidationError == nil
    }

    private var submitDisableReasons: [String] {
        var reasons: [String] = []
        if frontPhotoData == nil || backPhotoData == nil {
            reasons.append("Photos are required and will be captured when you submit")
        }
        if selectedWinnerProfileIds.count != teamSize || selectedLoserProfileIds.count != teamSize {
            reasons.append("Winners and losers must each equal team size")
        }
        if selectedGameType == .pong, teamSize > 1, pongTotalCups != pongCupMode.rawValue {
            reasons.append("Pong total must equal selected cup mode")
        }
        if !selectedMVPProfileId.isEmpty &&
            !selectedLVPProfileId.isEmpty &&
            selectedMVPProfileId == selectedLVPProfileId {
            reasons.append("MVP and LVP must be different players")
        }
        return reasons
    }

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    private var hasRequiredPhotos: Bool {
        (frontPhotoData != nil && backPhotoData != nil) || !photoUrls.isEmpty
    }

    private var participantProfileIds: [String] {
        Array(selectedWinnerProfileIds.union(selectedLoserProfileIds)).sorted()
    }

    private var selectedParticipants: [(profileId: String, displayName: String)] {
        members.filter { participantProfileIds.contains($0.profileId) }
    }

    private var pongTotalCups: Int {
        participantProfileIds.reduce(0) { $0 + (pongCupsByProfileId[$1] ?? 0) }
    }

    private var currentStatsValidationError: String? {
        let participantSet = Set(participantProfileIds)
        guard !participantSet.isEmpty else { return nil }
        switch selectedGameType {
        case .pong:
            if teamSize == 1 {
                guard let soloWinnerProfileId, participantSet.contains(soloWinnerProfileId) else {
                    return "Winner must be selected for solo Pong."
                }
                // In solo mode, enforce fixed defaults.
                if pongCupMode != .ten { return "Solo Pong must use 10-cup mode." }
                if pongLastCupByProfileId != soloWinnerProfileId {
                    return "Solo Pong last cup must be the winner."
                }
                break
            }
            if pongTotalCups != pongCupMode.rawValue {
                return "Pong cups must add up to \(pongCupMode.rawValue)."
            }
            if !pongLastCupByProfileId.isEmpty && !selectedWinnerProfileIds.contains(pongLastCupByProfileId) {
                return "Last cup must be selected from the winning team."
            }
        case .beerBall:
            if !beerBallFirstFinishedByProfileId.isEmpty && !participantSet.contains(beerBallFirstFinishedByProfileId) {
                return "Finished-first player must be one of the selected participants."
            }
        case .battlePong, .baseball:
            break
        }
        if !selectedMVPProfileId.isEmpty && !participantSet.contains(selectedMVPProfileId) {
            return "MVP must be one of the selected participants."
        }
        if !selectedLVPProfileId.isEmpty && !participantSet.contains(selectedLVPProfileId) {
            return "LVP must be one of the selected participants."
        }
        if !selectedMVPProfileId.isEmpty &&
            !selectedLVPProfileId.isEmpty &&
            selectedMVPProfileId == selectedLVPProfileId {
            return "MVP and LVP must be different players."
        }
        return nil
    }

    private func teamSizeRange(for gameType: GameType) -> ClosedRange<Int> {
        switch gameType {
        case .pong, .beerBall:
            return 1...10
        case .battlePong, .baseball:
            return 3...20
        }
    }

    private func resetSelectionForScopeChange() {
        outcome = nil
        selectedWinnerProfileIds.removeAll()
        selectedLoserProfileIds.removeAll()
        isTeammateDropdownOpen = false
        isOpponentDropdownOpen = false
        teammateQuery = ""
        opponentQuery = ""
        syncStatsWithParticipants()
    }

    private func syncStatsWithParticipants() {
        let ids = Set(participantProfileIds)

        pongCupsByProfileId = keepOnly(ids: ids, from: pongCupsByProfileId)
        beerBallNewCansByProfileId = keepOnly(ids: ids, from: beerBallNewCansByProfileId)
        battlePongCupsByProfileId = keepOnly(ids: ids, from: battlePongCupsByProfileId)
        baseballHitsByProfileId = keepOnly(ids: ids, from: baseballHitsByProfileId)

        if !pongLastCupByProfileId.isEmpty && !ids.contains(pongLastCupByProfileId) {
            pongLastCupByProfileId = ""
        }
        if !beerBallFirstFinishedByProfileId.isEmpty && !ids.contains(beerBallFirstFinishedByProfileId) {
            beerBallFirstFinishedByProfileId = ""
        }
        if !selectedMVPProfileId.isEmpty && !ids.contains(selectedMVPProfileId) {
            selectedMVPProfileId = ""
        }
        if !selectedLVPProfileId.isEmpty && !ids.contains(selectedLVPProfileId) {
            selectedLVPProfileId = ""
        }

        // Solo Pong defaults: fixed 10-cup mode and last cup = winner.
        if selectedGameType == .pong, teamSize == 1, let winnerId = soloWinnerProfileId {
            pongCupMode = .ten
            pongLastCupByProfileId = winnerId
            var onlyWinner: [String: Int] = [:]
            onlyWinner[winnerId] = 10
            pongCupsByProfileId = onlyWinner
        }
    }

    private func keepOnly(ids: Set<String>, from map: [String: Int]) -> [String: Int] {
        var result: [String: Int] = [:]
        for id in ids {
            result[id] = max(0, map[id] ?? 0)
        }
        return result
    }

    private func binding(for profileId: String, in map: Binding<[String: Int]>) -> Binding<Int> {
        Binding<Int>(
            get: { map.wrappedValue[profileId] ?? 0 },
            set: { newValue in
                map.wrappedValue[profileId] = max(0, newValue)
            }
        )
    }

    private func displayName(for profileId: String) -> String {
        guard let member = members.first(where: { $0.profileId == profileId }) else {
            return "Unknown"
        }
        return member.displayName.isEmpty ? "Unknown" : member.displayName
    }

    private func namesList(for ids: Set<String>) -> String {
        let names = members
            .filter { ids.contains($0.profileId) }
            .map { $0.displayName.isEmpty ? "Unknown" : $0.displayName }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    private var soloWinnerProfileId: String? {
        teamSize == 1 ? selectedWinnerProfileIds.first : nil
    }

    private func lockUserIntoOutcome() {
        guard let myUserId = currentUserId else { return }
        selectedWinnerProfileIds.removeAll()
        selectedLoserProfileIds.removeAll()
        switch outcome {
        case .won:
            selectedWinnerProfileIds.insert(myUserId)
        case .lost:
            selectedLoserProfileIds.insert(myUserId)
        case .none:
            break
        }
    }

    private func toggleTeammate(profileId: String, isSelected: Bool) {
        guard let myUserId = currentUserId else { return }
        guard profileId != myUserId else { return }
        guard let outcome else { return }

        let isMySideWinners = (outcome == .won)
        let currentSet = isMySideWinners ? selectedWinnerProfileIds : selectedLoserProfileIds

        if isSelected {
            if isMySideWinners { selectedWinnerProfileIds.remove(profileId) }
            else { selectedLoserProfileIds.remove(profileId) }
        } else {
            guard currentSet.count < teamSize else { return }
            if isMySideWinners {
                selectedWinnerProfileIds.insert(profileId)
                selectedLoserProfileIds.remove(profileId)
            } else {
                selectedLoserProfileIds.insert(profileId)
                selectedWinnerProfileIds.remove(profileId)
            }
        }
        selectedWinnerProfileIds.subtract(selectedLoserProfileIds)
        selectedLoserProfileIds.subtract(selectedWinnerProfileIds)
    }

    private func toggleOpponent(profileId: String, isSelected: Bool) {
        guard let myUserId = currentUserId else { return }
        guard profileId != myUserId else { return }
        guard let outcome else { return }

        let opponentsAreLosers = (outcome == .won)
        let currentSet = opponentsAreLosers ? selectedLoserProfileIds : selectedWinnerProfileIds

        if isSelected {
            if opponentsAreLosers { selectedLoserProfileIds.remove(profileId) }
            else { selectedWinnerProfileIds.remove(profileId) }
        } else {
            guard currentSet.count < teamSize else { return }
            if opponentsAreLosers {
                selectedLoserProfileIds.insert(profileId)
                selectedWinnerProfileIds.remove(profileId)
            } else {
                selectedWinnerProfileIds.insert(profileId)
                selectedLoserProfileIds.remove(profileId)
            }
        }
        selectedWinnerProfileIds.subtract(selectedLoserProfileIds)
        selectedLoserProfileIds.subtract(selectedWinnerProfileIds)
    }

    private func submitGameLog() async {
        submitErrorMessage = nil
        showOpenSettingsAction = false
        guard canSubmitGameLog else { return }
        guard let uid = currentUserId else {
            submitErrorMessage = "Sign in again, then try submitting."
            return
        }
        let participants = participantProfileIds
        let winners = Array(selectedWinnerProfileIds).sorted()
        let losers = Array(selectedLoserProfileIds).sorted()
        guard !participants.isEmpty else {
            submitErrorMessage = "Select participants before submitting."
            return
        }
        guard let frontData = frontPhotoData, let backData = backPhotoData else {
            submitErrorMessage = "Capture both front and back photos before submitting."
            return
        }
        guard let combinedPhotoData = makeCombinedPhotoData(frontData: frontData, backData: backData) else {
            submitErrorMessage = "Could not combine front and back photos. Please retake and try again."
            return
        }

        let gameLogId = AppFirestore.db().collection("gameLogs").document().documentID
        let communityId = selectedCommunityId
        let gameType = selectedGameType
        let pongStats = selectedGameType == .pong ? buildPongStats() : nil
        let beerBallStats = selectedGameType == .beerBall ? buildBeerBallStats() : nil
        let battlePongStats = selectedGameType == .battlePong ? buildBattlePongStats() : nil
        let baseballStats = selectedGameType == .baseball ? buildBaseballStats() : nil
        let gameLogService = container.gameLogService

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let combinedUrl = try await gameLogService.uploadGamePhoto(
                communityId: communityId,
                gameLogId: gameLogId,
                side: "combined",
                data: combinedPhotoData,
                contentType: "image/jpeg"
            )

            let payload = GameLogCreatePayload(
                gameLogId: gameLogId,
                communityId: communityId,
                gameType: gameType.rawValue,
                createdByProfileId: uid,
                participantProfileIds: participants,
                winnerProfileIds: winners,
                loserProfileIds: losers,
                mvpProfileId: selectedMVPProfileId.isEmpty ? nil : selectedMVPProfileId,
                lvpProfileId: selectedLVPProfileId.isEmpty ? nil : selectedLVPProfileId,
                photoUrls: [combinedUrl],
                notes: nil,
                pongStats: pongStats,
                beerBallStats: beerBallStats,
                battlePongStats: battlePongStats,
                baseballStats: baseballStats
            )
            try await gameLogService.createGameLog(payload: payload)
            dismiss()
        } catch {
            submitErrorMessage = error.localizedDescription
            AppDebugLog.log("submitGameLog failed: \(error.localizedDescription)")
        }
    }

    private func handleSubmitTapped() async {
        submitErrorMessage = nil
        showOpenSettingsAction = false

        guard canSubmitWithoutPhotos else {
            submitErrorMessage = "Complete required game details before submitting."
            return
        }

        if !hasRequiredPhotos {
            let status = await CameraPermissionCoordinator.ensureVideoPermission()
            switch status {
            case .authorized:
                submitAfterCapture = true
                showDualCapture = true
            case .denied, .restricted:
                submitErrorMessage = "Camera access is required to submit a game. Enable access in Settings."
                showOpenSettingsAction = true
            case .cameraUnavailable:
                // Capture flow falls back to photo library if camera is unavailable.
                submitAfterCapture = true
                showDualCapture = true
            }
            return
        }

        await submitGameLog()
    }

    private func buildPongStats() -> [String: Any] {
        var stats: [String: Any] = [
            "cupMode": pongCupMode.rawValue,
            "playerCupsHit": pongCupsByProfileId
        ]
        if !pongLastCupByProfileId.isEmpty {
            stats["lastCupByProfileId"] = pongLastCupByProfileId
        }
        return stats
    }

    private func buildBeerBallStats() -> [String: Any] {
        var stats: [String: Any] = [
            "newCanCountByProfileId": beerBallNewCansByProfileId
        ]
        if !beerBallFirstFinishedByProfileId.isEmpty {
            stats["firstFinishedByProfileId"] = beerBallFirstFinishedByProfileId
        }
        return stats
    }

    private func buildBattlePongStats() -> [String: Any] {
        ["playerCupsHit": battlePongCupsByProfileId]
    }

    private func makeCombinedPhotoData(frontData: Data, backData: Data) -> Data? {
        guard let frontImage = UIImage(data: frontData), let backImage = UIImage(data: backData) else {
            return nil
        }

        // Normalize both images to the same height, then place side-by-side.
        let targetHeight = max(frontImage.size.height, backImage.size.height)
        let resizedFront = resized(image: frontImage, targetHeight: targetHeight)
        let resizedBack = resized(image: backImage, targetHeight: targetHeight)
        let combinedSize = CGSize(width: resizedFront.size.width + resizedBack.size.width, height: targetHeight)

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: combinedSize, format: format)
        let combinedImage = renderer.image { _ in
            UIColor.black.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: combinedSize)).fill()
            resizedFront.draw(in: CGRect(origin: .zero, size: resizedFront.size))
            resizedBack.draw(in: CGRect(
                x: resizedFront.size.width,
                y: 0,
                width: resizedBack.size.width,
                height: resizedBack.size.height
            ))
        }
        return combinedImage.jpegData(compressionQuality: 0.85)
    }

    private func resized(image: UIImage, targetHeight: CGFloat) -> UIImage {
        guard image.size.height > 0, image.size.height != targetHeight else { return image }
        let scale = targetHeight / image.size.height
        let targetSize = CGSize(width: image.size.width * scale, height: targetHeight)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func buildBaseballStats() -> [String: Any] {
        ["hitsByProfileId": baseballHitsByProfileId]
    }

    @ViewBuilder
    private func photoPreview(data: Data?, title: String) -> some View {
        VStack(spacing: 6) {
            if let data, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemGray5))
                    .frame(width: 120, height: 150)
                    .overlay(Text("No photo").foregroundStyle(.secondary))
            }
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func loadIfNeeded() async {
        guard communities.isEmpty && isLoading else { return }
        await load()
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let page = try await container.communityService.fetchCommunitiesPage(cursor: nil, pageSize: 25)
            communities = page.items
            selectedCommunityId = communities.first?.communityId ?? ""
            isLoading = false
            if !selectedCommunityId.isEmpty {
                Task { await loadMembers() }
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func loadMembers() async {
        guard !selectedCommunityId.isEmpty else { return }
        isMembersLoading = true
        membersErrorMessage = nil
        do {
            members = try await container.communityService.fetchMembers(communityId: selectedCommunityId)
            syncStatsWithParticipants()
        } catch {
            membersErrorMessage = error.localizedDescription
            members = []
        }
        isMembersLoading = false
    }
}

private enum GameType: String, CaseIterable, Identifiable {
    case pong = "PONG"
    case beerBall = "BEER_BALL"
    case battlePong = "BATTLE_PONG"
    case baseball = "BASEBALL"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pong: return "Pong"
        case .beerBall: return "Beer Ball"
        case .battlePong: return "Battle Pong"
        case .baseball: return "Baseball"
        }
    }
}

private enum PongCupMode: Int, CaseIterable, Identifiable {
    case six = 6
    case ten = 10

    var id: Int { rawValue }

    var displayName: String {
        "\(rawValue)-cup"
    }
}

