import Foundation

/// One titled bucket of reminders: a group, or an urgency level.
public struct ReminderSection: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var symbol: String
    public var color: GroupColor
    public var reminders: [Reminder]
    /// Set when the section is a group, so callers can offer group-specific actions like reordering.
    public var groupID: UUID?
}

extension ReminderDatabase {
    /// Buckets `reminders` by group (in group order, manual order inside) or by urgency
    /// (most urgent first). Empty buckets are dropped.
    public func sections(
        of reminders: [Reminder],
        by grouping: Grouping,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ReminderSection] {
        switch grouping {
        case .groups:
            let byGroup = Dictionary(grouping: reminders, by: \.groupID)
            return sortedGroups.compactMap { group in
                guard let items = byGroup[group.id], !items.isEmpty else { return nil }
                return ReminderSection(
                    id: group.id.uuidString,
                    title: group.name,
                    symbol: group.symbol,
                    color: group.color,
                    reminders: items.sorted { $0.sortOrder < $1.sortOrder },
                    groupID: group.id
                )
            }
        case .urgency:
            let order = Reminder.urgencyOrder(now: now, calendar: calendar)
            let byUrgency = Dictionary(grouping: reminders) { $0.urgency(now: now, calendar: calendar) }
            return Urgency.allCases.compactMap { urgency in
                guard let items = byUrgency[urgency], !items.isEmpty else { return nil }
                return ReminderSection(
                    id: "urgency-\(urgency.rawValue)",
                    title: urgency.label,
                    symbol: urgency.symbol,
                    color: urgency.color,
                    reminders: items.sorted(by: order)
                )
            }
        }
    }
}
