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
    #expect(GoalRunner.shouldSettleNavigation(rows: september, requestedDate: requested, dateSelected: false, afterLaunch: false))

    let august = try Observation.rows(from: Data(#"""
    {"role":"AXApplication","frame":{"x":0,"y":0,"width":400,"height":800},"children":[
      {"role":"AXButton","AXLabel":"Thursday 20 August","frame":{"x":10,"y":70,"width":120,"height":40}},
      {"role":"AXButton","AXLabel":"Add","AXUniqueId":"add-plus-button","frame":{"x":300,"y":20,"width":90,"height":40}}
    ]}
    """#.utf8))
    let augustIndexed = Dictionary(uniqueKeysWithValues: august.enumerated().map { ("e\($0.offset)", $0.element) })
    let date = GoalRunner.constrainedTapRows(augustIndexed, requestedDate: requested, dateSelected: false)
    #expect(date.values.map(\.label) == ["Thursday 20 August"])
    #expect(!GoalRunner.shouldSettleNavigation(rows: august, requestedDate: requested, dateSelected: false, afterLaunch: false))
}

@Test("Quoted event goal derives exact text and date-specific verification")
@MainActor
func positionalCalendarGoal() {
    let goal = "Open Calendar app, go to Aug 16 2026, create a new event titled 'Cameron Birthday' and save."
    let inferred = GoalArguments.infer(from: goal)
    #expect(inferred.text == "Cameron Birthday")
    #expect(inferred.requirements == ["A saved event titled Cameron Birthday is visible on August 16 2026"])
    #expect(inferred.appBundleID == "com.apple.mobilecal")
    #expect(inferred.appName == "Calendar")
    #expect(GoalRunner.requestedDate(in: goal) == RequestedDate(month: "August", day: 16, year: 2026))
}

@Test("A current-day heading confirms an unchanged Calendar date tap")
@MainActor
func currentDayConfirmsSelection() {
    let data = Data(#"{"role":"AXApplication","AXLabel":"Calendar","children":[{"role":"AXHeading","AXUniqueId":"current-day","AXLabel":"Sunday – 16 Aug 2026"}]}"#.utf8)
    let august16 = RequestedDate(month: "August", day: 16, year: 2026)
    let august17 = RequestedDate(month: "August", day: 17, year: 2026)
    #expect(GoalRunner.currentDateMatches(data, requestedDate: august16))
    #expect(!GoalRunner.currentDateMatches(data, requestedDate: august17))
}

@Test("Save shortcut requires one Done button, exact title, and requested start date")
@MainActor
func saveRequiresEditorEvidence() {
    let date = RequestedDate(month: "August", day: 16, year: 2026)
    let frame = Rectangle(x: 0, y: 0, width: 10, height: 10)
    let done = Row(id: "done", role: "AXButton", label: "Done", value: nil,
                   stableID: nil, parent: nil, frame: frame, actions: ["tap"])
    let title = Row(id: "title", role: "AXTextArea", label: "Title", value: "Cameron Birthday",
                    stableID: "title-field", parent: nil, frame: frame, actions: ["tap", "type"])
    let start = Row(id: "start", role: "AXButton", label: "16 Aug 2026", value: nil,
                    stableID: "start-date-picker-cell", parent: nil, frame: frame, actions: ["tap"])
    #expect(GoalRunner.editorIsReadyToSave(rows: [done, title, start], exactText: "Cameron Birthday", requestedDate: date))
    #expect(!GoalRunner.editorIsReadyToSave(rows: [done, title, start], exactText: "Different title", requestedDate: date))
    #expect(!GoalRunner.editorIsReadyToSave(rows: [done, title], exactText: "Cameron Birthday", requestedDate: date))
    #expect(!GoalRunner.editorIsReadyToSave(rows: [done, done, title, start], exactText: "Cameron Birthday", requestedDate: date))
}

@Test("Exact title can be typed only into one empty event editor field")
@MainActor
func typeRequiresEditorEvidence() {
    let frame = Rectangle(x: 0, y: 0, width: 10, height: 10)
    let cancel = Row(id: "cancel", role: "AXButton", label: "Cancel", value: nil,
                     stableID: nil, parent: nil, frame: frame, actions: ["tap"])
    let done = Row(id: "done", role: "AXButton", label: "Done", value: nil,
                   stableID: nil, parent: nil, frame: frame, actions: ["tap"])
    let title = Row(id: "title", role: "AXTextArea", label: "Title", value: "Title",
                    stableID: "title-field", parent: nil, frame: frame, actions: ["tap", "type"])
    #expect(GoalRunner.editorIsReadyForTitle(rows: [cancel, done, title], exactText: "Cameron Birthday"))
    #expect(!GoalRunner.editorIsReadyForTitle(rows: [cancel, done, title, title], exactText: "Cameron Birthday"))
    #expect(!GoalRunner.editorIsReadyForTitle(rows: [done, title], exactText: "Cameron Birthday"))
}
