import Foundation
import Observation
import ReminderKit
import UserNotifications
import WidgetKit

/// The app's view of the shared database. Every change goes through `ReminderRepository.mutate`
/// so edits made by the widget in the meantime are never overwritten.
@MainActor
@Observable
final class ReminderStore {
    private(set) var database: ReminderDatabase

    init() {
        database = ReminderRepository.load()
    }

    func reload() {
        database = ReminderRepository.load()
    }

    private func change(_ body: (inout ReminderDatabase) -> Void) {
        database = ReminderRepository.mutate(body)
        WidgetCenter.shared.reloadAllTimelines()
        Notifications.reschedule(for: database)
    }

    // MARK: Reminders

    func add(_ parsed: QuickAddParser.Result, defaultGroup: UUID?) {
        let title = parsed.title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        change { db in
            let groupID = parsed.listHint.flatMap { Self.group(matching: $0, in: db) }
                ?? defaultGroup
                ?? db.sortedGroups.first?.id
            guard let groupID else { return }
            let last = db.reminders.filter { $0.groupID == groupID }.map(\.sortOrder).max() ?? 0
            db.reminders.append(Reminder(
                groupID: groupID,
                title: title,
                dueDate: parsed.dueDate,
                hasTime: parsed.hasTime,
                priority: parsed.priority,
                isFlagged: parsed.isFlagged,
                sortOrder: last + 1
            ))
        }
    }

    /// `#wo` finds "Work": exact name first, then prefix.
    private static func group(matching hint: String, in db: ReminderDatabase) -> UUID? {
        let hint = hint.lowercased()
        let groups = db.sortedGroups
        return (groups.first { $0.name.lowercased() == hint }
            ?? groups.first { $0.name.lowercased().replacingOccurrences(of: " ", with: "").hasPrefix(hint) })?.id
    }

    func setCompleted(_ id: UUID, _ completed: Bool) {
        change { db in
            guard let i = db.reminders.firstIndex(where: { $0.id == id }) else { return }
            db.reminders[i].isCompleted = completed
            db.reminders[i].completedAt = completed ? .now : nil
        }
    }

    func toggleFlag(_ id: UUID) {
        change { db in
            guard let i = db.reminders.firstIndex(where: { $0.id == id }) else { return }
            db.reminders[i].isFlagged.toggle()
        }
    }

    func update(_ reminder: Reminder) {
        change { db in
            guard let i = db.reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
            var reminder = reminder
            // A new date usually means a new urgency section, so start fresh there.
            if reminder.dueDate != db.reminders[i].dueDate || reminder.hasTime != db.reminders[i].hasTime {
                reminder.urgencyRank = nil
            }
            db.reminders[i] = reminder
        }
    }

    func delete(_ ids: some Sequence<UUID>) {
        let ids = Set(ids)
        change { db in db.reminders.removeAll { ids.contains($0.id) } }
    }

    func clearDone() {
        change { db in db.reminders.removeAll(where: \.isCompleted) }
    }

    /// Reorders within one group after a drag. `visible` is the group's rows as shown.
    func move(in visible: [Reminder], from source: IndexSet, to destination: Int) {
        var ordered = visible
        ordered.move(fromOffsets: source, toOffset: destination)
        let orders = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, Double($0)) })
        change { db in
            for i in db.reminders.indices {
                if let order = orders[db.reminders[i].id] { db.reminders[i].sortOrder = order }
            }
        }
    }

    /// Reorders within one urgency section after a drag. `visible` is the section's rows as shown,
    /// which may be a filtered subset (one group, or only flagged). The dragged rows trade places
    /// among the slots they already hold in the full section, so hidden reminders keep their spots.
    func moveByUrgency(in visible: [Reminder], from source: IndexSet, to destination: Int) {
        guard let urgency = visible.first?.urgency() else { return }
        var reordered = visible
        reordered.move(fromOffsets: source, toOffset: destination)
        let visibleIDs = Set(visible.map(\.id))
        change { db in
            let now = Date.now
            let full = db.activeReminders
                .filter { $0.urgency(now: now) == urgency }
                .sorted(by: Reminder.urgencyOrder(now: now))
            var next = reordered.makeIterator()
            let placed = full.map { visibleIDs.contains($0.id) ? (next.next() ?? $0) : $0 }
            let ranks = Dictionary(uniqueKeysWithValues: placed.enumerated().map { ($1.id, Double($0)) })
            for i in db.reminders.indices {
                if let rank = ranks[db.reminders[i].id] { db.reminders[i].urgencyRank = rank }
            }
        }
    }

    // MARK: Groups

    func saveGroup(_ group: ReminderGroup) {
        change { db in
            if let i = db.groups.firstIndex(where: { $0.id == group.id }) {
                db.groups[i] = group
            } else {
                var group = group
                group.sortOrder = (db.groups.map(\.sortOrder).max() ?? -1) + 1
                db.groups.append(group)
            }
        }
    }

    /// Deletes the group and everything in it, including its Done items.
    func deleteGroup(_ id: UUID) {
        change { db in
            db.groups.removeAll { $0.id == id }
            db.reminders.removeAll { $0.groupID == id }
        }
    }

    func moveGroups(from source: IndexSet, to destination: Int) {
        var ordered = database.sortedGroups
        ordered.move(fromOffsets: source, toOffset: destination)
        let orders = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0) })
        change { db in
            for i in db.groups.indices {
                if let order = orders[db.groups[i].id] { db.groups[i].sortOrder = order }
            }
        }
    }

    // MARK: Settings

    func setWidgetGrouping(_ grouping: Grouping) {
        change { $0.widgetGrouping = grouping }
    }
}

enum Notifications {
    static func requestAuthorization() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    /// Replaces all pending notifications with one per upcoming, not-done reminder.
    /// Day-only reminders fire at 9 AM. iOS keeps at most 64, so the soonest win.
    static func reschedule(for database: ReminderDatabase) {
        let now = Date.now
        let calendar = Calendar.current
        let upcoming: [(Reminder, Date)] = database.activeReminders.compactMap { reminder in
            guard let due = reminder.dueDate else { return nil }
            let fire = reminder.hasTime ? due : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: due) ?? due
            return fire > now ? (reminder, fire) : nil
        }
        .sorted { $0.1 < $1.1 }
        let requests = upcoming.prefix(64).map { reminder, fire in
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            if let group = database.group(id: reminder.groupID) { content.subtitle = group.name }
            if !reminder.notes.isEmpty { content.body = reminder.notes }
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            return UNNotificationRequest(
                identifier: reminder.id.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            )
        }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for request in requests {
            center.add(request)
        }
    }
}
