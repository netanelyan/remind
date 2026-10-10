import Foundation

/// Reads and writes the JSON database in the shared container.
///
/// The app and the widget's intents can write at the same time, so every access goes
/// through `NSFileCoordinator`, and `mutate` does read-modify-write as one coordinated step.
public enum ReminderRepository {
    public static var fileURL: URL {
        SharedContainer.directory.appending(path: "reminders.json")
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Loads the database, seeding the starter content on first launch.
    public static func load() -> ReminderDatabase {
        var result: ReminderDatabase?
        coordinate(writing: false) { url in
            result = read(at: url)
        }
        if let result { return result }
        return mutate { _ in }
    }

    /// Applies `change` to the latest on-disk state and saves it. Returns the saved database.
    @discardableResult
    public static func mutate(_ change: (inout ReminderDatabase) -> Void) -> ReminderDatabase {
        var database = ReminderDatabase.starter
        coordinate(writing: true) { url in
            database = read(at: url) ?? .starter
            change(&database)
            write(database, to: url)
        }
        return database
    }

    private static func read(at url: URL) -> ReminderDatabase? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(ReminderDatabase.self, from: data)
        } catch {
            // Keep the unreadable file instead of silently overwriting the user's data with starters.
            let backup = url.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date.now.timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            return nil
        }
    }

    private static func write(_ database: ReminderDatabase, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(database).write(to: url, options: [.atomic])
        } catch {
            print("ReminderRepository: failed to save: \(error)")
        }
    }

    private static func coordinate(writing: Bool, _ body: (URL) -> Void) {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        if writing {
            coordinator.coordinate(writingItemAt: fileURL, options: [], error: &error, byAccessor: body)
        } else {
            coordinator.coordinate(readingItemAt: fileURL, options: [], error: &error, byAccessor: body)
        }
        if let error {
            print("ReminderRepository: coordination failed: \(error)")
        }
    }
}
