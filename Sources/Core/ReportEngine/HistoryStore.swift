import Foundation

/// 一次验机快照。除完整报告外，额外冗余几个可比对的关键指标，便于历史对比直接取用。
struct SavedReport: Codable, Identifiable, Sendable {
    var id: UUID
    var savedAt: Date
    var deviceName: String
    var serial: String
    var score: Int
    var batteryCycles: Int?
    var batteryHealth: String?
    var report: MacCheckReport
}

/// 历史记录持久化（无状态）。App 非沙盒，存到 Application Support/MacCheck/history.json。
enum HistoryStore {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacCheck", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("history.json")
    }

    static func load() -> [SavedReport] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([SavedReport].self, from: data) else { return [] }
        return decoded.sorted { $0.savedAt > $1.savedAt }
    }

    static func save(_ reports: [SavedReport]) {
        guard let data = try? JSONEncoder().encode(reports) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
