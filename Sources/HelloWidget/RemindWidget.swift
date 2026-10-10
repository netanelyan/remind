import AppIntents
import ReminderKit
import SwiftUI
import WidgetKit

@main
struct RemindWidgetBundle: WidgetBundle {
    var body: some Widget {
        RemindWidget()
        RemindAccessoryWidget()
    }
}

struct RemindEntry: TimelineEntry {
    var date: Date
    var grouping: Grouping
    var sections: [ReminderSection]
    var groups: [UUID: ReminderGroup]
    var leftToday: Int
    var doneToday: Int

    /// Share of today's work finished; a day with nothing due counts as complete.
    var progress: Double {
        let total = leftToday + doneToday
        return total == 0 ? 1 : Double(doneToday) / Double(total)
    }

    var allActive: [Reminder] { sections.flatMap(\.reminders) }

    static let placeholder: RemindEntry = {
        let db = ReminderDatabase.starter
        return RemindEntry(database: db, now: .now)
    }()

    init(database db: ReminderDatabase, now: Date) {
        date = now
        grouping = db.widgetGrouping
        sections = db.sections(of: db.activeReminders, by: db.widgetGrouping, now: now)
        groups = Dictionary(uniqueKeysWithValues: db.groups.map { ($0.id, $0) })
        leftToday = db.activeReminders.filter { $0.isDueTodayOrOverdue(now: now) }.count
        doneToday = db.doneReminders.filter { $0.completedAt.map(Calendar.current.isDateInToday) ?? false }.count
    }
}

struct RemindProvider: TimelineProvider {
    func placeholder(in context: Context) -> RemindEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (RemindEntry) -> Void) {
        completion(context.isPreview ? .placeholder : RemindEntry(database: ReminderRepository.load(), now: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RemindEntry>) -> Void) {
        let db = ReminderRepository.load()
        let now = Date.now
        let calendar = Calendar.current
        // Urgency buckets change at midnight and when a timed reminder becomes overdue.
        var refresh = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        if let nextDue = db.activeReminders.compactMap({ $0.hasTime ? $0.dueDate : nil }).filter({ $0 > now }).min() {
            refresh = min(refresh, nextDue.addingTimeInterval(1))
        }
        refresh = min(refresh, now.addingTimeInterval(3600))
        completion(Timeline(entries: [RemindEntry(database: db, now: now)], policy: .after(refresh)))
    }
}

// MARK: - Home Screen

