import XCTest
@testable import IdeaQueue

final class ServerSyncPlannerTests: XCTestCase {
    func testSyncUploadsLocalChangesWhenServerIsUnchanged() {
        let local = ["queue/alpha.json": "local"]
        let base = ["queue/alpha.json": "base"]
        let server = ["queue/alpha.json": "base"]

        let plan = ServerSyncPlanner.makePlan(local: local, base: base, server: server)

        XCTAssertEqual(plan.filesForUpload["queue/alpha.json"], "local")
        XCTAssertTrue(plan.uploadRequired)
        XCTAssertEqual(plan.changedLocalPaths, ["queue/alpha.json"])
    }

    func testSyncAcceptsServerChangesWhenLocalIsUnchanged() {
        let local = [
            "queue/alpha.json": "base",
            "queue/PROJECTS.json": "order"
        ]
        let base = [
            "queue/alpha.json": "base",
            "queue/PROJECTS.json": "order"
        ]
        let server = [
            "queue/alpha.json": "server",
            "queue/PROJECTS.json": "order"
        ]

        let plan = ServerSyncPlanner.makePlan(local: local, base: base, server: server)

        XCTAssertEqual(plan.filesForUpload["queue/alpha.json"], "base")
        XCTAssertFalse(plan.uploadRequired)
        XCTAssertEqual(plan.changedLocalPaths, [])
    }

    func testSyncAllowsConflictingFileEditsToBeResolvedByServer() {
        let local = ["queue/alpha.json": "local"]
        let base = ["queue/alpha.json": "base"]
        let server = ["queue/alpha.json": "server"]

        let plan = ServerSyncPlanner.makePlan(local: local, base: base, server: server)

        XCTAssertTrue(plan.uploadRequired)
        XCTAssertEqual(plan.filesForUpload, local)
        XCTAssertEqual(plan.changedLocalPaths, ["queue/alpha.json"])
    }
}
