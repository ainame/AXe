import Foundation
import FBControlCore
import FBSimulatorControl

public enum SimulatorSessionError: Error, LocalizedError {
    case simulatorUnavailable(String)
    case unsupportedCharacter(Character)
    case invalidAccessibilityResponse

    public var errorDescription: String? {
        switch self {
        case .simulatorUnavailable(let udid): "Simulator \(udid) is unavailable or not booted."
        case .unsupportedCharacter(let character): "Unsupported US keyboard character: \(character)"
        case .invalidAccessibilityResponse: "The simulator returned an invalid accessibility hierarchy."
        }
    }
}
public enum ScrollDirection {
    case up
    case down
}

@objc private final class QuietReporter: NSObject, FBEventReporter {
    var metadata: [String: String] = [:]
    func report(_ subject: FBEventReporterSubject) {}
    func addMetadata(_ metadata: [String: String]) {}
}

/// A direct simulator interface shared by agent-facing tools. This target has no TypeSafe dependency.
@MainActor
public final class SimulatorSession {
    private let simulator: FBSimulator
    private let logger: FBControlCoreLogger

    public init(udid: String) throws {
        let logger = FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: false, withDebugLogging: false)
        try FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(logger)
        try FBSimulatorControlFrameworkLoader.xcodeFrameworks.loadPrivateFrameworks(logger)
        let configuration = FBSimulatorControlConfiguration(
            deviceSetPath: nil, logger: logger, reporter: QuietReporter()
        )
        let simulatorSet = try FBSimulatorControl.withConfiguration(configuration).set
        guard let simulator = simulatorSet.allSimulators.first(where: { $0.udid == udid }),
              simulator.state == .booted else {
            throw SimulatorSessionError.simulatorUnavailable(udid)
        }
        self.simulator = simulator
        self.logger = logger
    }

    public func observe() async throws -> Data {
        let element = try await simulator.accessibilityElementForFrontmostApplication()
        defer { element.close() }
        let keys: Set<FBAXKeys> = [
            .label, .frame, .frameDict, .value, .uniqueID, .type, .enabled, .role,
        ]
        let response = try element.serialize(
            with: FBAccessibilityRequestOptions(nestedFormat: true, keys: keys)
        )
        guard JSONSerialization.isValidJSONObject(response.elements) else {
            throw SimulatorSessionError.invalidAccessibilityResponse
        }
        return try JSONSerialization.data(withJSONObject: response.elements)
    }

    /// Reads the element currently hit at a coordinate for a cheap pre-input freshness check.
    public func observe(at point: CGPoint) async throws -> Data {
        let element = try await simulator.accessibilityElement(at: point)
        defer { element.close() }
        let keys: Set<FBAXKeys> = [
            .label, .frame, .frameDict, .value, .uniqueID, .type, .enabled, .role,
        ]
        let response = try element.serialize(
            with: FBAccessibilityRequestOptions(nestedFormat: true, keys: keys)
        )
        guard JSONSerialization.isValidJSONObject(response.elements) else {
            throw SimulatorSessionError.invalidAccessibilityResponse
        }
        return try JSONSerialization.data(withJSONObject: response.elements)
    }

    public func tap(x: Double, y: Double) async throws {
        let hid = try await simulator.connectToHID()
        try await hid.send(event: .tapAt(x: x, y: y), logger: logger)
        try await Task.sleep(for: .milliseconds(100))
    }

    public func tapPhysical(x: Double, y: Double) async throws {
        let hid = try await simulator.connectToHID()
        let down = FBSimulatorHIDEvent.touch(direction: .down, x: x, y: y)
        let up = FBSimulatorHIDEvent.touch(direction: .up, x: x, y: y)
        var pressed = false
        do {
            try await hid.send(event: down, logger: logger)
            pressed = true
            try await Task.sleep(for: .milliseconds(80))
            try await hid.send(event: up, logger: logger)
            pressed = false
        } catch {
            if pressed { try? await hid.send(event: up, logger: logger) }
            throw error
        }
        try await Task.sleep(for: .milliseconds(100))
    }

    public func scroll(in frame: CGRect, direction: ScrollDirection) async throws {
        let hid = try await simulator.connectToHID()
        let travel = min(frame.height * 0.45, 240)
        let center = frame.midY
        let startY = direction == .up ? center + travel / 2 : center - travel / 2
        let endY = direction == .up ? center - travel / 2 : center + travel / 2
        let event = FBSimulatorHIDEvent.swipe(
            frame.midX, yStart: startY, xEnd: frame.midX, yEnd: endY,
            delta: 30, duration: 0.5
        )
        try await hid.send(event: event, logger: logger)
        try await Task.sleep(for: .milliseconds(150))
    }

    public func openApp(bundleID: String) async throws {
        let configuration = FBApplicationLaunchConfiguration(
            bundleID: bundleID, bundleName: nil, arguments: [], environment: [:],
            waitForDebugger: false,
            io: FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull(),
            launchMode: .foregroundIfRunning
        )
        _ = try await simulator.launchApplication(configuration)
        try await Task.sleep(for: .milliseconds(250))
    }

    public func type(_ text: String) async throws {
        let events = try Self.keyboardEvents(for: text)
        let hid = try await simulator.connectToHID()
        try await hid.send(event: .composite(events), logger: logger)
        try await Task.sleep(for: .milliseconds(100))
    }

    public static func validateText(_ text: String) throws {
        _ = try keyboardEvents(for: text)
    }

    private static func keyboardEvents(for text: String) throws -> [FBSimulatorHIDEvent] {
        var events: [FBSimulatorHIDEvent] = []
        for character in text {
            let key = KeyEvent.keyCodeForString(String(character))
            guard key.keyCode != 0 else {
                throw SimulatorSessionError.unsupportedCharacter(character)
            }
            let code = UInt32(key.keyCode)
            if key.shift { events.append(.keyboard(direction: .down, keyCode: 225)) }
            events.append(.keyboard(direction: .down, keyCode: code))
            events.append(.keyboard(direction: .up, keyCode: code))
            if key.shift { events.append(.keyboard(direction: .up, keyCode: 225)) }
        }
        return events
    }
}
