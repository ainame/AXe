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

@Test("Verification requires configured evidence and every check to pass")
func verificationSemantics() {
    let unconfigured = GoalVerification(
        requirements: [],
        expectedLabels: [],
        expectedIDs: [],
        expectedValues: [],
        missingLabels: [],
        missingIDs: [],
        missingValues: []
    )
    #expect(!unconfigured.isConfigured)

    let verified = GoalVerification(
        requirements: [RequirementResult(requirement: "Saved event is visible", probability: 0.91)],
        expectedLabels: ["Cameron Birthday"],
        expectedIDs: [],
        expectedValues: [],
        missingLabels: [],
        missingIDs: [],
        missingValues: []
    )
    #expect(verified.isConfigured)
    #expect(verified.passed)

    let failed = GoalVerification(
        requirements: [RequirementResult(requirement: "Saved event is visible", probability: 0.79)],
        expectedLabels: ["Cameron Birthday"],
        expectedIDs: [],
        expectedValues: [],
        missingLabels: ["Cameron Birthday"],
        missingIDs: [],
        missingValues: []
    )
    #expect(!failed.passed)
}

@Test("An unsaved editor cannot be mistaken for goal completion")
@MainActor
func unsavedEditorBlocksCompletion() throws {
    let data = Data(#"""
    {"role":"AXApplication","frame":{"x":0,"y":0,"width":400,"height":800},"children":[
      {"role":"AXStaticText","AXLabel":"New Event","frame":{"x":10,"y":20,"width":90,"height":40}},
      {"role":"AXButton","AXLabel":"Cancel","frame":{"x":10,"y":70,"width":90,"height":40}},
      {"role":"AXButton","AXLabel":"Done","frame":{"x":300,"y":70,"width":90,"height":40}}
    ]}
    """#.utf8)
    let rows = try Observation.rows(from: data)
    #expect(!GoalRunner.completionIsAvailable(rows: rows))
    #expect(GoalAction.goalComplete.rawValue == "goal_complete")
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

@Test("Target selection uses selected probability rather than distribution confidence")
@MainActor
func targetSelectionThreshold() {
    #expect(GoalRunner.targetIsAccepted(selectedProbability: 0.54, minimumProbability: 0))
    #expect(!GoalRunner.targetIsAccepted(selectedProbability: 0.49, minimumProbability: 0))
    #expect(!GoalRunner.targetIsAccepted(selectedProbability: 0.79, minimumProbability: 0.8))
}

@Test("Calendar date goals constrain taps to navigation prerequisites")
@MainActor
func dateNavigationCandidates() throws {
    let requested = GoalRunner.requestedDate(
        in: "Open Calendar, go to August 20 2026, create an event"
    )
    #expect(requested == RequestedDate(month: "August", day: 20, year: 2026))

    let september = try Observation.rows(from: Data(#"""
    {"role":"AXApplication","frame":{"x":0,"y":0,"width":400,"height":800},"children":[
      {"role":"AXButton","AXLabel":"2026","AXUniqueId":"BackButton","frame":{"x":10,"y":20,"width":90,"height":40}},
      {"role":"AXButton","AXLabel":"Add","AXUniqueId":"add-plus-button","frame":{"x":300,"y":20,"width":90,"height":40}},
      {"role":"AXButton","AXLabel":"Monday 31 August","frame":{"x":10,"y":70,"width":90,"height":40}}
    ]}
    """#.utf8))
    let indexed = Dictionary(uniqueKeysWithValues: september.enumerated().map { ("e\($0.offset)", $0.element) })
    let navigation = GoalRunner.constrainedTapRows(indexed, requestedDate: requested, dateSelected: false)
    #expect(navigation.values.map(\.stableID) == ["BackButton"])

    let august = try Observation.rows(from: Data(#"""
    {"role":"AXApplication","frame":{"x":0,"y":0,"width":400,"height":800},"children":[
      {"role":"AXButton","AXLabel":"Thursday 20 August","frame":{"x":10,"y":70,"width":120,"height":40}},
      {"role":"AXButton","AXLabel":"Add","AXUniqueId":"add-plus-button","frame":{"x":300,"y":20,"width":90,"height":40}}
    ]}
    """#.utf8))
    let augustIndexed = Dictionary(uniqueKeysWithValues: august.enumerated().map { ("e\($0.offset)", $0.element) })
    let date = GoalRunner.constrainedTapRows(augustIndexed, requestedDate: requested, dateSelected: false)
    #expect(date.values.map(\.label) == ["Thursday 20 August"])
}
