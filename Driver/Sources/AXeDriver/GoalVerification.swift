import Foundation
import TypeSafe

@MainActor
extension GoalRunner {
    struct VerificationResponse {
        let result: GoalVerification
        let inputTokens: Int
        let outputTokens: Int
    }

    static func verify(
        request: InteractionRequest,
        rows: [Row],
        client: TypeSafeClient
    ) async throws -> VerificationResponse {
        let expectedLabels = request.expectLabels ?? []
        let expectedIDs = request.expectIDs ?? []
        let expectedValues = request.expectValues ?? []
        let missingLabels = expectedLabels.filter { expected in !rows.contains { $0.label == expected } }
        let missingIDs = expectedIDs.filter { expected in !rows.contains { $0.stableID == expected } }
        let missingValues = expectedValues.filter { expected in !rows.contains { $0.value == expected } }
        let requirements = request.requirements ?? []
        guard !requirements.isEmpty else {
            return VerificationResponse(
                result: GoalVerification(
                    requirements: [],
                    expectedLabels: expectedLabels,
                    expectedIDs: expectedIDs,
                    expectedValues: expectedValues,
                    missingLabels: missingLabels,
                    missingIDs: missingIDs,
                    missingValues: missingValues
                ),
                inputTokens: 0,
                outputTokens: 0
            )
        }

        var questions: [String: Question] = [:]
        addRequirementQuestions(requirements, questions: &questions)
        let response = try await client.systemOne(
            state: ["visible_ui": .array(compactRows(rows).map(JSONValue.string))],
            questions: questions
        )
        let results = requirements.enumerated().map { index, requirement in
            RequirementResult(
                requirement: requirement,
                probability: response.nouls["requirement_\(index)"]?.noul ?? 0
            )
        }
        return VerificationResponse(
            result: GoalVerification(
                requirements: results,
                expectedLabels: expectedLabels,
                expectedIDs: expectedIDs,
                expectedValues: expectedValues,
                missingLabels: missingLabels,
                missingIDs: missingIDs,
                missingValues: missingValues
            ),
            inputTokens: response.usage.inputTokens ?? 0,
            outputTokens: response.usage.outputTokens ?? 0
        )
    }
}
