import ReminderKit
import SwiftUI

struct ReminderListView: View {
    var scope: Scope

    @Environment(ReminderStore.self) private var store
    @AppStorage("listGrouping") private var grouping: Grouping = .groups
    @State private var editing: Reminder?

    private var db: ReminderDatabase { store.database }

    var body: some View {
        let reminders = scope.reminders(in: db)
        let sections = db.sections(of: reminders, by: grouping)
        let tint = scope.color(in: db).color

        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.reminders) { reminder in
                        ReminderRow(
                            reminder: reminder,
                            // Show which group a row belongs to when sections don't already say it.
                            group: grouping == .urgency ? db.group(id: reminder.groupID) : nil,
                            accent: db.group(id: reminder.groupID)?.color ?? .blue
                        )
                        .contentShape(.rect)
                        .onTapGesture { editing = reminder }
                        .swipeActions(edge: .leading) {
                            Button("Done", systemImage: "checkmark") { store.setCompleted(reminder.id, true) }
                                .tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) { store.delete([reminder.id]) }
                            Button(reminder.isFlagged ? "Unflag" : "Flag", systemImage: reminder.isFlagged ? "flag.slash" : "flag") {
                                store.toggleFlag(reminder.id)
                            }
                            .tint(.orange)
                        }
                    }
                    // Drag to reorder inside a section: a group's manual order, or your own order
                    // within an urgency level. Moving between urgency levels means changing the date.
                    .onMove { source, destination in
                        if section.groupID != nil {
                            store.move(in: section.reminders, from: source, to: destination)
                        } else {
                            store.moveByUrgency(in: section.reminders, from: source, to: destination)
                        }
                    }
                } header: {
                    if sections.count > 1 || grouping == .urgency {
                        SectionHeader(section: section)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.spring(duration: 0.35), value: reminders.map(\.id))
        .animation(.spring(duration: 0.35), value: grouping)
        .overlay {
            if reminders.isEmpty {
                ContentUnavailableView {
                    Label("All Clear", systemImage: "checkmark.circle")
                } description: {
                    Text("Nothing here. Finished items are in Done, under the ••• menu on the main screen.")
                }
            }
        }
        .navigationTitle(scope.title(in: db))
        .tint(tint)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("Group By", selection: $grouping.animation(.spring)) {
                    ForEach(Grouping.allCases, id: \.self) { grouping in
                        Label(grouping.label, systemImage: grouping.symbol).tag(grouping)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        .safeAreaInset(edge: .bottom) {
            QuickAddBar(defaultGroup: scope.defaultGroup, defaultsToToday: scope == .today)
        }
        .sheet(item: $editing) { reminder in
            ReminderEditor(reminder: reminder)
        }
    }
}

struct SectionHeader: View {
    var section: ReminderSection

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: section.symbol)
                .foregroundStyle(section.color.color)
            Text(section.title)
                .foregroundStyle(.primary)
            Text(section.reminders.count, format: .number)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
    }
}

struct ReminderRow: View {
    var reminder: Reminder
    /// Shown as a small tag, for views that aren't already sectioned by group.
    var group: ReminderGroup?
    var accent: GroupColor

    @Environment(ReminderStore.self) private var store
    /// Fills the circle right away; the reminder moves to Done after the animation plays.
    @State private var checking = false

    private var shownDone: Bool { reminder.isCompleted != checking }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { checking = true }
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    withAnimation(.spring) { store.setCompleted(reminder.id, !reminder.isCompleted) }
                    checking = false
                }
            } label: {
                CheckCircle(isDone: shownDone, color: accent.color)
            }
            .buttonStyle(.plain)
            .disabled(checking)
            .sensoryFeedback(.success, trigger: checking) { _, new in new }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if reminder.priority != .none {
                        Text(reminder.priority.marks)
                            .foregroundStyle(accent.color)
                            .fontWeight(.bold)
                    }
                    Text(reminder.title)
                        .strikethrough(shownDone, color: .secondary)
                        .foregroundStyle(shownDone ? .secondary : .primary)
                }
                if !reminder.notes.isEmpty {
                    Text(reminder.notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                details
            }
            Spacer(minLength: 0)
            if reminder.isFlagged {
                Image(systemName: "flag.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder private var details: some View {
        let due = reminder.dueText()
        if due != nil || group != nil {
            HStack(spacing: 8) {
                if let due {
                    Label(due, systemImage: reminder.hasTime ? "clock" : "calendar")
                        .foregroundStyle(reminder.isOverdue() ? .red : .secondary)
                }
                if let group {
                    Label(group.name, systemImage: "circle.fill")
                        .labelStyle(TagLabelStyle(color: group.color.color))
                }
            }
            .font(.caption)
        }
    }
}

private struct TagLabelStyle: LabelStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            configuration.title.foregroundStyle(.secondary)
        }
    }
}

struct CheckCircle: View {
    var isDone: Bool
    var color: Color

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isDone ? color : .secondary.opacity(0.5), lineWidth: 2)
            Circle()
                .fill(color.gradient)
                .scaleEffect(isDone ? 1 : 0.1)
                .opacity(isDone ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
                .scaleEffect(isDone ? 1 : 0.3)
                .opacity(isDone ? 1 : 0)
        }
        .frame(width: 22, height: 22)
        .contentShape(.circle.inset(by: -8))
    }
}

struct QuickAddBar: View {
    var defaultGroup: UUID?
    /// In Today, a reminder typed without a date is due today.
    var defaultsToToday: Bool

    @Environment(ReminderStore.self) private var store
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let parsed = QuickAddParser().parse(text)
        VStack(alignment: .leading, spacing: 6) {
            if focused, !text.isEmpty {
                ParsePreview(parsed: parsed, groupName: groupName(for: parsed))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                TextField("gym tomorrow 7am !high #work", text: $text)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(submit)
                if !text.isEmpty {
                    Button("Add", systemImage: "arrow.up.circle.fill", action: submit)
                        .labelStyle(.iconOnly)
                        .font(.title2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .animation(.spring(duration: 0.3), value: focused && !text.isEmpty)
        .sensoryFeedback(.impact(weight: .light), trigger: store.database.reminders.count)
    }

    private func groupName(for parsed: QuickAddParser.Result) -> String? {
        guard let hint = parsed.listHint?.lowercased() else { return nil }
        return store.database.sortedGroups.first { $0.name.lowercased().replacingOccurrences(of: " ", with: "").hasPrefix(hint) }?.name
    }

    private func submit() {
        var parsed = QuickAddParser().parse(text)
        guard !parsed.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if defaultsToToday, parsed.dueDate == nil {
            parsed.dueDate = Calendar.current.startOfDay(for: .now)
        }
        withAnimation(.spring) { store.add(parsed, defaultGroup: defaultGroup) }
        text = ""
        focused = true
    }
}

/// Chips that show what quick add understood, before you press return.
private struct ParsePreview: View {
    var parsed: QuickAddParser.Result
    var groupName: String?

    var body: some View {
        let probe = Reminder(groupID: UUID(), title: "", dueDate: parsed.dueDate, hasTime: parsed.hasTime)
        HStack(spacing: 6) {
            if let due = probe.dueText() {
                chip(due, "calendar", .red)
            }
            if parsed.priority != .none {
                chip(parsed.priority.label, "exclamationmark", .orange)
            }
            if parsed.isFlagged {
                chip("Flagged", "flag.fill", .yellow)
            }
            if let groupName {
                chip(groupName, "square.stack.3d.up.fill", .blue)
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 6)
    }

    private func chip(_ text: String, _ symbol: String, _ color: Color) -> some View {
        Label(text, systemImage: symbol)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }
}
