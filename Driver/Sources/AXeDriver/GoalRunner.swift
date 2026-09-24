import Foundation
import AXeSimulator
import TypeSafe

@MainActor
enum GoalRunner {
    static func run(_ request: InteractionRequest) async throws -> GoalResult {
        DriverLog.reset()
        let started = ContinuousClock.now
        func elapsed() -> Int {
            let duration = started.duration(to: .now).components
            return Int(duration.seconds) * 1_000 + Int(duration.attoseconds / 1_000_000_000_000_000)
        }

        var steps: [GoalStep] = []
        var rows: [Row] = []
        var inputTokens = 0
        var outputTokens = 0
        var completionRejections = 0
        var pendingTransition = false
        var previousActionableCount = 0
        var nonActionRetries = 0
        var reusePostActionRows = false
        func finish(_ status: String, _ message: String, verification: GoalVerification? = nil) -> GoalResult {
            DriverLog.write("Result: \(status) — \(message) [elapsed \(elapsed()) ms, steps \(steps.count), AX \(DriverLog.screenReads) reads / \(DriverLog.screenMilliseconds) ms, Jev decisions \(DriverLog.jevMilliseconds) ms, input \(DriverLog.inputMilliseconds) ms]")
            return GoalResult(
                status: status,
                message: message,
                steps: steps,
                finalRows: rows,
                verification: verification,
                elapsedMilliseconds: elapsed(),
                inputTokens: inputTokens,
                outputTokens: outputTokens
            )
        }

        guard let maxSteps = request.maxSteps, (1...32).contains(maxSteps) else {
            return finish("invalid_request", "maxSteps must be between 1 and 32")
        }
        guard request.observeOnly != true else {
            return finish("invalid_request", "maxSteps and observeOnly cannot be combined")
        }
        guard !request.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return finish("invalid_request", "instruction is required")
        }
        let confidenceThreshold = request.minimumConfidence ?? 0.5
        guard (0...1).contains(confidenceThreshold) else {
            return finish("invalid_request", "minimumConfidence must be between 0 and 1")
        }
        let probabilityThreshold = request.minimumProbability ?? 0
        guard (0...1).contains(probabilityThreshold) else {
            return finish("invalid_request", "minimumProbability must be between 0 and 1")
        }
        if let text = request.text {
            guard !text.isEmpty else { return finish("invalid_request", "text must not be empty") }
            do { try SimulatorSession.validateText(text) }
            catch { return finish("invalid_request", error.localizedDescription) }
        }
        if let bundleID = request.appBundleID, bundleID.isEmpty {
            return finish("invalid_request", "appBundleID must not be empty")
        }

        let session = try SimulatorSession(udid: request.simulatorUDID)
        let client = try TypeSafeClient(model: request.model, retry: RetryPolicy(maxRetries: 0))
        var openedApp = false
        DriverLog.write(
            "Goal started: \(request.instruction) [max \(maxSteps) steps, confidence ≥\(DriverLog.probability(confidenceThreshold)), probability ≥\(DriverLog.probability(probabilityThreshold))]"
        )

