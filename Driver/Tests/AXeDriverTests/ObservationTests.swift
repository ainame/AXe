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
