import Foundation
import SwiftUI

@MainActor
final class DashboardStore: ObservableObject {
    struct DeletedIdeaState: Identifiable {
        let id = UUID()
        let project: String
        let index: Int
        let idea: Idea
    }

    @Published private(set) var document: DashboardDocument
    @Published var enabledPriorities: Set<String> = Set(PriorityOption.allCases.map(\.rawValue))
    @Published var collapsedProjects: Set<String> = []
    @Published var syncConfiguration: SyncConfiguration {
        didSet {
            persistSyncConfiguration()
        }
    }
    @Published var serverToken: String {
        didSet {
            credentialStore.saveToken(serverToken)
        }
    }
    @Published var syncMetadata: SyncMetadata
    @Published var syncStatusMessage: String?
    @Published var isSyncing = false
    @Published var pendingDelete: DeletedIdeaState?

    private let repository: LocalRepository
    private let credentialStore: ServerCredentialStore
    private let syncClient: ServerSyncClient
    private let defaults: UserDefaults
    private var deleteClearTask: Task<Void, Never>?

    init(
        repository: LocalRepository = .appRepository(),
        credentialStore: ServerCredentialStore = ServerCredentialStore(),
        syncClient: ServerSyncClient = HTTPServerSyncClient(),
        defaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.credentialStore = credentialStore
        self.syncClient = syncClient
        self.defaults = defaults
        self.syncConfiguration = Self.loadSyncConfiguration(from: defaults)
        self.serverToken = credentialStore.loadToken()

        do {
            self.document = try repository.loadDocument()
            self.syncMetadata = try repository.loadSyncMetadata()
        } catch {
            self.document = .empty
            self.syncMetadata = .empty
            self.syncStatusMessage = error.localizedDescription
        }

        self.document.normalizeProjectOrder()
        persistDocument()
    }

    var orderedProjects: [String] {
        document.orderedProjects()
    }

    func visibleIdeas(in project: String) -> [(Int, Idea)] {
        (document.queueProjects[project] ?? [])
            .enumerated()
            .filter { enabledPriorities.contains($0.element.priority) || ($0.element.priority.isEmpty && enabledPriorities.contains("none")) }
            .map { ($0.offset, $0.element) }
    }

    func ideaField(project: String, index: Int, field: IdeaTextField) -> String {
        guard let idea = document.queueProjects[project]?[safe: index] else { return "" }
        switch field {
        case .name:
            return idea.name
        case .humanIdea:
            return idea.humanIdea
        case .description:
            return idea.description
        case .difficulty:
            return idea.difficulty
        }
    }

    func relatedText(project: String, index: Int) -> String {
        document.queueProjects[project]?[safe: index]?.related.joined(separator: ", ") ?? ""
    }

    func priority(project: String, index: Int) -> String {
        document.queueProjects[project]?[safe: index]?.priority ?? PriorityOption.none.rawValue
    }

    func updateTextField(project: String, index: Int, field: IdeaTextField, value: String) {
        document.updateTextField(project: project, index: index, field: field, value: value)
        persistDocument()
    }

    func updateRelated(project: String, index: Int, value: String) {
        let related = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        document.updateRelated(project: project, index: index, related: related)
        persistDocument()
    }

    func updatePriority(project: String, index: Int, value: String) {
        document.updatePriority(project: project, index: index, priority: value)
        persistDocument()
    }

    func togglePriority(_ priority: String) {
        if enabledPriorities.contains(priority) {
            enabledPriorities.remove(priority)
        } else {
            enabledPriorities.insert(priority)
        }
    }

    func collapseAll() {
        collapsedProjects = Set(orderedProjects)
    }

    func expandAll() {
        collapsedProjects.removeAll()
    }

    func toggleCollapse(project: String) {
        if collapsedProjects.contains(project) {
            collapsedProjects.remove(project)
        } else {
            collapsedProjects.insert(project)
        }
    }

