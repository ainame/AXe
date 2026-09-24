import Foundation
import Testing
@testable import AXeDriver

@Test("A full-screen modal hides the underlying UI from action candidates")
func modalTakesPrecedence() throws {
    let data = Data(#"""
    {"role":"AXApplication","frame":{"x":0,"y":0,"width":400,"height":800},"children":[
      {"role":"AXGroup","frame":{"x":0,"y":0,"width":400,"height":800},"children":[
        {"role":"AXGroup","frame":{"x":0,"y":0,"width":400,"height":800},"children":[
          {"role":"AXButton","AXLabel":"Delete","frame":{"x":10,"y":20,"width":90,"height":40}}]},
        {"role":"AXGroup","frame":{"x":0,"y":0,"width":400,"height":800},"children":[
          {"role":"AXGroup","frame":{"x":0,"y":60,"width":400,"height":740},"children":[
            {"role":"AXButton","AXLabel":"Continue","frame":{"x":10,"y":700,"width":90,"height":40}}]}]}
      ]}
    ]}
    """#.utf8)
    let rows = try Observation.rows(from: data)
    #expect(rows.map(\.label) == ["Continue"])
}

@Test("A full-screen toolbar container does not hide the main view")
func toolbarDoesNotOcclude() throws {
    let data = Data(#"""
    {"role":"AXApplication","frame":{"x":0,"y":0,"width":400,"height":800},"children":[
      {"role":"AXGroup","frame":{"x":0,"y":0,"width":400,"height":800},"children":[
        {"role":"AXGroup","frame":{"x":0,"y":0,"width":400,"height":800},"children":[
          {"role":"AXButton","AXLabel":"16 August","frame":{"x":10,"y":300,"width":90,"height":40}}]},
        {"role":"AXGroup","AXLabel":"Toolbar","frame":{"x":0,"y":0,"width":400,"height":800},"children":[
          {"role":"AXButton","AXLabel":"Today","frame":{"x":10,"y":740,"width":90,"height":40}}]}
      ]}
    ]}
    """#.utf8)
    let rows = try Observation.rows(from: data)
    #expect(rows.map(\.label) == ["16 August", "Today"])
}

@Test("Offscreen and disabled elements are excluded")
func excludesUnavailableRows() throws {
    let data = Data(#"""
    {"role":"AXApplication","frame":{"x":0,"y":0,"width":400,"height":800},"children":[
      {"role":"AXButton","AXLabel":"Visible","frame":{"x":10,"y":20,"width":90,"height":40}},
      {"role":"AXButton","AXLabel":"Disabled","enabled":false,"frame":{"x":10,"y":70,"width":90,"height":40}},
      {"role":"AXButton","AXLabel":"Offscreen","frame":{"x":10,"y":810,"width":90,"height":40}}
    ]}
    """#.utf8)
    let rows = try Observation.rows(from: data)
    #expect(rows.map(\.label) == ["Visible"])
    let verificationRows = try Observation.rows(from: data, includeOffscreen: true)
    #expect(verificationRows.map(\.label) == ["Visible", "Offscreen"])
}

@Test("Numeric accessibility values decode without losing the hierarchy")
func numericValues() throws {
    let data = Data(#"""
    [{"role":"AXApplication","frame":{"x":0,"y":0,"width":400,"height":800},"children":[
      {"role":"AXRadioButton","AXLabel":"Event","AXValue":1,"frame":{"x":10,"y":20,"width":90,"height":40}},
      {"role":"AXButton","AXLabel":"Done","frame":{"x":300,"y":20,"width":90,"height":40}}
    ]}]
    """#.utf8)
    let rows = try Observation.rows(from: data)
    #expect(rows.map(\.label) == ["Event", "Done"])
    #expect(rows.first?.value == "1")
}

@Test("Visible headings inform planning but cannot become input targets")
@MainActor
func headingsAreContextOnly() throws {
    let data = Data(#"""
    {"role":"AXApplication","frame":{"x":0,"y":0,"width":400,"height":800},"children":[
      {"role":"AXHeading","AXLabel":"Current location: North","frame":{"x":10,"y":20,"width":200,"height":40}},
      {"role":"AXButton","AXLabel":"South","frame":{"x":10,"y":70,"width":90,"height":40}}
    ]}
    """#.utf8)
    let rows = try Observation.rows(from: data)
    #expect(rows.map(\.label) == ["South", "Current location: North"])
    #expect(rows.last?.actions.isEmpty == true)
    let request = InteractionRequest(
        simulatorUDID: "fixture", instruction: "Navigate south", text: nil,
        observeOnly: nil, minimumProbability: nil, minimumConfidence: nil, maxSteps: 1,
        appBundleID: nil, appName: nil, requirements: nil,
        expectLabels: nil, expectLabelPrefixes: nil, expectIDs: nil, expectValues: nil, model: nil
    )
    let choices = GoalRunner.candidates(request: request, rows: rows, steps: [])
    #expect(choices["tap:e0"]?.action == .tap)
    #expect(choices["tap:e1"] == nil)
}

@Test("Verification requires configured evidence and every check to pass")
func verificationSemantics() {
    let unconfigured = GoalVerification(
        requirements: [],
        expectedLabels: [],
        expectedLabelPrefixes: [],
        expectedIDs: [],
        expectedValues: [],
        missingLabels: [],
        missingLabelPrefixes: [],
        missingIDs: [],
        missingValues: []
    )
    #expect(!unconfigured.isConfigured)

    let verified = GoalVerification(
        requirements: [RequirementResult(requirement: "Saved event is visible", probability: 0.91)],
        expectedLabels: ["Cameron Birthday"],
        expectedLabelPrefixes: ["Cameron Birthday"],
        expectedIDs: [],
        expectedValues: [],
        missingLabels: [],
        missingLabelPrefixes: [],
        missingIDs: [],
        missingValues: []
    )
    #expect(verified.isConfigured)
    #expect(verified.passed)

    let failed = GoalVerification(
        requirements: [RequirementResult(requirement: "Saved event is visible", probability: 0.79)],
        expectedLabels: ["Cameron Birthday"],
        expectedLabelPrefixes: ["Cameron Birthday"],
        expectedIDs: [],
        expectedValues: [],
        missingLabels: ["Cameron Birthday"],
        missingLabelPrefixes: ["Cameron Birthday"],
        missingIDs: [],
        missingValues: []
    )
    #expect(!failed.passed)
}

@Test("Completion label prefixes preserve the caller's exact case")
@MainActor
func labelPrefixIsCaseSensitive() {
    let row = Row(
        id: "event", role: "AXButton",
        label: "Axe Birthday, from 02:00 to 03:00", value: nil,
        stableID: nil, parent: nil,
        frame: Rectangle(x: 0, y: 0, width: 100, height: 40),
        actions: ["tap"]
    )
    #expect(GoalRunner.missingLabelPrefixes(["AXe Birthday"], in: [row]) == ["AXe Birthday"])
    #expect(GoalRunner.missingLabelPrefixes(["Axe Birthday"], in: [row]).isEmpty)
}

@Test("A transient empty observation is not accepted as a UI transition")
@MainActor
func emptyTransitionIsRejected() throws {
    let data = Data(#"""
    {"role":"AXApplication","frame":{"x":0,"y":0,"width":400,"height":800},"children":[
      {"role":"AXButton","AXLabel":"Calendar","frame":{"x":10,"y":20,"width":90,"height":40}}
    ]}
    """#.utf8)
    let rows = try Observation.rows(from: data)
    #expect(!GoalRunner.acceptsTransition(from: rows, to: []))
}

@Test("Launch recovery waits for actionable UI instead of judging an empty snapshot")
@MainActor
func launchRecoveryWaitsForUI() async throws {
    let ready = Row(id: "ready", role: "AXButton", label: "Calendar", value: nil,
                    stableID: nil, parent: nil,
                    frame: Rectangle(x: 0, y: 0, width: 10, height: 10), actions: ["tap"])
    var snapshots: [[Row]] = [[], [], [ready]]
    let result = try await GoalRunner.waitForUIChange(from: [], timeout: .seconds(1)) {
        snapshots.removeFirst()
    }
    #expect(result?.first?.label == "Calendar")
}

@Test("Animated target must settle and remain unambiguous before input")
@MainActor
func targetStability() async throws {
    let initial = Row(id: "old", role: "AXButton", label: "2026", value: nil,
                      stableID: "BackButton", parent: "Calendar",
                      frame: Rectangle(x: 10, y: 20, width: 90, height: 40), actions: ["tap"])
    let moving = Row(id: "new", role: initial.role, label: initial.label, value: nil,
                     stableID: initial.stableID, parent: initial.parent,
                     frame: Rectangle(x: 20, y: 20, width: 90, height: 40), actions: initial.actions)
    var snapshots = [[moving], [moving]]
    let result = try await GoalRunner.stableTarget(for: initial, timeout: .seconds(1)) {
        snapshots.removeFirst()
    }
    #expect(result?.0.id == "new")
    let ambiguous = try await GoalRunner.stableTarget(for: initial, timeout: .zero) {
        [moving, moving]
    }
    #expect(ambiguous?.0.id == nil)
    let replacement = Row(id: "replacement", role: "AXButton", label: "New screen", value: nil,
                          stableID: nil, parent: nil, frame: initial.frame, actions: ["tap"])
    var reads = 0
    let disappeared = try await GoalRunner.stableTarget(for: initial, timeout: .seconds(3)) {
        reads += 1
        return [replacement]
    }
    #expect(disappeared == nil)
    #expect(reads == 1)
}

@Test("Point validation accepts only the same visible target and frame")
@MainActor
func pointTargetValidation() {
    let selected = Row(id: "0.1", role: "AXButton", label: "Add", value: nil,
                       stableID: "add-plus-button", parent: "Calendar",
                       frame: Rectangle(x: 300, y: 20, width: 50, height: 40), actions: ["tap"])
    let matching = Data(#"{"role":"AXButton","AXLabel":"Add","AXUniqueId":"add-plus-button","enabled":true,"frame":{"x":300,"y":20,"width":50,"height":40}}"#.utf8)
    let moved = Data(#"{"role":"AXButton","AXLabel":"Add","AXUniqueId":"add-plus-button","enabled":true,"frame":{"x":200,"y":20,"width":50,"height":40}}"#.utf8)
    let disabled = Data(#"{"role":"AXButton","AXLabel":"Add","AXUniqueId":"add-plus-button","enabled":false,"frame":{"x":300,"y":20,"width":50,"height":40}}"#.utf8)
    #expect(GoalRunner.pointMatchesTarget(matching, selected: selected))
    #expect(!GoalRunner.pointMatchesTarget(moved, selected: selected))
    #expect(!GoalRunner.pointMatchesTarget(disabled, selected: selected))
}

@Test("Planning waits for the same nonempty accessibility state twice")
@MainActor
func stablePlanningRows() async throws {
    let loading = Row(id: "loading", role: "AXButton", label: "2026", value: nil,
                      stableID: "BackButton", parent: nil,
                      frame: Rectangle(x: 0, y: 0, width: 10, height: 10), actions: ["tap"])
    let august = Row(id: "august", role: "AXButton", label: "August 2026", value: nil,
                     stableID: nil, parent: nil, frame: loading.frame, actions: ["tap"])
    var snapshots = [[loading, august], [loading, august]]
    let result = try await GoalRunner.stableRows(startingWith: [loading], timeout: .seconds(1)) {
        snapshots.removeFirst()
    }
    #expect(result?.map(\.label) == ["2026", "August 2026"])
}

@Test("Target selection uses selected probability rather than distribution confidence")
@MainActor
func targetSelectionThreshold() {
    #expect(GoalRunner.targetIsAccepted(selectedProbability: 0.54, minimumProbability: 0))
    #expect(!GoalRunner.targetIsAccepted(selectedProbability: 0.49, minimumProbability: 0))
    #expect(!GoalRunner.targetIsAccepted(selectedProbability: 0.79, minimumProbability: 0.8))
}

@Test("Generic planning offers every compatible target without app-specific filtering")
@MainActor
func genericTargetsRemainAvailable() throws {
    let data = Data(#"""
    {"role":"AXApplication","frame":{"x":0,"y":0,"width":400,"height":800},"children":[
      {"role":"AXButton","AXLabel":"Previous","frame":{"x":10,"y":20,"width":90,"height":40}},
      {"role":"AXButton","AXLabel":"Create","frame":{"x":300,"y":20,"width":90,"height":40}},
      {"role":"AXTextField","AXLabel":"Name","AXValue":"","frame":{"x":10,"y":70,"width":180,"height":40}}
    ]}
    """#.utf8)
    let rows = try Observation.rows(from: data)
    let request = InteractionRequest(
        simulatorUDID: "fixture", instruction: "Create a named item", text: "Example",
        observeOnly: nil, minimumProbability: nil, minimumConfidence: nil, maxSteps: 4,
        appBundleID: nil, appName: nil, requirements: ["Saved item is visible"],
        expectLabels: nil, expectLabelPrefixes: nil, expectIDs: nil, expectValues: nil, model: nil
    )
    let choices = GoalRunner.candidates(request: request, rows: rows, steps: [])
    #expect(choices["tap:e0"]?.action == .tap)
    #expect(choices["tap:e1"]?.action == .tap)
    #expect(choices["type:e2"]?.action == .type)
    #expect(choices["goal_complete"]?.action == .goalComplete)
    #expect(choices["no_match"]?.action == .noMatch)
}
