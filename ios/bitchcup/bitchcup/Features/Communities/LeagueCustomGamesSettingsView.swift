import SwiftUI

/// League members: CRUD for `communities/{communityId}/gameDefinitions/*` (Phase E3).
struct LeagueCustomGamesSettingsView: View {
    let communityId: String

    @EnvironmentObject private var container: DependencyContainer

    private let headerFont = Font.custom("NeueHaasDisplay-Bold", size: 15)
    private let bodyFont = Font.custom("NeueHaasDisplay-Mediu", size: 17)
    private let accent = Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)

    @State private var definitions: [GameDefinitionRecord] = []
    @State private var isLoading = true
    @State private var listError: String?

    @State private var editorMode: EditorMode?
    @State private var editorName = ""
    @State private var editorRules = ""
    @State private var editorSaving = false
    @State private var editorError: String?

    @State private var deleteTarget: GameDefinitionRecord?
    @State private var deleteInProgress = false
    @State private var deleteError: String?

    private enum EditorMode: Identifiable {
        case create
        case edit(GameDefinitionRecord)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let row): return "edit_\(row.gameDefinitionId)"
            }
        }

        var isCreate: Bool {
            if case .create = self { return true }
            return false
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let listError {
                VStack(spacing: 12) {
                    Text(listError)
                        .font(AppFont.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await reload() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                List {
                    if let deleteError {
                        Text(deleteError)
                            .font(AppFont.caption)
                            .foregroundStyle(.red)
                            .listRowBackground(Color.white)
                    }
                    if definitions.isEmpty {
                        Text("No custom games yet. Tap Add to create one for this league.")
                            .font(AppFont.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.white)
                    } else {
                        ForEach(definitions) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(row.name)
                                    .font(bodyFont)
                                    .foregroundStyle(.black)
                                if let rules = row.rulesText?.trimmingCharacters(in: .whitespacesAndNewlines),
                                   !rules.isEmpty {
                                    Text(rules)
                                        .font(AppFont.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.white)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editorError = nil
                                editorMode = .edit(row)
                                editorName = row.name
                                editorRules = row.rulesText ?? ""
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteError = nil
                                    deleteTarget = row
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.white)
            }
        }
        .background(Color.white)
        .navigationTitle("Custom game types")
        .navigationBarTitleDisplayMode(.inline)
        .communityFlowNavigationBarChrome()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                CommunityFlowBackToolbarButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editorError = nil
                    editorMode = .create
                    editorName = ""
                    editorRules = ""
                } label: {
                    Text("Add")
                        .font(.custom("NeueHaasDisplay-Mediu", size: 16))
                        .foregroundStyle(accent)
                }
                .disabled(isLoading || deleteInProgress)
            }
        }
        .sheet(item: $editorMode) { mode in
            NavigationStack {
                Form {
                    Section {
                        TextField("Name", text: $editorName)
                            .font(AppFont.body)
                        TextField("Rules (optional)", text: $editorRules, axis: .vertical)
                            .font(AppFont.body)
                            .lineLimit(5...12)
                    } header: {
                        Text(mode.isCreate ? "New custom game" : "Edit custom game")
                            .font(headerFont)
                            .foregroundStyle(accent)
                    }
                    if let editorError {
                        Section {
                            Text(editorError)
                                .font(AppFont.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.white)
                .navigationTitle(mode.isCreate ? "Add" : "Edit")
                .navigationBarTitleDisplayMode(.inline)
                .communityFlowNavigationBarChrome()
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        CommunityFlowAccentToolbarButton(title: "Cancel") {
                            editorMode = nil
                        }
                        .disabled(editorSaving)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Task { await saveEditor(mode: mode) }
                        } label: {
                            Text(mode.isCreate ? "Create" : "Save")
                                .font(.custom("NeueHaasDisplay-Mediu", size: 16))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(accent, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(editorSaving || editorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(editorSaving || editorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Delete “\(deleteTarget?.name ?? "")”?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await confirmDelete() }
            }
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
        } message: {
            Text("Players can no longer log new games with this type. Existing logs are unchanged.")
        }
        .task {
            await reload()
        }
    }

    private func confirmDelete() async {
        guard let row = deleteTarget else { return }
        deleteInProgress = true
        defer {
            deleteInProgress = false
            deleteTarget = nil
        }
        do {
            try await container.communityService.deleteGameDefinition(
                communityId: communityId,
                gameDefinitionId: row.gameDefinitionId
            )
            await reload()
        } catch {
            await MainActor.run {
                deleteError = error.localizedDescription
            }
        }
    }

    private func reload() async {
        isLoading = true
        listError = nil
        do {
            let rows = try await container.communityService.listGameDefinitions(communityId: communityId)
            await MainActor.run {
                definitions = rows
                isLoading = false
            }
        } catch {
            await MainActor.run {
                listError = error.localizedDescription
                definitions = []
                isLoading = false
            }
        }
    }

    private func saveEditor(mode: EditorMode) async {
        let trimmedName = editorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            editorError = "Enter a name."
            return
        }
        let rulesTrimmed = editorRules.trimmingCharacters(in: .whitespacesAndNewlines)
        let rulesPayload: String? = rulesTrimmed.isEmpty ? nil : rulesTrimmed

        editorSaving = true
        editorError = nil
        defer { editorSaving = false }
        do {
            switch mode {
            case .create:
                _ = try await container.communityService.createGameDefinition(
                    communityId: communityId,
                    name: trimmedName,
                    rulesText: rulesPayload
                )
            case .edit(let row):
                try await container.communityService.updateGameDefinition(
                    communityId: communityId,
                    gameDefinitionId: row.gameDefinitionId,
                    name: trimmedName,
                    rulesText: rulesPayload
                )
            }
            await MainActor.run { editorMode = nil }
            await reload()
        } catch {
            editorError = error.localizedDescription
        }
    }
}
