import Foundation

enum TidylyWidgetStore {
    static let appGroup = "group.com.tidyly.jonesweb.club"
    static let snapshotKey = "tidyly.widget.snapshot"

    static func save(_ snapshot: TidylyWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot),
              let defaults = UserDefaults(suiteName: appGroup) else { return }
        defaults.set(data, forKey: snapshotKey)
        defaults.synchronize()
    }

    static func load() -> TidylyWidgetSnapshot {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(TidylyWidgetSnapshot.self, from: data) else { return .empty }
        return snapshot
    }
}

struct TidylyWidgetSnapshot: Codable {
    let generatedAt: Date
    let remainingCount: Int
    let completedCount: Int
    let remainingMinutes: Int
    let tasks: [TidylyWidgetTask]

    var totalCount: Int { remainingCount + completedCount }
    var progress: Double { totalCount == 0 ? 1 : Double(completedCount) / Double(totalCount) }
    static let empty = TidylyWidgetSnapshot(generatedAt: Date(), remainingCount: 0, completedCount: 0, remainingMinutes: 0, tasks: [])
}

struct TidylyWidgetTask: Codable, Identifiable {
    let id: UUID
    let title: String
    let roomName: String
    let roomIcon: String
    let isOverdue: Bool
}
