import Foundation

public enum Priority: Int, Codable, CaseIterable, Comparable, Sendable {
    case none = 0, low, medium, high

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    /// "!", "!!", "!!!", shown inline before titles.
    public var marks: String { String(repeating: "!", count: rawValue) }
}

/// Named palette so groups stay theme-aware (SwiftUI maps these to adaptive colors).
public enum GroupColor: String, Codable, CaseIterable, Sendable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, graphite
}

public struct ReminderGroup: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var color: GroupColor
    public var symbol: String
    public var sortOrder: Int

    public init(id: UUID = UUID(), name: String, color: GroupColor, symbol: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.color = color
        self.symbol = symbol
        self.sortOrder = sortOrder
    }
}

/// How reminders are bucketed, in the app's list screens and in the widget.
public enum Grouping: String, Codable, CaseIterable, Sendable {
    case groups, urgency

    public var label: String {
        switch self {
        case .groups: "Groups"
        case .urgency: "Urgency"
        }
    }

    public var symbol: String {
        switch self {
        case .groups: "square.stack.3d.up.fill"
        case .urgency: "flame.fill"
        }
    }

    public var toggled: Grouping { self == .groups ? .urgency : .groups }
}

/// Urgency buckets, most urgent first.
public enum Urgency: Int, CaseIterable, Comparable, Sendable {
    case overdue, today, tomorrow, thisWeek, later, someday

    public static func < (lhs: Urgency, rhs: Urgency) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .thisWeek: "Next 7 Days"
        case .later: "Later"
        case .someday: "No Date"
        }
    }

    public var symbol: String {
        switch self {
        case .overdue: "exclamationmark.triangle.fill"
        case .today: "sun.max.fill"
        case .tomorrow: "sunrise.fill"
        case .thisWeek: "calendar"
        case .later: "calendar.badge.clock"
        case .someday: "tray.fill"
        }
    }

    public var color: GroupColor {
        switch self {
        case .overdue: .red
        case .today: .orange
        case .tomorrow: .yellow
        case .thisWeek: .blue
        case .later: .indigo
        case .someday: .graphite
        }
    }
}

public struct Reminder: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var groupID: UUID
    public var title: String
    public var notes: String
    /// When `hasTime` is false only the calendar day of `dueDate` is meaningful.
    public var dueDate: Date?
    public var hasTime: Bool
    public var priority: Priority
    public var isFlagged: Bool
    /// Completed reminders leave every normal view and live in the hidden Done folder.
    public var isCompleted: Bool
    public var completedAt: Date?
    public var createdAt: Date
    /// Manual order within a group; fractional so a drop between two rows needs no renumbering.
    public var sortOrder: Double
    /// Your own order inside an urgency section, set by dragging in Urgency mode.
    /// Nil until placed; unplaced reminders sit at the top of their section in automatic order.
    public var urgencyRank: Double?

    public init(
        id: UUID = UUID(),
        groupID: UUID,
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        hasTime: Bool = false,
        priority: Priority = .none,
        isFlagged: Bool = false,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = .now,
        sortOrder: Double = 0,
        urgencyRank: Double? = nil
    ) {
        self.id = id
        self.groupID = groupID
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.hasTime = hasTime
        self.priority = priority
        self.isFlagged = isFlagged
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.urgencyRank = urgencyRank
    }

    public func isOverdue(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !isCompleted, let dueDate else { return false }
        return hasTime ? dueDate < now : dueDate < calendar.startOfDay(for: now)
    }

    public func isDue(onDayOf day: Date, calendar: Calendar = .current) -> Bool {
        guard let dueDate else { return false }
        return calendar.isDate(dueDate, inSameDayAs: day)
    }

    /// Due today or already overdue: what "Today" and the widget's progress ring count.
    public func isDueTodayOrOverdue(now: Date = .now, calendar: Calendar = .current) -> Bool {
        isOverdue(now: now, calendar: calendar) || isDue(onDayOf: now, calendar: calendar)
    }

    public func urgency(now: Date = .now, calendar: Calendar = .current) -> Urgency {
        guard let dueDate else { return .someday }
        if isOverdue(now: now, calendar: calendar) { return .overdue }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: dueDate)).day ?? 0
        switch days {
        case ...0: return .today
        case 1: return .tomorrow
        case 2...7: return .thisWeek
        default: return .later
        }
    }

    /// Orders by bucket, then your dragged order, then (for unplaced reminders) due moment,
    /// priority, flag and group order.
    public static func urgencyOrder(now: Date = .now, calendar: Calendar = .current) -> (Reminder, Reminder) -> Bool {
        { a, b in
            let ua = a.urgency(now: now, calendar: calendar), ub = b.urgency(now: now, calendar: calendar)
            if ua != ub { return ua < ub }
            switch (a.urgencyRank, b.urgencyRank) {
            case let (ra?, rb?) where ra != rb: return ra < rb
            case (nil, _?): return true
            case (_?, nil): return false
            default: break
            }
            if let da = a.dueDate, let db = b.dueDate, da != db {
                // A day-only reminder sorts before timed ones on the same day.
                let ka = a.hasTime ? da : calendar.startOfDay(for: da)
                let kb = b.hasTime ? db : calendar.startOfDay(for: db)
                if ka != kb { return ka < kb }
            }
            if a.priority != b.priority { return a.priority > b.priority }
            if a.isFlagged != b.isFlagged { return a.isFlagged }
            return a.sortOrder < b.sortOrder
        }
    }
}

