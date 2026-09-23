import Foundation
import AXeSimulator

@MainActor
extension GoalRunner {
    static func requestedDate(in instruction: String) -> RequestedDate? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let months = formatter.monthSymbols, let shortMonths = formatter.shortMonthSymbols else { return nil }
        guard let monthIndex = months.indices.first(where: { index in
            [months[index], shortMonths[index]].contains { symbol in
                instruction.range(of: "\\b\(NSRegularExpression.escapedPattern(for: symbol))\\b", options: [.regularExpression, .caseInsensitive]) != nil
            }
        }) else { return nil }
        let month = months[monthIndex]
        let escaped = "(?:\(NSRegularExpression.escapedPattern(for: month))|\(NSRegularExpression.escapedPattern(for: shortMonths[monthIndex])))"
        let pattern = "(?i)\\b\(escaped)\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,)?\\s+(\\d{4})\\b"
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: instruction,
                range: NSRange(instruction.startIndex..., in: instruction)
              ),
              let dayRange = Range(match.range(at: 1), in: instruction),
              let yearRange = Range(match.range(at: 2), in: instruction),
              let day = Int(instruction[dayRange]),
              let year = Int(instruction[yearRange]),
              (1...31).contains(day) else { return nil }
        return RequestedDate(month: month, day: day, year: year)
    }

    static func currentDateMatches(_ data: Data, requestedDate: RequestedDate) -> Bool {
        let decoder = JSONDecoder()
        let roots: [Element]
        if let root = try? decoder.decode(Element.self, from: data) {
            roots = [root]
        } else if let decoded = try? decoder.decode([Element].self, from: data) {
            roots = decoded
        } else {
            return false
        }
        let month = NSRegularExpression.escapedPattern(for: requestedDate.month)
        let shortMonth = NSRegularExpression.escapedPattern(for: String(requestedDate.month.prefix(3)))
        let pattern = "(?i)\\b\(requestedDate.day)\\s+(?:\(month)|\(shortMonth))\\s+\(requestedDate.year)\\b"
        func matches(_ element: Element) -> Bool {
            if element.AXUniqueId == "current-day", let label = element.AXLabel,
               label.range(of: pattern, options: .regularExpression) != nil { return true }
            return (element.children ?? []).contains(where: matches)
        }
        return roots.contains(where: matches)
    }

    static func editorIsReadyToSave(
        rows: [Row], exactText: String?, requestedDate: RequestedDate?
    ) -> Bool {
        guard let exactText, let requestedDate,
              rows.filter({ $0.label == "Done" && $0.role == "AXButton" }).count == 1,
              rows.contains(where: { $0.stableID == "title-field" && $0.value == exactText }) else {
            return false
        }
        let month = NSRegularExpression.escapedPattern(for: requestedDate.month)
        let shortMonth = NSRegularExpression.escapedPattern(for: String(requestedDate.month.prefix(3)))
        let pattern = "(?i)^\(requestedDate.day)\\s+(?:\(month)|\(shortMonth))\\s+\(requestedDate.year)$"
        return rows.contains {
            $0.stableID == "start-date-picker-cell"
                && $0.label?.range(of: pattern, options: .regularExpression) != nil
        }
    }

    static func editorIsReadyForTitle(rows: [Row], exactText: String?) -> Bool {
        guard exactText?.isEmpty == false,
              rows.contains(where: { $0.label == "Cancel" && $0.role == "AXButton" }),
              rows.contains(where: { $0.label == "Done" && $0.role == "AXButton" }) else {
            return false
        }
        let fields = rows.filter { $0.stableID == "title-field" && $0.actions.contains("type") }
        guard fields.count == 1 else { return false }
        let field = fields[0]
        return field.value == nil || field.value?.isEmpty == true || field.value == field.label
    }

    static func currentDateIsSelected(
        session: SimulatorSession,
        udid: String,
        requestedDate: RequestedDate
    ) async throws -> Bool {
        currentDateMatches(try await observeData(session: session, udid: udid), requestedDate: requestedDate)
    }

    static func constrainedTapRows(
        _ rows: [String: Row],
        requestedDate: RequestedDate?,
        dateSelected: Bool
    ) -> [String: Row] {
        guard let requestedDate, !dateSelected else { return rows }
        let exactDateRows = rows.filter { row($0.value, matches: requestedDate) }
        if !exactDateRows.isEmpty { return exactDateRows }

        let monthRows = rows.filter { _, row in
            guard let label = row.label else { return false }
            return label.compare(requestedDate.month, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        if !monthRows.isEmpty { return monthRows }

        let backRows = rows.filter { $0.value.stableID == "BackButton" }
        if !backRows.isEmpty { return backRows }

        return rows.filter { _, row in
            row.stableID != "add-plus-button" && row.label?.caseInsensitiveCompare("Add") != .orderedSame
        }
    }

    static func row(_ row: Row, matches requestedDate: RequestedDate) -> Bool {
        guard let label = row.label,
              label.range(of: requestedDate.month, options: [.caseInsensitive, .diacriticInsensitive]) != nil else {
            return false
        }
        let pattern = "\\b\(requestedDate.day)\\b"
        return label.range(of: pattern, options: .regularExpression) != nil
    }
}
