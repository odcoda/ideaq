import XCTest
@testable import IdeaQueue

final class DashboardDocumentTests: XCTestCase {
    func testRenamePropagatesThroughRelatedFields() {
        var document = DashboardDocument(
            queueProjects: [
                "alpha": [
                    Idea(
                        name: "idea_one",
                        humanIdea: "alpha",
                        description: "first",
                        difficulty: "S",
                        related: ["beta_shared"],
                        priority: "none"
                    )
                ],
                "beta": [
                    Idea(
                        name: "beta_shared",
                        humanIdea: "beta",
                        description: "second",
                        difficulty: "M",
                        related: ["idea_one"],
                        priority: "high"
                    )
                ]
            ],
            completedProjects: [:],
            projectOrder: ["alpha", "beta"]
        )

        document.updateTextField(project: "alpha", index: 0, field: .name, value: "idea_renamed")

        XCTAssertEqual(document.queueProjects["alpha"]?[0].name, "idea_renamed")
        XCTAssertEqual(document.queueProjects["beta"]?[0].related, ["idea_renamed"])
    }

    func testCompleteMovesIdeaIntoCompletedProject() {
        var document = DashboardDocument(
            queueProjects: [
                "alpha": [
                    Idea.default
                ]
            ],
            completedProjects: [:],
            projectOrder: ["alpha"]
        )

        let completed = document.completeIdea(project: "alpha", index: 0)

        XCTAssertEqual(completed, Idea.default)
        XCTAssertEqual(document.queueProjects["alpha"], [])
        XCTAssertEqual(document.completedProjects["alpha"], [Idea.default])
    }
}

final class LocalRepositoryTests: XCTestCase {
    func testLoadTrackedFilesHandlesFilesystemAliasInEnumeratedURLs() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let repository = LocalRepository(rootURL: root, fileManager: fileManager)
        try repository.ensureDirectories()
        try "[]\n".write(
            to: root.appendingPathComponent("queue/PROJECTS.json"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(try repository.loadTrackedFiles(), ["queue/PROJECTS.json": "[]\n"])
    }
}