/// Everything persisted, in one file shared through the App Group.
public struct ReminderDatabase: Codable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var groups: [ReminderGroup]
    public var reminders: [Reminder]
    /// What the Home Screen widget buckets by. Flipped from the widget itself or from the app.
    public var widgetGrouping: Grouping
    /// How far each widget size is paged down, as the number of reminders skipped. Keyed by size
    /// ("small", "medium", "large") so differently sized widgets page independently.
    public var widgetScroll: [String: Int]

    public init(
        version: Int = Self.currentVersion,
        groups: [ReminderGroup],
        reminders: [Reminder],
        widgetGrouping: Grouping = .urgency,
        widgetScroll: [String: Int] = [:]
    ) {
        self.version = version
        self.groups = groups
        self.reminders = reminders
        self.widgetGrouping = widgetGrouping
        self.widgetScroll = widgetScroll
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        groups = try c.decode([ReminderGroup].self, forKey: .groups)
        reminders = try c.decode([Reminder].self, forKey: .reminders)
        widgetGrouping = try c.decodeIfPresent(Grouping.self, forKey: .widgetGrouping) ?? .urgency
        widgetScroll = try c.decodeIfPresent([String: Int].self, forKey: .widgetScroll) ?? [:]
    }

    public func group(id: UUID) -> ReminderGroup? {
        groups.first { $0.id == id }
    }

    public var sortedGroups: [ReminderGroup] {
        groups.sorted { $0.sortOrder < $1.sortOrder }
    }

    public var activeReminders: [Reminder] { reminders.filter { !$0.isCompleted } }

    /// The hidden Done folder, most recently finished first.
    public var doneReminders: [Reminder] {
        reminders.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    public static var starter: ReminderDatabase {
        let personal = ReminderGroup(name: "Personal", color: .blue, symbol: "person.fill", sortOrder: 0)
        let work = ReminderGroup(name: "Work", color: .orange, symbol: "briefcase.fill", sortOrder: 1)
        let groceries = ReminderGroup(name: "Groceries", color: .green, symbol: "cart.fill", sortOrder: 2)
        let today = Calendar.current.startOfDay(for: .now)
        return ReminderDatabase(
            groups: [personal, work, groceries],
            reminders: [
                Reminder(groupID: personal.id, title: "Tap the circle to finish me", dueDate: today, sortOrder: 0),
                Reminder(groupID: personal.id, title: "Try quick add: call mom tomorrow 6pm !high #personal",
                         dueDate: today, isFlagged: true, sortOrder: 1),
                Reminder(groupID: work.id, title: "Add the Remind widget to your Home Screen",
                         dueDate: today, priority: .medium, sortOrder: 0),
                Reminder(groupID: groceries.id, title: "Oat milk", sortOrder: 0),
            ]
        )
    }
}
