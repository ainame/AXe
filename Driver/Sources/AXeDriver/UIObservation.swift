import Foundation

struct Rectangle: Decodable, Encodable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    var centerX: Double { x + width / 2 }
    var centerY: Double { y + height / 2 }
    func contained(in other: Rectangle) -> Bool {
        width > 0 && height > 0 && x >= other.x && y >= other.y
            && x + width <= other.x + other.width
            && y + height <= other.y + other.height
    }
}

struct Element: Decodable {
    let type: String?
    let role: String?
    let AXLabel: String?
    let AXValue: String?
    let AXUniqueId: String?
    let enabled: Bool?
    let frame: Rectangle?
    let children: [Element]?

    enum CodingKeys: String, CodingKey {
        case type, role, AXLabel, AXValue, AXUniqueId, enabled, frame, children
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        type = try fields.decodeIfPresent(String.self, forKey: .type)
        role = try fields.decodeIfPresent(String.self, forKey: .role)
        AXLabel = try Self.scalar(fields, .AXLabel)
        AXValue = try Self.scalar(fields, .AXValue)
        AXUniqueId = try Self.scalar(fields, .AXUniqueId)
        enabled = try fields.decodeIfPresent(Bool.self, forKey: .enabled)
        frame = try fields.decodeIfPresent(Rectangle.self, forKey: .frame)
        children = try fields.decodeIfPresent([Element].self, forKey: .children)
    }

    private static func scalar(_ fields: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> String? {
        guard fields.contains(key), try !fields.decodeNil(forKey: key) else { return nil }
        if let value = try? fields.decode(String.self, forKey: key) { return value }
        if let value = try? fields.decode(Int.self, forKey: key) { return String(value) }
        if let value = try? fields.decode(Double.self, forKey: key) { return String(value) }
        if let value = try? fields.decode(Bool.self, forKey: key) { return String(value) }
        return nil
    }
}

struct Row: Encodable {
    let id: String
    let role: String
    let label: String?
    let value: String?
    let stableID: String?
    let parent: String?
    let frame: Rectangle
    let actions: [String]

    var fingerprint: String {
        [role, label ?? "", value ?? "", stableID ?? "", parent ?? ""].joined(separator: "\u{1f}")
    }
}

enum Observation {
    static func rows(from data: Data, includeOffscreen: Bool = false) throws -> [Row] {
        let decoder = JSONDecoder()
        let roots: [Element]
        if let root = try? decoder.decode(Element.self, from: data) {
            roots = [root]
        } else {
            roots = try decoder.decode([Element].self, from: data)
        }
        guard let viewport = roots.compactMap(\.frame).first else { return [] }
        var rows: [Row] = []
        func hasActionableDescendant(_ element: Element) -> Bool {
            let role = element.role ?? element.type ?? ""
            return ["Button", "Cell", "Switch", "CheckBox", "Link", "Tab", "TextField", "TextView", "TextArea", "Picker"]
                .contains(where: role.contains)
                || (element.children ?? []).contains(where: hasActionableDescendant)
        }
        func containsSheet(_ element: Element) -> Bool {
            let role = element.role ?? element.type ?? ""
            if role.contains("Sheet") || role.contains("Alert") { return true }
            if let frame = element.frame,
               frame.x <= viewport.x + 1, frame.width >= viewport.width - 2,
               frame.y >= viewport.y + 20, frame.y <= viewport.y + viewport.height * 0.3,
               frame.height >= viewport.height * 0.6,
               frame.height <= viewport.height - 10,
               hasActionableDescendant(element) { return true }
            return (element.children ?? []).contains(where: containsSheet)
        }
        func visit(_ element: Element, path: String, parent: String?) {
            let role = element.role ?? element.type ?? "Unknown"
            let label = element.AXLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = element.AXValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let context = label?.isEmpty == false ? label : parent
            if let frame = element.frame,
               (includeOffscreen || frame.contained(in: viewport)),
               element.enabled != false {
                let editable = role.contains("TextField") || role.contains("TextView") || role.contains("TextArea")
                let tappable = ["Button", "Cell", "Switch", "CheckBox", "Link", "Tab", "TextField", "TextView", "TextArea", "Picker"]
                    .contains(where: role.contains)
                let scrollable = ["ScrollView", "CollectionView", "Table", "List"].contains(where: role.contains)
                let actions = (tappable ? ["tap"] : []) + (editable ? ["type"] : [])
                    + (scrollable ? ["scroll"] : [])
                if !actions.isEmpty {
                    rows.append(Row(id: path, role: role, label: label, value: value,
                                    stableID: element.AXUniqueId, parent: parent, frame: frame, actions: actions))
                }
            }
            let children = element.children ?? []
            let covering = children.enumerated().filter { _, child in
                guard let frame = child.frame else { return false }
                return frame.x <= viewport.x + 1 && frame.y <= viewport.y + 1
                    && frame.width >= viewport.width - 2 && frame.height >= viewport.height - 2
                    && hasActionableDescendant(child)
            }
            // AXe may retain controls behind a later sheet. A full-screen toolbar container
            // alone is not evidence of occlusion.
            let lastCovering = covering.last
            let visibleChildren = path.split(separator: ".").count <= 2 && covering.count > 1
                && lastCovering.map({ $0.element.AXLabel == nil && containsSheet($0.element) }) == true
                ? [lastCovering!]
                : Array(children.enumerated())
            for (index, child) in visibleChildren {
                visit(child, path: "\(path).\(index)", parent: context)
            }
        }
        for (index, root) in roots.enumerated() { visit(root, path: "\(index)", parent: nil) }
        return Array(rows.prefix(150))
    }
}
