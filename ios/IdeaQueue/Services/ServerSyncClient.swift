import Foundation

struct ServerSnapshot: Codable, Equatable {
    let revision: String
    let files: [String: String]
}

enum ServerSyncError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Set a valid sync server URL before syncing."
        case .invalidResponse:
            return "The sync server returned an invalid response."
        case .message(let message):
            return message
        }
    }
}

protocol ServerSyncClient {
    func fetchSnapshot(configuration: SyncConfiguration, token: String) async throws -> ServerSnapshot
    func uploadSnapshot(
        configuration: SyncConfiguration,
        token: String,
        baseRevision: String,
        files: [String: String]
    ) async throws -> ServerSnapshot
}

final class HTTPServerSyncClient: ServerSyncClient {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchSnapshot(configuration: SyncConfiguration, token: String) async throws -> ServerSnapshot {
        var request = URLRequest(url: try snapshotURL(configuration: configuration))
        request.httpMethod = "GET"
        setHeaders(on: &request, token: token)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(ServerSnapshot.self, from: data)
    }

    func uploadSnapshot(
        configuration: SyncConfiguration,
        token: String,
        baseRevision: String,
        files: [String: String]
    ) async throws -> ServerSnapshot {
        var request = URLRequest(url: try snapshotURL(configuration: configuration))
        request.httpMethod = "PUT"
        setHeaders(on: &request, token: token)

        let body = UploadRequest(baseRevision: baseRevision, files: files)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(ServerSnapshot.self, from: data)
    }

    private func snapshotURL(configuration: SyncConfiguration) throws -> URL {
        let trimmedURL = configuration.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStoreID = configuration.storeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedStoreID.isEmpty, let baseURL = URL(string: trimmedURL) else {
            throw ServerSyncError.invalidConfiguration
        }

        return baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("stores")
            .appendingPathComponent(trimmedStoreID)
            .appendingPathComponent("snapshot")
    }

    private func setHeaders(on request: inout URLRequest, token: String) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("IdeaQueue-iOS", forHTTPHeaderField: "User-Agent")

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty {
            request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServerSyncError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let error = try? decoder.decode(ServerErrorResponse.self, from: data) {
                throw ServerSyncError.message(error.error ?? error.message)
            }
            throw ServerSyncError.message(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
        }
    }
}

private struct UploadRequest: Encodable {
    let baseRevision: String
    let files: [String: String]

    enum CodingKeys: String, CodingKey {
        case baseRevision = "base_revision"
        case files
    }
}

private struct ServerErrorResponse: Decodable {
    let message: String
    let error: String?
}
