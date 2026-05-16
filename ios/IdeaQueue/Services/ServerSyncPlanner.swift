import Foundation

enum SyncPlannerError: LocalizedError, Equatable {
    case conflicts([String])

    var errorDescription: String? {
        switch self {
        case .conflicts(let paths):
            return "Conflicts detected in: \(paths.joined(separator: ", "))"
        }
    }
}

struct SyncPlan: Equatable {
    let mergedFiles: [String: String]
    let uploadRequired: Bool
    let changedServerPaths: [String]
}

enum ServerSyncPlanner {
    static func makePlan(
        local: [String: String],
        base: [String: String],
        server: [String: String]
    ) throws -> SyncPlan {
        let paths = Set(local.keys).union(base.keys).union(server.keys)
        var conflicts: [String] = []
        var mergedFiles: [String: String] = [:]

        for path in paths.sorted() {
            let localValue = local[path]
            let baseValue = base[path]
            let serverValue = server[path]

            if hasConflict(local: localValue, base: baseValue, server: serverValue) {
                conflicts.append(path)
                continue
            }

            let resolvedValue: String?
            if localValue == serverValue {
                resolvedValue = localValue
            } else if localValue == baseValue {
                resolvedValue = serverValue
            } else {
                resolvedValue = localValue
            }

            if let resolvedValue {
                mergedFiles[path] = resolvedValue
            }
        }

        if !conflicts.isEmpty {
            throw SyncPlannerError.conflicts(conflicts)
        }

        let changedServerPaths = paths
            .filter { mergedFiles[$0] != server[$0] }
            .sorted()

        return SyncPlan(
            mergedFiles: mergedFiles,
            uploadRequired: !changedServerPaths.isEmpty,
            changedServerPaths: changedServerPaths
        )
    }

    private static func hasConflict(local: String?, base: String?, server: String?) -> Bool {
        local != server && local != base && server != base
    }
}
