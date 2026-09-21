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

    @Flag(name: .customLong("observe-only"), help: "Observe actionable UI without calling Jev.")
    var observeOnly = false

    mutating func run() async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let usesArguments = simulatorUDID != nil || goal != nil || maxSteps != nil || observeOnly
        do {
            let request: InteractionRequest
            if usesArguments {
                guard let simulatorUDID, let goal else {
                    throw ValidationError("--udid and --goal are required when using command-line options")
                }
                request = InteractionRequest(
                    simulatorUDID: simulatorUDID,
                    instruction: goal,
                    text: text,
                    observeOnly: observeOnly,
                    minimumProbability: minimumProbability,
                    minimumConfidence: minimumConfidence,
                    maxSteps: maxSteps,
                    appBundleID: appBundleID,
                    appName: appName,
                    requirements: requirement.isEmpty ? nil : requirement,
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
                FileHandle.standardOutput.write(try encoder.encode(result) + Data([10]))
            } else {
                let result = try await Driver.run(request)
                FileHandle.standardOutput.write(try encoder.encode(result) + Data([10]))
            }
        } catch {
            let payload = ErrorResult(message: String(describing: error))
            let data = (try? encoder.encode(payload)) ?? Data(#"{"status":"error","message":"Encoding failed"}"#.utf8)
            FileHandle.standardOutput.write(data + Data([10]))
            if usesArguments, error is ValidationError { throw error }
            Foundation.exit(1)
        }
    }
}
