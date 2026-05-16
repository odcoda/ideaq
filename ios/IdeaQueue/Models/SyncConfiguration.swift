import Foundation

struct SyncConfiguration: Codable, Equatable {
    var serverURL: String
    var storeID: String

    var isConfigured: Bool {
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStoreID = storeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), let scheme = url.scheme, url.host != nil else {
            return false
        }

        return ["http", "https"].contains(scheme.lowercased()) && !trimmedStoreID.isEmpty
    }

    static let `default` = SyncConfiguration(
        serverURL: "",
        storeID: "default"
    )
}

struct SyncMetadata: Codable, Equatable {
    var lastServerRevision: String?
    var lastSyncDate: Date?
    var lastAction: String?

    static let empty = SyncMetadata(
        lastServerRevision: nil,
        lastSyncDate: nil,
        lastAction: nil
    )
}