    func addProject(named rawName: String) {
        let normalized = rawName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9_-]", with: "_", options: .regularExpression)
        guard !normalized.isEmpty else { return }
        document.addProject(normalized)
        collapsedProjects.remove(normalized)
        persistDocument()
    }

    func addIdea(to project: String) {
        document.addIdea(to: project)
        collapsedProjects.remove(project)
        persistDocument()
    }

    func moveIdeaUp(project: String, index: Int) {
        document.moveIdeaUp(project: project, index: index)
        persistDocument()
    }

    func moveIdeaDown(project: String, index: Int) {
        document.moveIdeaDown(project: project, index: index)
        persistDocument()
    }

    func moveIdea(project: String, index: Int, to destinationProject: String) {
        let toIndex = document.queueProjects[destinationProject]?.count ?? 0
        document.moveIdea(
            fromProject: project,
            fromIndex: index,
            toProject: destinationProject,
            toIndex: toIndex
        )
        persistDocument()
    }

    func completeIdea(project: String, index: Int) {
        _ = document.completeIdea(project: project, index: index)
        persistDocument()
    }

    func deleteIdea(project: String, index: Int) {
        guard let deleted = document.deleteIdea(project: project, index: index) else { return }
        pendingDelete = DeletedIdeaState(project: project, index: index, idea: deleted)
        persistDocument()

        deleteClearTask?.cancel()
        deleteClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            await MainActor.run {
                self?.pendingDelete = nil
            }
        }
    }

    func undoDelete() {
        guard let pendingDelete else { return }
        document.restoreIdea(pendingDelete.idea, to: pendingDelete.project, at: pendingDelete.index)
        self.pendingDelete = nil
        deleteClearTask?.cancel()
        persistDocument()
    }

    func sortProjectByPriority(_ project: String) {
        document.sortProjectByPriority(project)
        persistDocument()
    }

    func sortAllByPriority() {
        document.sortAllByPriority()
        persistDocument()
    }

    func moveProjectUp(_ project: String) {
        document.moveProjectUp(project)
        persistDocument()
    }

    func moveProjectDown(_ project: String) {
        document.moveProjectDown(project)
        persistDocument()
    }

    func syncWithServer() async {
        guard syncConfiguration.isConfigured else {
            syncStatusMessage = "Set a server URL to sync. Local edits are still saved on this device."
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let localFiles = try repository.loadTrackedFiles()
            let baseFiles = try repository.loadBaseTrackedFiles()
            let serverSnapshot = try await syncClient.fetchSnapshot(
                configuration: syncConfiguration,
                token: serverToken
            )
            let plan = try ServerSyncPlanner.makePlan(
                local: localFiles,
                base: baseFiles,
                server: serverSnapshot.files
            )

            let finalSnapshot: ServerSnapshot
            if plan.uploadRequired {
                finalSnapshot = try await syncClient.uploadSnapshot(
                    configuration: syncConfiguration,
                    token: serverToken,
                    baseRevision: serverSnapshot.revision,
                    files: plan.mergedFiles
                )
            } else {
                finalSnapshot = ServerSnapshot(
                    revision: serverSnapshot.revision,
                    files: plan.mergedFiles
                )
            }

            try repository.replaceLocalTrackedFiles(with: finalSnapshot.files)
            try repository.replaceBaseTrackedFiles(with: finalSnapshot.files)

            syncMetadata = SyncMetadata(
                lastServerRevision: finalSnapshot.revision,
                lastSyncDate: Date(),
                lastAction: "sync"
            )
            try repository.saveSyncMetadata(syncMetadata)
            document = try repository.loadDocument()
            document.normalizeProjectOrder()
            syncStatusMessage = syncMessage(uploaded: plan.changedServerPaths.count, total: finalSnapshot.files.count)
        } catch {
            syncStatusMessage = "\(error.localizedDescription) Local edits remain saved on this device."
        }
    }

    private func persistDocument() {
        do {
            document.normalizeProjectOrder()
            try repository.saveDocument(document)
        } catch {
            syncStatusMessage = error.localizedDescription
        }
    }

    private func persistSyncConfiguration() {
        do {
            let data = try JSONEncoder().encode(syncConfiguration)
            defaults.set(data, forKey: "syncConfiguration")
        } catch {
            syncStatusMessage = error.localizedDescription
        }
    }

    private func syncMessage(uploaded: Int, total: Int) -> String {
        if uploaded == 0 {
            return "Synced \(total) files from the server."
        }
        return "Synced \(total) files and uploaded \(uploaded) local changes."
    }

    private static func loadSyncConfiguration(from defaults: UserDefaults) -> SyncConfiguration {
        if let data = defaults.data(forKey: "syncConfiguration"),
           let configuration = try? JSONDecoder().decode(SyncConfiguration.self, from: data) {
            return configuration
        }

        return .default
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
