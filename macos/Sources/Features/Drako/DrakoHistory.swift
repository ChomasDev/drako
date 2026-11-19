import Foundation
import OSLog

/// The terminals the user closed, newest first: the sidebar's "Archived".
/// Kept in `Application Support/Drako/history.json`.
@MainActor
final class DrakoHistory: ObservableObject {
    struct Record: Codable, Equatable, Identifiable {
        var id = UUID()
        let program: String
        let title: String
        let cwd: String?
        let host: DrakoHost
        let closedAt: Date
    }

    static let shared = DrakoHistory()

    @Published private(set) var records: [Record]

    private static let limit = 100

    private static let file = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Drako/history.json")

    private static let logger = Logger(subsystem: "dev.drako.Drako", category: "history")

    private init() {
        records = Self.load()
    }

    func archive(_ record: Record) {
        records = Array(([record] + records).prefix(Self.limit))
        save()
    }

    func remove(_ id: Record.ID) {
        records.removeAll { $0.id == id }
        save()
    }

    func clear() {
        records = []
        save()
    }

    private static func load() -> [Record] {
        guard let data = try? Data(contentsOf: file) else { return [] }

        do {
            return try JSONDecoder().decode([Record].self, from: data)
        } catch {
            logger.warning("unreadable history, starting fresh: \(error.localizedDescription)")
            return []
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: Self.file.deletingLastPathComponent(),
                withIntermediateDirectories: true)

            try JSONEncoder().encode(records).write(to: Self.file, options: .atomic)
        } catch {
            Self.logger.warning("couldn't save the history: \(error.localizedDescription)")
        }
    }
}