struct RemindWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RemindWidget", provider: RemindProvider()) { entry in
            RemindWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(.secondarySystemBackground), Color(.systemBackground)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .widgetURL(WidgetLink.open.url)
        }
        .configurationDisplayName("Remind")
        .description("Tap a circle to finish a reminder. The switch at the top shows reminders by group or by urgency.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct RemindWidgetView: View {
    var entry: RemindEntry
    @Environment(\.widgetFamily) private var family

    /// Rows that fit in the left column, counting section titles as rows.
    private var lineBudget: Int {
        family == .systemLarge ? 12 : 5
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Left side: reminders only.
            VStack(alignment: .leading, spacing: family == .systemLarge ? 6 : 4) {
                let (lines, hidden) = layout()
                if lines.isEmpty {
                    Spacer()
                    Label("All clear", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                } else {
                    ForEach(lines) { line in
                        switch line.kind {
                        case .header(let section): sectionTitle(section)
                        case .reminder(let reminder): row(reminder)
                        }
                    }
                    Spacer(minLength: 0)
                    if hidden > 0 {
                        Text("+\(hidden) more")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Right edge: switch on top, today's tally in the middle, + at the bottom.
            VStack(alignment: .trailing, spacing: 0) {
                GroupingSwitch(current: entry.grouping, compact: family == .systemSmall)
                Spacer(minLength: 4)
                DoneTally(done: entry.doneToday, progress: entry.progress)
                Spacer(minLength: 4)
                AddButton(family: family)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func sectionTitle(_ section: ReminderSection) -> some View {
        Label(section.title.uppercased(), systemImage: section.symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(section.color.color)
            .lineLimit(1)
            .padding(.top, 2)
    }

    private func row(_ reminder: Reminder) -> some View {
        let color = entry.groups[reminder.groupID]?.color.color ?? .blue
        return HStack(spacing: 2) {
            // Only the circle finishes the reminder, in place (see WidgetIntents.swift). The rest
            // of the row falls through to the widget's URL, which just opens the app.
            Button(intent: CompleteReminderIntent(reminderID: reminder.id)) {
                Circle()
                    .strokeBorder(color, lineWidth: 1.6)
                    .frame(width: 14, height: 14)
                    // A slightly bigger tap target than the drawn circle.
                    .frame(width: 22, height: 20, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Text(reminder.priority == .none ? reminder.title : "\(reminder.priority.marks) \(reminder.title)")
                .font(.caption)
                .lineLimit(1)
            // No dates in the widget; they only show in the app.
            Spacer(minLength: 2)
        }
    }

    private struct Line: Identifiable {
        enum Kind { case header(ReminderSection), reminder(Reminder) }
        var id: String
        var kind: Kind
    }

    /// Flattens sections into rows until the budget runs out. A section title is only shown
    /// when at least one of its reminders fits under it.
    private func layout() -> ([Line], hidden: Int) {
        var lines: [Line] = []
        var shown = 0
        for section in entry.sections {
            guard lines.count + 2 <= lineBudget else { break }
            lines.append(Line(id: "h" + section.id, kind: .header(section)))
            for reminder in section.reminders {
                guard lines.count < lineBudget else { break }
                lines.append(Line(id: reminder.id.uuidString, kind: .reminder(reminder)))
                shown += 1
            }
        }
        return (lines, entry.allActive.count - shown)
    }
}

/// Bottom-right +: opens the app with quick add focused. Widgets can't take typed text.
struct AddButton: View {
    var family: WidgetFamily

    var body: some View {
        // The small size ignores Links, so it uses the system "open URL" action instead.
        if family == .systemSmall {
            Button(intent: OpenURLIntent(WidgetLink.add.url)) { plus }
                .buttonStyle(.plain)
        } else {
            Link(destination: WidgetLink.add.url) { plus }
        }
    }

    /// White circle, black plus. An image (not a filled shape) so it can keep its real colors in
    /// the clear and tinted Home Screen styles, which would otherwise wash it into the background.
    private var plus: some View {
        Image(systemName: "plus.circle.fill")
            .resizable()
            .widgetAccentedRenderingMode(.fullColor)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.black, .white)
            .frame(width: 26, height: 26)
            .accessibilityLabel("Add reminder")
    }
}

/// The in-widget switch between grouping by group and by urgency. Runs in place.
struct GroupingSwitch: View {
    var current: Grouping
    var compact: Bool

    var body: some View {
        Button(intent: SwitchWidgetGroupingIntent()) { capsule }
            .buttonStyle(.plain)
    }

    private var capsule: some View {
        HStack(spacing: 3) {
            Image(systemName: current.symbol)
            if !compact { Text(current.label) }
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.fill.tertiary, in: .capsule)
        .accessibilityLabel("Showing \(current.label). Switch to \(current.toggled.label).")
    }
}

/// How many reminders you finished today, with a thin bar for the share of today's list.
struct DoneTally: View {
    var done: Int
    var progress: Double

    var body: some View {
        VStack(spacing: 2) {
            Text(done, format: .number)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .widgetAccentable()
            Text("done")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.25))
                Capsule()
                    .fill(.green)
                    .frame(width: 30 * progress)
                    .widgetAccentable()
            }
            .frame(width: 30, height: 4)
        }
        .frame(minWidth: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) done today")
    }
}

// MARK: - Lock Screen

struct RemindAccessoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RemindAccessoryWidget", provider: RemindProvider()) { entry in
            RemindAccessoryView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(WidgetLink.open.url)
        }
        .configurationDisplayName("Remind")
        .description("What's left today.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct RemindAccessoryView: View {
    var entry: RemindEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.progress) {
                Image(systemName: "checklist")
            } currentValueLabel: {
                Text(entry.leftToday, format: .number)
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryInline:
            Label(entry.leftToday == 0 ? "All clear today" : "\(entry.leftToday) left today", systemImage: "checklist")
        default:
            // The Lock Screen always shows the most urgent items, whatever the Home Screen switch says.
            let urgent = entry.allActive.sorted(by: Reminder.urgencyOrder(now: entry.date)).prefix(3)
            VStack(alignment: .leading, spacing: 1) {
                if urgent.isEmpty {
                    Label("All clear", systemImage: "checkmark.circle")
                        .font(.headline)
                } else {
                    ForEach(urgent) { reminder in
                        // Lock Screen widgets only support one tap target, so this opens the app.
                        HStack(spacing: 4) {
                            Image(systemName: reminder.isOverdue(now: entry.date) ? "exclamationmark.circle" : "circle")
                            Text(reminder.title).lineLimit(1)
                        }
                        .font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
