import Foundation

struct DashboardDocument: Equatable {
    var queueProjects: [String: [Idea]]
    var completedProjects: [String: [Idea]]
    var projectOrder: [String]

    static let empty = DashboardDocument(
        queueProjects: [:],
        completedProjects: [:],
        projectOrder: []
    )

    mutating func normalizeProjectOrder() {
        let known = Set(projectOrder)
        let extras = queueProjects.keys
            .filter { !known.contains($0) }
            .sorted()
        projectOrder.append(contentsOf: extras)
    }

    func orderedProjects() -> [String] {
        var order = projectOrder
        let known = Set(order)
        for name in queueProjects.keys.sorted() where !known.contains(name) {
            order.append(name)
        }
        return order
    }

    mutating func addProject(_ name: String) {
        guard !name.isEmpty else { return }
        if queueProjects[name] == nil {
            queueProjects[name] = []
        }
        if !projectOrder.contains(name) {
            projectOrder.append(name)
        }
    }

    mutating func addIdea(to project: String) {
        addProject(project)
        queueProjects[project, default: []].append(.default)
    }

    mutating func updateTextField(
        project: String,
        index: Int,
        field: IdeaTextField,
        value: String
    ) {
        guard var ideas = queueProjects[project], ideas.indices.contains(index) else {
            return
        }

        let oldName = ideas[index].name
        switch field {
        case .name:
            ideas[index].name = value
        case .humanIdea:
            ideas[index].humanIdea = value
        case .description:
            ideas[index].description = value
        case .difficulty:
            ideas[index].difficulty = value
        }
        queueProjects[project] = ideas

        if field == .name, oldName != value {
            renameRelatedReferences(from: oldName, to: value)
        }
    }

    mutating func updateRelated(project: String, index: Int, related: [String]) {
        guard var ideas = queueProjects[project], ideas.indices.contains(index) else {
            return
        }
        ideas[index].related = related
        queueProjects[project] = ideas
    }

    mutating func updatePriority(project: String, index: Int, priority: String) {
        guard var ideas = queueProjects[project], ideas.indices.contains(index) else {
            return
        }
        ideas[index].priority = priority
        queueProjects[project] = ideas
    }

    mutating func moveIdea(
        fromProject: String,
        fromIndex: Int,
        toProject: String,
        toIndex: Int
    ) {
        guard var sourceIdeas = queueProjects[fromProject], sourceIdeas.indices.contains(fromIndex) else {
            return
        }

        let idea = sourceIdeas.remove(at: fromIndex)
        queueProjects[fromProject] = sourceIdeas
        addProject(toProject)

        var targetIdeas = queueProjects[toProject, default: []]
        let targetIndex = max(0, min(toIndex, targetIdeas.count))
        targetIdeas.insert(idea, at: targetIndex)
        queueProjects[toProject] = targetIdeas
    }

    mutating func moveIdeaUp(project: String, index: Int) {
        guard index > 0 else { return }
        moveIdea(fromProject: project, fromIndex: index, toProject: project, toIndex: index - 1)
    }

    mutating func moveIdeaDown(project: String, index: Int) {
        guard let ideas = queueProjects[project], index < ideas.count - 1 else { return }
        moveIdea(fromProject: project, fromIndex: index, toProject: project, toIndex: index + 1)
    }

    mutating func completeIdea(project: String, index: Int) -> Idea? {
        guard var ideas = queueProjects[project], ideas.indices.contains(index) else {
            return nil
        }
        let idea = ideas.remove(at: index)
        queueProjects[project] = ideas
        completedProjects[project, default: []].append(idea)
        return idea
    }

    mutating func deleteIdea(project: String, index: Int) -> Idea? {
        guard var ideas = queueProjects[project], ideas.indices.contains(index) else {
            return nil
        }
        let idea = ideas.remove(at: index)
        queueProjects[project] = ideas
        return idea
    }

    mutating func restoreIdea(_ idea: Idea, to project: String, at index: Int) {
        addProject(project)
        var ideas = queueProjects[project, default: []]
        let restoredIndex = max(0, min(index, ideas.count))
        ideas.insert(idea, at: restoredIndex)
        queueProjects[project] = ideas
    }

    mutating func sortProjectByPriority(_ project: String) {
        guard var ideas = queueProjects[project] else { return }
        ideas.sort { lhs, rhs in
            PriorityOption.sortRank(for: lhs.priority) < PriorityOption.sortRank(for: rhs.priority)
        }
        queueProjects[project] = ideas
    }

    mutating func sortAllByPriority() {
        for project in queueProjects.keys {
            sortProjectByPriority(project)
        }
    }

    mutating func moveProjectUp(_ project: String) {
        guard let index = projectOrder.firstIndex(of: project), index > 0 else { return }
        projectOrder.swapAt(index, index - 1)
    }

    mutating func moveProjectDown(_ project: String) {
        guard let index = projectOrder.firstIndex(of: project), index < projectOrder.count - 1 else {
            return
        }
        projectOrder.swapAt(index, index + 1)
    }

    private mutating func renameRelatedReferences(from oldName: String, to newName: String) {
        guard !oldName.isEmpty, !newName.isEmpty else { return }
        for project in queueProjects.keys {
            var ideas = queueProjects[project, default: []]
            var didChange = false
            for ideaIndex in ideas.indices {
                if ideas[ideaIndex].related.contains(oldName) {
                    ideas[ideaIndex].related = ideas[ideaIndex].related.map { item in
                        item == oldName ? newName : item
                    }
                    didChange = true
                }
            }
            if didChange {
                queueProjects[project] = ideas
            }
        }
    }
}
