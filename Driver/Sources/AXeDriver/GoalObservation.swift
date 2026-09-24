import Foundation
import AXeSimulator

@MainActor
extension GoalRunner {
    static func acceptsTransition(from previous: [Row], to current: [Row]) -> Bool {
        !current.isEmpty && semanticSignature(current) != semanticSignature(previous)
    }

    static func waitForUIChange(
        from previous: [Row],
        timeout: Duration,
        observe: () async throws -> [Row]
    ) async throws -> [Row]? {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        repeat {
            let current = try await observe()
            if acceptsTransition(from: previous, to: current) { return current }
            if ContinuousClock.now >= deadline { return nil }
            try await Task.sleep(for: .milliseconds(200))
        } while true
    }

    static func stableRows(
        startingWith initial: [Row],
        timeout: Duration,
        observe: () async throws -> [Row]
    ) async throws -> [Row]? {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var previous = initial
        repeat {
            try await Task.sleep(for: .milliseconds(150))
            let current = try await observe()
            if !current.isEmpty && semanticSignature(current) == semanticSignature(previous) {
                return current
            }
            previous = current
            if ContinuousClock.now >= deadline { return nil }
        } while true
    }

    static func stableTarget(
        for selected: Row,
        timeout: Duration,
        observe: () async throws -> [Row]
    ) async throws -> (Row, [Row])? {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var previous: Row? = selected
        repeat {
            let rows = try await observe()
            let matching = rows.filter { $0.fingerprint == selected.fingerprint }
            // A populated replacement screen cannot stabilize the old target.
            // Replan from it without spending the full timeout on repeated tree reads.
            if !rows.isEmpty && matching.isEmpty { return nil }
            let target = matching.count == 1 ? matching[0] : matching.first(where: { $0.id == selected.id })
            if let target, let previous,
               abs(target.frame.centerX - previous.frame.centerX) < 1,
               abs(target.frame.centerY - previous.frame.centerY) < 1 {
                return (target, rows)
            }
            previous = target
            if ContinuousClock.now >= deadline { return nil }
            try await Task.sleep(for: .milliseconds(120))
        } while true
    }

    static func pointMatchesTarget(_ data: Data, selected: Row) -> Bool {
        guard let element = try? JSONDecoder().decode(Element.self, from: data),
              element.enabled != false,
              let frame = element.frame,
              frame.width > 0, frame.height > 0,
              (element.role ?? element.type) == selected.role,
              element.AXLabel?.trimmingCharacters(in: .whitespacesAndNewlines) == selected.label,
              element.AXValue?.trimmingCharacters(in: .whitespacesAndNewlines) == selected.value,
              element.AXUniqueId == selected.stableID else { return false }
        return abs(frame.centerX - selected.frame.centerX) < 1
            && abs(frame.centerY - selected.frame.centerY) < 1
            && abs(frame.width - selected.frame.width) < 1
            && abs(frame.height - selected.frame.height) < 1
    }

    static func freshPointMatchesTarget(_ selected: Row, session: SimulatorSession) async -> Bool {
        let point = CGPoint(x: selected.frame.centerX, y: selected.frame.centerY)
        guard let data = try? await DriverLog.observe(session, at: point) else {
            DriverLog.detail("Point validation failed for \(selected.label ?? selected.id); using full UI")
            return false
        }
        let matched = pointMatchesTarget(data, selected: selected)
        DriverLog.detail("Point validation \(matched ? "matched" : "missed") \(selected.label ?? selected.id)")
        return matched
    }

    static func observeUntilChanged(
        session: SimulatorSession,
        udid: String,
        from before: [Row]
    ) async throws -> [Row] {
        var latest: [Row] = []
        for attempt in 0..<4 {
            latest = try await observeRows(session: session, udid: udid)
            if acceptsTransition(from: before, to: latest) { return latest }
            if attempt < 3 { try await Task.sleep(for: .milliseconds(150)) }
        }
        return latest
    }

    static func observeActionable(session: SimulatorSession, udid: String) async throws -> [Row] {
        var rows: [Row] = []
        for attempt in 0..<4 {
            rows = try await observeRows(session: session, udid: udid)
            if !rows.isEmpty { return rows }
            if attempt < 3 {
                DriverLog.write("Waiting: accessibility returned no actionable controls")
                try await Task.sleep(for: .milliseconds(150))
            }
        }
        return rows
    }

    static func observeRows(
        session: SimulatorSession,
        udid: String,
        includeOffscreen: Bool = false
    ) async throws -> [Row] {
        try Observation.rows(
            from: await observeData(session: session, udid: udid),
            includeOffscreen: includeOffscreen
        )
    }

    static func observeData(session: SimulatorSession, udid: String) async throws -> Data {
        do {
            return try await DriverLog.observe(session)
        } catch {
            DriverLog.write("Warning: accessibility read failed; reconnecting without repeating input (\(error))")
            var lastError = error
            for _ in 0..<4 {
                try await Task.sleep(for: .milliseconds(250))
                do {
                    let fresh = try SimulatorSession(udid: udid)
                    return try await DriverLog.observe(fresh)
                } catch {
                    lastError = error
                }
            }
            DriverLog.write("Warning: in-process accessibility reconnect failed; trying AXe in a fresh process")
            let started = ContinuousClock.now
            do {
                let data = try await Task.detached(priority: .userInitiated) { () throws -> Data in
                    let process = Process()
                    let environment = ProcessInfo.processInfo.environment
                    let candidates = [
                        environment["AXE_BIN_PATH"],
                        FileManager.default.currentDirectoryPath + "/.build/out/Products/Debug/axe",
                    ].compactMap { $0 }
                    if let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                        process.executableURL = URL(fileURLWithPath: executable)
                        process.arguments = ["describe-ui", "--udid", udid]
                    } else {
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                        process.arguments = ["axe", "describe-ui", "--udid", udid]
                    }
                    let output = Pipe()
                    process.standardOutput = output
                    process.standardError = FileHandle.nullDevice
                    try process.run()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else {
                        throw NSError(domain: "AXeDriver", code: Int(process.terminationStatus),
                                      userInfo: [NSLocalizedDescriptionKey: "axe describe-ui failed"])
                    }
                    return data
                }.value
                DriverLog.screenReads += 1
                DriverLog.screenMilliseconds += DriverLog.milliseconds(since: started)
                DriverLog.write("Accessibility recovered in a fresh AXe process")
                return data
            } catch {
                DriverLog.write("Warning: fresh-process accessibility recovery failed: \(error)")
                throw lastError
            }
        }
    }
    static func semanticSignature(_ rows: [Row]) -> [String] {
        rows.map(\.fingerprint)
    }
}
