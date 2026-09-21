import Foundation

private struct ErrorResult: Encodable {
    let status = "error"
    let message: String
}
@main
struct DriverMain {
    static func main() async {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            let request = try JSONDecoder().decode(InteractionRequest.self, from: input)
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
            exit(1)
        }
    }
}