        for stepNumber in 1...(maxSteps + 2) {
            if stepNumber > maxSteps + nonActionRetries { break }
            let stepStarted = elapsed()
            let readsBeforeStep = DriverLog.screenReads
            let readMillisecondsBeforeStep = DriverLog.screenMilliseconds
            if stepNumber == 1, let bundleID = request.appBundleID {
                do {
                    try await session.openApp(bundleID: bundleID)
                } catch {
                    return finish("launch_failed", "Could not open \(request.appName ?? bundleID): \(error)")
                }
                openedApp = true
                pendingTransition = true
                steps.append(GoalStep(
                    action: GoalAction.openApp.rawValue, target: bundleID,
                    actionProbability: 1, actionConfidence: 1,
                    targetProbability: nil, targetConfidence: nil,
                    requestID: nil, inputTokens: nil, outputTokens: nil, outcome: "executed"
                ))
                DriverLog.write("1. OPEN APP → \(request.appName ?? bundleID) (\(bundleID)) [step \(elapsed() - stepStarted) ms]")
                continue
            }
            if !reusePostActionRows || rows.isEmpty {
                do { rows = try await observeActionable(session: session, udid: request.simulatorUDID) }
                catch {
                    if request.appBundleID == nil || openedApp { throw error }
                    rows = []
                }
            }
            reusePostActionRows = false
            if rows.isEmpty && pendingTransition {
                DriverLog.write("Waiting: no actionable controls visible after the previous input")
                guard let refreshed = try await waitForUIChange(from: rows, timeout: .seconds(8), observe: {
                    try await observeRows(session: session, udid: request.simulatorUDID)
                }) else {
                    return finish("launch_timeout", "No actionable UI appeared within eight seconds after input")
                }
                rows = refreshed
            }
            let actionableCount = rows.filter { !$0.actions.isEmpty }.count
            let afterLaunch = steps.last?.action == GoalAction.openApp.rawValue
            let sparseTransition = previousActionableCount > 0
                && actionableCount * 2 < previousActionableCount
            if pendingTransition && (afterLaunch || sparseTransition) {
                DriverLog.detail("Settling transition: \(previousActionableCount) → \(actionableCount) actionable rows")
                guard let settled = try await stableRows(startingWith: rows, timeout: .seconds(5), observe: {
                    try await observeRows(session: session, udid: request.simulatorUDID)
                }) else {
                    return finish("ui_unstable", "Accessibility UI did not settle after input")
                }
                rows = settled
            }
            DriverLog.detail("step=\(stepNumber) observed candidates=\(rows.count)")

            let decision: GoalDecision
            do {
                guard let planned = try await planDecision(
                    request: request, rows: rows, steps: steps, stepNumber: stepNumber, client: client
                ) else {
                    return finish("invalid_model_answer", "Jev returned an unavailable action")
                }
                decision = planned
            } catch GoalPlanningError.candidateOverflow(let count) {
                return finish("candidate_overflow", "\(count) action and target choices exceed Jev's 255 option limit")
            }
            let indexed = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ("e\($0.offset)", $0.element) })
            let action = decision.action
            let actionProbability = decision.actionProbability
            let targetID = decision.targetID
            let targetProbability = decision.targetProbability
            let selectedTarget = decision.selectedTarget
            let response = decision.response
            let jevMilliseconds = decision.jevMilliseconds
            inputTokens += response?.usage.inputTokens ?? 0
            outputTokens += response?.usage.outputTokens ?? 0

            func record(_ outcome: String, target: Row? = nil) {
                steps.append(GoalStep(
                    action: action.rawValue,
                    target: target?.id,
                    actionProbability: actionProbability,
                    actionConfidence: decision.actionConfidence,
                    targetProbability: targetProbability,
                    targetConfidence: decision.targetConfidence,
                    requestID: response?.requestID,
                    inputTokens: response?.usage.inputTokens,
                    outputTokens: response?.usage.outputTokens,
                    outcome: outcome
                ))
                let label = target?.label ?? selectedTarget?.label ?? target?.stableID ?? targetID ?? "none"
                let operation = action == .type ? "TYPE" : action.rawValue.uppercased()
                DriverLog.write("\(stepNumber). \(operation) → \(label) [\(outcome), p=\(DriverLog.probability(targetProbability ?? actionProbability)), Jev \(jevMilliseconds) ms, AX \(DriverLog.screenReads - readsBeforeStep) reads / \(DriverLog.screenMilliseconds - readMillisecondsBeforeStep) ms, step \(elapsed() - stepStarted) ms]")
            }

            if action == .goalComplete {
                let requirementsSatisfied = (request.requirements ?? []).indices.allSatisfy {
                    (response?.nouls["requirement_\($0)"]?.noul ?? 0) >= 0.8
                }
                if !requirementsSatisfied, completionRejections < 2 {
                    completionRejections += 1
                    record("completion_rejected")
                    continue
                }
                record("declared_done")
                rows = try await observeRows(session: session, udid: request.simulatorUDID)
                let verified = try await verify(request: request, rows: rows, client: client)
                inputTokens += verified.inputTokens
                outputTokens += verified.outputTokens
                guard verified.result.isConfigured else {
                    return finish(
                        "done_unverified",
                        "Jev declared the goal complete, but no independent requirements or expectations were supplied",
                        verification: verified.result
                    )
                }
                return finish(
                    verified.result.passed ? "completed" : "done_unverified",
                    verified.result.passed
                        ? "Fresh UI evidence satisfied every configured requirement and expectation"
                        : "Jev declared completion, but fresh verification failed",
                    verification: verified.result
                )
            }
            if action == .noMatch {
                if pendingTransition && nonActionRetries < 2,
                   let refreshed = try await waitForUIChange(from: rows, timeout: .seconds(8), observe: {
                       try await observeRows(session: session, udid: request.simulatorUDID)
                   }) {
                    rows = refreshed
                    pendingTransition = false
                    nonActionRetries += 1
                    record("transient_no_match")
                    DriverLog.write("Retrying decision: the screen changed after Jev returned no match; no input was repeated")
                    continue
                }
                record("no_match")
                return finish("no_match", "Jev found no safe next action")
            }
            guard decision.actionConfidence >= confidenceThreshold
                    && actionProbability >= probabilityThreshold else {
                record("uncertain")
                return finish("uncertain", "Action confidence or selected probability is below its configured threshold")
            }

            var chosen: Row?
            if let requiredAction = action.rowAction {
                guard let targetID, let row = indexed[targetID],
                      row.actions.contains(requiredAction) else {
                    record("invalid_target")
                    return finish("invalid_target", "Jev selected a target incompatible with \(action.rawValue)")
                }
                guard decision.targetConfidence != nil
                        && targetIsAccepted(
                            selectedProbability: targetProbability ?? 0,
                            minimumProbability: probabilityThreshold
                        ) else {
                    record("uncertain", target: row)
                    return finish("uncertain", "Target confidence or selected probability is below its configured threshold")
                }
                chosen = row
            } else {
                chosen = nil
            }

            if let selected = chosen {
                let pointMatched = await freshPointMatchesTarget(selected, session: session)
                let settled: (Row, [Row])?
                if pointMatched {
                    settled = (selected, rows)
                } else {
                    settled = try await stableTarget(for: selected, timeout: .seconds(3), observe: {
                        try await observeRows(session: session, udid: request.simulatorUDID)
                    })
                }
                guard let (target, fresh) = settled else {
                    let fresh = try await observeRows(session: session, udid: request.simulatorUDID)
                    rows = fresh
                    if nonActionRetries < 2 {
                        nonActionRetries += 1
                        record("replan_stale", target: selected)
                        DriverLog.write("Retrying decision: target moved or disappeared before input")
                        continue
                    }
                    record("stale", target: selected)
                    return finish("stale", "Selected target did not stabilize before execution")
                }
                if action == .type, let text = request.text {
                    if target.value == text {
                        rows = fresh
                        record("already_satisfied", target: target)
                        return finish("already_satisfied", "Target already contains exact_text")
                    }
                    if let value = target.value, !value.isEmpty, value != target.label {
                        rows = fresh
                        record("nonempty_field", target: target)
                        return finish("nonempty_field", "Target contains other text")
                    }
                }
                rows = fresh
                chosen = target
            }
            let inputStarted = elapsed()
            if action.rowAction != nil && chosen == nil {
                return finish("invalid_target", "\(action.rawValue) requires a target")
            }
            if action == .type && request.text == nil {
                return finish("invalid_target", "Type requires a target and exact text")
            }
            if action == .openApp && request.appBundleID == nil {
                return finish("invalid_request", "appBundleID is required")
            }
            do {
                try await execute(
                    action, target: chosen, text: request.text,
                    appBundleID: request.appBundleID, session: session
                )
                if action == .openApp { openedApp = true }
            } catch {
                record("uncertain_write", target: chosen)
                return finish("uncertain_write", "Input may have been sent: \(error). Inspect fresh UI before retrying.")
            }
            DriverLog.inputMilliseconds += elapsed() - inputStarted

            let beforeAction = rows
            previousActionableCount = beforeAction.filter { !$0.actions.isEmpty }.count
            do {
                rows = try await observeUntilChanged(session: session, udid: request.simulatorUDID, from: beforeAction)
            } catch {
                record("executed_unverified", target: chosen)
                return finish("executed_unverified", "Input was sent but follow-up observation failed: \(error)")
            }
            reusePostActionRows = true
            let changed = semanticSignature(rows) != semanticSignature(beforeAction)
            record(changed ? "executed" : "unchanged", target: chosen)
            if !changed {
                return finish("unchanged", "UI did not visibly change; stopped to avoid repeating input")
            }
            pendingTransition = action == .openApp || action == .tap
        }
        return finish("step_limit", "Reached maxSteps before verified completion")
    }
}
