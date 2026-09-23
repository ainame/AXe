import Foundation
import AXeSimulator

@MainActor
enum DriverLog {
    static var screenReads = 0
    static var screenMilliseconds = 0
    static var jevMilliseconds = 0
    static var inputMilliseconds = 0

    static func reset() {
        screenReads = 0
        screenMilliseconds = 0
        jevMilliseconds = 0
        inputMilliseconds = 0
    }

    static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let components = start.duration(to: .now).components
        return Int(components.seconds) * 1_000 + Int(components.attoseconds / 1_000_000_000_000_000)
    }

    static func observe(_ session: SimulatorSession) async throws -> Data {
        let start = ContinuousClock.now
        defer {
            screenReads += 1
            screenMilliseconds += milliseconds(since: start)
        }
        return try await session.observe()
    }

    static func observe(_ session: SimulatorSession, at point: CGPoint) async throws -> Data {
        let start = ContinuousClock.now
        defer {
            screenReads += 1
            screenMilliseconds += milliseconds(since: start)
        }
        return try await session.observe(at: point)
    }

    static func write(_ message: String) {
        guard ProcessInfo.processInfo.environment["AXE_DRIVER_LOG"] != "0" else { return }
        let stamp = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)
            .time(includingFractionalSeconds: true).timeZone(separator: .omitted))
        FileHandle.standardError.write(Data("[\(stamp)] \(message)\n".utf8))
    }

    static func detail(_ message: String) {
        guard ProcessInfo.processInfo.environment["AXE_DRIVER_LOG"] == "verbose" else { return }
        write(message)
    }

    static func probability(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "n/a"
    }
}
