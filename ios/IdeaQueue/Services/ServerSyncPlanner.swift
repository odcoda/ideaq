struct SyncPlan: Equatable {
    let filesForUpload: [String: String]
    let uploadRequired: Bool
    let changedLocalPaths: [String]
}

enum ServerSyncPlanner {
    static func makePlan(
        local: [String: String],
        base: [String: String],
        server: [String: String]
    ) -> SyncPlan {
        let changedLocalPaths = Set(local.keys)
            .union(base.keys)
            .filter { local[$0] != base[$0] }
            .sorted()

        return SyncPlan(
            filesForUpload: local,
            uploadRequired: !changedLocalPaths.isEmpty,
            changedLocalPaths: changedLocalPaths
        )
    }
}
