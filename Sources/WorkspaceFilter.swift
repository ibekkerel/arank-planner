import Foundation

struct WorkspaceActivityRow {
    let activity: Activity
    let depth: Int
    let contextOnly: Bool
}
enum WorkFilter: String, CaseIterable, Identifiable {
    case all, unfinished, inProgress, milestones, critical
    var id: Self { self }
    var title: String {
        switch self {
        case .all: "Все работы"
        case .unfinished: "Незавершённые"
        case .inProgress: "В работе"
        case .milestones: "Вехи"
        case .critical: "Критические"
        }
    }
    static func terms(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { String($0).folding(options:[.caseInsensitive,.diacriticInsensitive],locale:.current) }
    }

    /// Ordered activities use preorder. In a reverse traversal all matches have
    /// propagated their need for context before their parent is processed.
    func rows(_ ordered: [(activity:Activity,depth:Int)], terms:[String], collapsed:Set<String>, timings:[String:Timing]) -> [WorkspaceActivityRow] {
        guard self != .all || !terms.isEmpty else {
            var hiddenDepth: Int?
            return ordered.compactMap { entry in
                if let depth = hiddenDepth, entry.depth > depth { return nil }
                hiddenDepth = collapsed.contains(entry.activity.id) ? entry.depth : nil
                return WorkspaceActivityRow(activity:entry.activity,depth:entry.depth,contextOnly:false)
            }
        }
        let matches = ordered.map { entry -> Bool in
            let a = entry.activity
            switch self {
            case .all: break
            case .unfinished: guard a.entityType == "task" && a.progress < 100 else { return false }
            case .inProgress: guard a.entityType == "task" && a.progress > 0 && a.progress < 100 else { return false }
            case .milestones: guard a.entityType == "milestone" else { return false }
            case .critical: guard a.entityType != "summary", let timing = timings[a.id], timing.float <= 0 else { return false }
            }
            if terms.isEmpty { return true }
            let key = "\(a.id) \(a.name)".folding(options:[.caseInsensitive,.diacriticInsensitive],locale:.current)
            return terms.allSatisfy { key.contains($0) }
        }
        var visibleIDs = Set(ordered.indices.lazy.filter { matches[$0] }.map { ordered[$0].activity.id })
        for entry in ordered.reversed() where visibleIDs.contains(entry.activity.id) {
            if let parent = entry.activity.parent { visibleIDs.insert(parent) }
        }
        return ordered.indices.compactMap { i in
            let e = ordered[i]
            guard visibleIDs.contains(e.activity.id) else { return nil }
            return WorkspaceActivityRow(activity:e.activity,depth:e.depth,contextOnly:!matches[i])
        }
    }

}
