import Foundation
import Combine

enum ActivityLogLevel: String {
    case info
    case warn
    case error
}

struct ActivityLogEntry: Identifiable, Equatable, Codable {
    let id: UUID
    let date: Date
    let level: String
    let category: String
    let message: String

    init(id: UUID = UUID(), date: Date = Date(), level: ActivityLogLevel, category: String, message: String) {
        self.id = id
        self.date = date
        self.level = level.rawValue
        self.category = category
        self.message = message
    }

    var levelEnum: ActivityLogLevel {
        ActivityLogLevel(rawValue: level) ?? .info
    }
}

@MainActor
final class ActivityLogStore: ObservableObject {
    static let shared = ActivityLogStore()

    @Published private(set) var entries: [ActivityLogEntry] = []

    private let maxEntries = 200
    private let defaultsKey = "activityLog.entries"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([ActivityLogEntry].self, from: data) {
            entries = decoded
        }
    }

    func append(level: ActivityLogLevel = .info, category: String, message: String) {
        let entry = ActivityLogEntry(level: level, category: category, message: message)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        persist()
    }

    func clear() {
        entries = []
        persist()
        append(level: .info, category: "Log", message: L10n.tr("Activity Log Cleared"))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    /// Thread-safe helper for background IO callbacks.
    nonisolated static func log(_ level: ActivityLogLevel = .info, category: String, message: String) {
        DispatchQueue.main.async {
            ActivityLogStore.shared.append(level: level, category: category, message: message)
        }
    }
}
