import Foundation

struct LocalRepository {
    private let fileManager: FileManager
    let rootURL: URL

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    static func appRepository() -> LocalRepository {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LocalRepository(rootURL: baseURL.appendingPathComponent("IdeaQueueData", isDirectory: true))
    }

    private var queueURL: URL { rootURL.appendingPathComponent("queue", isDirectory: true) }
    private var completedURL: URL { rootURL.appendingPathComponent("completed", isDirectory: true) }
    private var projectsURL: URL { rootURL.appendingPathComponent("projects", isDirectory: true) }
    private var syncURL: URL { rootURL.appendingPathComponent(".sync", isDirectory: true) }
    private var baseSnapshotURL: URL { syncURL.appendingPathComponent("base", isDirectory: true) }
    private var metadataURL: URL { syncURL.appendingPathComponent("metadata.json") }

    func ensureDirectories() throws {
        for directory in [rootURL, queueURL, completedURL, projectsURL, syncURL, baseSnapshotURL] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func loadDocument() throws -> DashboardDocument {
        try ensureDirectories()
        return DashboardDocument(
            queueProjects: try loadIdeas(from: queueURL, excluding: ["PROJECTS.json"]),
            completedProjects: try loadIdeas(from: completedURL, excluding: []),
            projectOrder: try loadProjectOrder()
        )
    }

    func saveDocument(_ document: DashboardDocument) throws {
        try ensureDirectories()
        try saveIdeas(document.queueProjects, to: queueURL)
        try saveIdeas(document.completedProjects, to: completedURL)
        try writeJSON(document.projectOrder, to: queueURL.appendingPathComponent("PROJECTS.json"))
    }

    func loadTrackedFiles() throws -> [String: String] {
        try trackedFiles(at: rootURL)
    }

    func loadBaseTrackedFiles() throws -> [String: String] {
        try ensureDirectories()
        return try trackedFiles(at: baseSnapshotURL)
    }

    func replaceLocalTrackedFiles(with files: [String: String]) throws {
        try replaceTrackedFiles(at: rootURL, files: files)
    }

    func replaceBaseTrackedFiles(with files: [String: String]) throws {
        try replaceTrackedFiles(at: baseSnapshotURL, files: files)
    }

    func loadSyncMetadata() throws -> SyncMetadata {
        try ensureDirectories()
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode(SyncMetadata.self, from: data)
    }

    func saveSyncMetadata(_ metadata: SyncMetadata) throws {
        try ensureDirectories()
        try writeJSON(metadata, to: metadataURL)
    }

    private func loadProjectOrder() throws -> [String] {
        let path = queueURL.appendingPathComponent("PROJECTS.json")
        guard fileManager.fileExists(atPath: path.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: path)
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            return []
        }
    }

    private func loadIdeas(from directory: URL, excluding excludedNames: Set<String>) throws -> [String: [Idea]] {
        guard fileManager.fileExists(atPath: directory.path) else {
            return [:]
        }

        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !excludedNames.contains($0.lastPathComponent) }

        var result: [String: [Idea]] = [:]
        let decoder = JSONDecoder()
        for file in files {
            do {
                let data = try Data(contentsOf: file)
                let ideas = try decoder.decode([Idea].self, from: data)
                result[file.deletingPathExtension().lastPathComponent] = ideas
            } catch {
                result[file.deletingPathExtension().lastPathComponent] = []
            }
        }
        return result
    }

    private func saveIdeas(_ ideasByProject: [String: [Idea]], to directory: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for (project, ideas) in ideasByProject {
            try writeJSON(ideas, to: directory.appendingPathComponent("\(project).json"))
        }
    }

    private func trackedFiles(at root: URL) throws -> [String: String] {
        var files: [String: String] = [:]
        for relativeDirectory in trackedDirectories {
            let directory = root.appendingPathComponent(relativeDirectory, isDirectory: true)
            guard fileManager.fileExists(atPath: directory.path) else { continue }

            let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)
            while let entry = enumerator?.nextObject() as? URL {
                guard entry.pathExtension == "json" else { continue }
                let relativePath = try relativeTrackedPath(for: entry, under: root)
                files[relativePath] = try String(contentsOf: entry, encoding: .utf8)
            }
        }
        return files
    }

    private func relativeTrackedPath(for entry: URL, under root: URL) throws -> String {
        let rootComponents = root.resolvingSymlinksInPath().pathComponents
        let entryComponents = entry.resolvingSymlinksInPath().pathComponents
        guard entryComponents.starts(with: rootComponents), entryComponents.count > rootComponents.count else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return entryComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private func replaceTrackedFiles(at root: URL, files: [String: String]) throws {
        try ensureDirectories()

        let existingFiles = try trackedFiles(at: root)
        let filePathsToDelete = Set(existingFiles.keys).subtracting(files.keys)
        for relativePath in filePathsToDelete {
            let fileURL = root.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        }

        for (relativePath, contents) in files {
            let fileURL = root.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        let text = String(decoding: data, as: UTF8.self) + "\n"
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private var trackedDirectories: [String] {
        ["queue", "completed", "projects"]
    }
}
