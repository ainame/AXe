import Foundation

enum GoalAction: String {
    case tap
    case type
    case scrollUp = "scroll_up"
    case scrollDown = "scroll_down"
    case openApp = "open_app"
    case goalComplete = "goal_complete"
    case noMatch = "no_match"

    var rowAction: String? {
        switch self {
        case .tap: "tap"
        case .type: "type"
        case .scrollUp, .scrollDown: "scroll"
        case .openApp, .goalComplete, .noMatch: nil
        }
    }

    var targetQuestion: String? {
        switch self {
        case .tap: "tap_target"
        case .type: "type_target"
        case .scrollUp, .scrollDown: "scroll_target"
        case .openApp, .goalComplete, .noMatch: nil
        }
    }
}

struct GoalStep: Encodable {
    let action: String
    let target: String?
    let actionProbability: Double
    let actionConfidence: Double
    let targetProbability: Double?
    let targetConfidence: Double?
    let requestID: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let outcome: String
}

struct RequirementResult: Encodable {
    let requirement: String
    let probability: Double
}

struct GoalVerification: Encodable {
    let requirements: [RequirementResult]
    let expectedLabels: [String]
    let expectedIDs: [String]
    let expectedValues: [String]
    let missingLabels: [String]
    let missingIDs: [String]
    let missingValues: [String]

    var isConfigured: Bool {
        !requirements.isEmpty || !expectedLabels.isEmpty || !expectedIDs.isEmpty || !expectedValues.isEmpty
    }

    var passed: Bool {
        requirements.allSatisfy { $0.probability >= 0.8 }
            && missingLabels.isEmpty && missingIDs.isEmpty && missingValues.isEmpty
    }
}

struct GoalResult: Encodable {
    let status: String
    let message: String
    let steps: [GoalStep]
    let finalRows: [Row]
    let verification: GoalVerification?
    let elapsedMilliseconds: Int
    let inputTokens: Int
    let outputTokens: Int
}
