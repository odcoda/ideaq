import Foundation

struct Idea: Codable, Equatable {
    var name: String
    var humanIdea: String
    var description: String
    var difficulty: String
    var related: [String]
    var priority: String

    enum CodingKeys: String, CodingKey {
        case name
        case humanIdea = "human_idea"
        case description
        case difficulty
        case related
        case priority
    }

    static let `default` = Idea(
        name: "new_idea",
        humanIdea: "",
        description: "",
        difficulty: "S",
        related: [],
        priority: "none"
    )
}

enum IdeaTextField {
    case name
    case humanIdea
    case description
    case difficulty
}

enum PriorityOption: String, CaseIterable, Codable {
    case high
    case medium
    case low
    case none

    static func sortRank(for rawValue: String) -> Int {
        switch rawValue {
        case PriorityOption.high.rawValue:
            return 0
        case PriorityOption.medium.rawValue:
            return 1
        case PriorityOption.low.rawValue:
            return 2
        default:
            return 3
        }
    }
}

enum SizeOption: String, CaseIterable, Codable {
    case small = "S"
    case medium = "M"
    case large = "L"
}
