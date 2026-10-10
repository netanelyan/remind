import AppIntents
import ReminderKit
import WidgetKit

// Widget buttons that run in place, without opening the app.
//
// iOS only runs these if the widget bundle contains App Intents metadata (Metadata.appintents),
// which Xcode generates at build time and xtool can't. The GitHub workflow in
// .github/workflows/appintents-metadata.yml builds this target with Xcode on a Mac runner and
// commits the generated metadata to Metadata/, where xtool.yml picks it up.
//
// Keep the type names, titles and parameters stable: the metadata describes them, so changing
// them means running the workflow again.

struct CompleteReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Reminder"
    static let isDiscoverable = false

    @Parameter(title: "Reminder ID")
    var reminderID: String

    init() {}

    init(reminderID: UUID) {
        self.reminderID = reminderID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: reminderID) else { return .result() }
        ReminderRepository.mutate { db in
            guard let i = db.reminders.firstIndex(where: { $0.id == id }) else { return }
            db.reminders[i].isCompleted = true
            db.reminders[i].completedAt = .now
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct SwitchWidgetGroupingIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Widget Grouping"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        ReminderRepository.mutate { db in
            db.widgetGrouping = db.widgetGrouping.toggled
            db.widgetScroll = [:] // the order changed, so start every widget from the top
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Pages a widget's reminder list. Widgets can't scroll, so "N more" and "Back to top" set
/// where the list starts.
struct ScrollWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Scroll Widget"
    static let isDiscoverable = false

    @Parameter(title: "Widget Size")
    var size: String

    @Parameter(title: "First Reminder")
    var offset: Int

    init() {}

    init(size: String, offset: Int) {
        self.size = size
        self.offset = offset
    }

    func perform() async throws -> some IntentResult {
        ReminderRepository.mutate { $0.widgetScroll[size] = offset }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
