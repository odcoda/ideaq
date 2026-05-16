import XCTest
@testable import IdeaQueue

final class ServerSyncPlannerTests: XCTestCase {
    func testSyncPreservesLocalChangesWhenServerIsUnchanged() throws {
        let local = ["queue/alpha.json": "local"]
        let base = ["queue/alpha.json": "base"]
        let server = ["queue/alpha.json": "base"]

        let plan = try ServerSyncPlanner.makePlan(local: local, base: base, server: server)

        XCTAssertEqual(plan.mergedFiles["queue/alpha.json"], "local")
        XCTAssertTrue(plan.uploadRequired)
        XCTAssertEqual(plan.changedServerPaths, ["queue/alpha.json"])
    }

    func testSyncAcceptsServerChangesWhenLocalIsUnchanged() throws {
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

        let plan = try ServerSyncPlanner.makePlan(local: local, base: base, server: server)

        XCTAssertEqual(plan.mergedFiles["queue/alpha.json"], "server")
        XCTAssertFalse(plan.uploadRequired)
    }

    func testSyncDetectsConflictingFileEdits() {
        let local = ["queue/alpha.json": "local"]
        let base = ["queue/alpha.json": "base"]
        let server = ["queue/alpha.json": "server"]

        XCTAssertThrowsError(
            try ServerSyncPlanner.makePlan(local: local, base: base, server: server)
        ) { error in
            XCTAssertEqual(error as? SyncPlannerError, .conflicts(["queue/alpha.json"]))
        }
    }
}
