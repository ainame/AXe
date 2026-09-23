import Foundation
import AXeSimulator

@MainActor
extension GoalRunner {
    static func execute(
        _ action: GoalAction,
        target: Row?,
        text: String?,
        appBundleID: String?,
        session: SimulatorSession
    ) async throws {
        switch action {
        case .tap:
            guard let target else { throw GoalExecutionError.missingTarget }
            if ["CheckBox", "Switch", "Toggle"].contains(where: target.role.contains) {
                try await session.tapPhysical(x: target.frame.centerX, y: target.frame.centerY)
            } else {
                try await session.tap(x: target.frame.centerX, y: target.frame.centerY)
            }
        case .type:
            guard let target, let text else { throw GoalExecutionError.missingTextOrTarget }
            try await session.tap(x: target.frame.centerX, y: target.frame.centerY)
            try await session.type(text)
        case .scrollUp, .scrollDown:
            guard let target else { throw GoalExecutionError.missingTarget }
            let frame = CGRect(
                x: target.frame.x, y: target.frame.y,
                width: target.frame.width, height: target.frame.height
            )
            try await session.scroll(in: frame, direction: action == .scrollUp ? .up : .down)
        case .openApp:
            guard let appBundleID else { throw GoalExecutionError.missingAppBundleID }
            try await session.openApp(bundleID: appBundleID)
        case .goalComplete, .noMatch:
            break
        }
    }
}

enum GoalExecutionError: Error {
    case missingTarget
    case missingTextOrTarget
    case missingAppBundleID
}
