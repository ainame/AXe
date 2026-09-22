import Foundation
import ArgumentParser

private struct ErrorResult: Encodable {
    let status = "error"
    let message: String
}
@main
struct DriverMain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "axe-driver",
        abstract: "Run a bounded Jev-assisted iOS Simulator goal."
    )

    @Option(name: .customLong("udid"), help: "Simulator UDID.")
    var simulatorUDID: String?

    @Argument(help: "Natural-language goal. May be used instead of --goal.")
    var positionalGoal: String?

    @Option(help: "Natural-language goal.")
    var goal: String?

    @Option(help: "Exact text AXe may type.")
    var text: String?

    @Option(name: .customLong("max-steps"), help: "Maximum bounded goal steps.")
    var maxSteps: Int?

    @Option(help: "Visible completion requirement. Repeat for multiple requirements.")
    var requirement: [String] = []

    @Option(name: .customLong("expect-label"), help: "Exact label expected after completion. Repeatable.")
    var expectLabels: [String] = []

    @Option(name: .customLong("expect-id"), help: "Exact accessibility ID expected after completion. Repeatable.")
    var expectIDs: [String] = []

    @Option(name: .customLong("expect-value"), help: "Exact value expected after completion. Repeatable.")
    var expectValues: [String] = []

    @Option(name: .customLong("minimum-confidence"), help: "Minimum Jev Choice confidence from 0 to 1.")
    var minimumConfidence: Double?

    @Option(name: .customLong("minimum-probability"), help: "Minimum selected probability from 0 to 1.")
    var minimumProbability: Double?

    @Option(name: .customLong("app-bundle-id"), help: "Bundle ID AXe may launch.")
    var appBundleID: String?

    @Option(name: .customLong("app-name"), help: "Human-readable app name supplied to Jev.")
    var appName: String?

    @Option(help: "Pinned TypeSafe model. Defaults to jev-latest.")
    var model: String?

    @Option(help: "Write the full JSON result to this path.")
    var trace: String?

    @Flag(help: "Print the full JSON result on standard output instead of a brief summary.")
    var json = false

    @Flag(name: .customLong("observe-only"), help: "Observe actionable UI without calling Jev.")
    var observeOnly = false

    mutating func run() async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let usesArguments = simulatorUDID != nil || goal != nil || positionalGoal != nil || maxSteps != nil || observeOnly
        do {
            let request: InteractionRequest
            if usesArguments {
                guard let simulatorUDID, let instruction = positionalGoal ?? goal else {
                    throw ValidationError("--udid and a positional goal (or --goal) are required")
                }
                let inferred = await GoalArguments.infer(from: instruction)
                request = InteractionRequest(
                    simulatorUDID: simulatorUDID,
                    instruction: instruction,
                    text: text ?? inferred.text,
                    observeOnly: observeOnly,
                    minimumProbability: minimumProbability,
                    minimumConfidence: minimumConfidence,
                    maxSteps: maxSteps ?? (observeOnly ? nil : 8),
                    appBundleID: appBundleID ?? inferred.appBundleID,
                    appName: appName ?? inferred.appName,
                    requirements: requirement.isEmpty ? inferred.requirements : requirement,
                    expectLabels: expectLabels.isEmpty ? nil : expectLabels,
                    expectIDs: expectIDs.isEmpty ? nil : expectIDs,
                    expectValues: expectValues.isEmpty ? nil : expectValues,
                    model: model
                )
            } else {
                let input = FileHandle.standardInput.readDataToEndOfFile()
                request = try JSONDecoder().decode(InteractionRequest.self, from: input)
            }
            if request.maxSteps != nil {
                let result = try await GoalRunner.run(request)
                let output = try encoder.encode(result) + Data([10])
                if let trace { try output.write(to: URL(fileURLWithPath: trace), options: .atomic) }
                if usesArguments && !json {
                    let verdict = result.status == "completed" ? "Completed" : "Stopped: \(result.status)"
                    let summary = "\(verdict) — \(result.message)\nSteps: \(result.steps.count), elapsed: \(String(format: "%.1f", Double(result.elapsedMilliseconds) / 1_000)) s\n"
                    FileHandle.standardOutput.write(Data(summary.utf8))
                } else {
                    FileHandle.standardOutput.write(output)
                }
            } else {
                let result = try await Driver.run(request)
                let output = try encoder.encode(result) + Data([10])
                if let trace { try output.write(to: URL(fileURLWithPath: trace), options: .atomic) }
                if usesArguments && !json {
                    let summary = "\(result.status.capitalized) — \(result.message)\nVisible controls: \(result.before.count), elapsed: \(String(format: "%.1f", Double(result.elapsedMilliseconds) / 1_000)) s\n"
                    FileHandle.standardOutput.write(Data(summary.utf8))
                } else {
                    FileHandle.standardOutput.write(output)
                }
            }
        } catch {
            let payload = ErrorResult(message: String(describing: error))
            let data = (try? encoder.encode(payload)) ?? Data(#"{"status":"error","message":"Encoding failed"}"#.utf8)
            if let trace { try? (data + Data([10])).write(to: URL(fileURLWithPath: trace), options: .atomic) }
            if usesArguments && !json {
                let stamp = Date.now.ISO8601Format()
                FileHandle.standardError.write(Data("[\(stamp)] Error — \(error)\n".utf8))
            } else {
                FileHandle.standardOutput.write(data + Data([10]))
            }
            if usesArguments, error is ValidationError { throw error }
            Foundation.exit(1)
        }
    }
}

@MainActor
enum GoalArguments {
    static func infer(from instruction: String) -> (text: String?, requirements: [String]?, appBundleID: String?, appName: String?) {
        let opensCalendar = instruction.range(of: #"(?i)\bopen\s+(?:the\s+)?calendar(?:\s+app)?\b"#, options: .regularExpression) != nil
        let bundleID = opensCalendar ? "com.apple.mobilecal" : nil
        let appName = opensCalendar ? "Calendar" : nil
        let pattern = #"(?i)\btitled\s+['\"]([^'\"]+)['\"]"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: instruction, range: NSRange(instruction.startIndex..., in: instruction)),
              let range = Range(match.range(at: 1), in: instruction) else {
            return (nil, nil, bundleID, appName)
        }
        let title = String(instruction[range])
        guard !title.isEmpty else { return (nil, nil, bundleID, appName) }
        guard let date = GoalRunner.requestedDate(in: instruction) else { return (title, nil, bundleID, appName) }
        return (title, ["A saved event titled \(title) is visible on \(date.month) \(date.day) \(date.year)"], bundleID, appName)
    }
}
