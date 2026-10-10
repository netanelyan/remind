import ReminderKit
import SwiftUI

struct ReminderEditor: View {
    @Environment(ReminderStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Reminder

    init(reminder: Reminder) {
        _draft = State(initialValue: reminder)
    }

    private var hasDue: Binding<Bool> {
        Binding(
            get: { draft.dueDate != nil },
            set: { on in
                withAnimation {
                    draft.dueDate = on ? Calendar.current.startOfDay(for: .now) : nil
                    if !on { draft.hasTime = false }
                }
            }
        )
    }

    private var hasTime: Binding<Bool> {
        Binding(
            get: { draft.hasTime },
            set: { on in
                withAnimation {
                    draft.hasTime = on
                    let calendar = Calendar.current
                    let day = draft.dueDate ?? .now
                    draft.dueDate = on
                        ? calendar.date(bySettingHour: calendar.component(.hour, from: .now) + 1, minute: 0, second: 0, of: day)
                        : calendar.startOfDay(for: day)
                }
            }
        )
    }

    private var dueBinding: Binding<Date> {
        Binding(get: { draft.dueDate ?? .now }, set: { draft.dueDate = $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title, axis: .vertical)
                        .font(.title3.weight(.semibold))
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    Picker("Group", selection: $draft.groupID) {
                        ForEach(store.database.sortedGroups) { group in
                            Label(group.name, systemImage: group.symbol).tag(group.id)
                        }
                    }
                }
                Section {
                    Toggle(isOn: hasDue) { Label("Date", systemImage: "calendar") }
                    if draft.dueDate != nil {
                        DatePicker("Day", selection: dueBinding, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                        Toggle(isOn: hasTime) { Label("Time", systemImage: "clock") }
                        if draft.hasTime {
                            DatePicker("Time", selection: dueBinding, displayedComponents: .hourAndMinute)
                        }
                    }
                }
                Section {
                    Picker("Priority", selection: $draft.priority) {
                        ForEach(Priority.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle(isOn: $draft.isFlagged) { Label("Flagged", systemImage: "flag.fill") }
                }
                Section {
                    Button("Delete Reminder", systemImage: "trash", role: .destructive) {
                        store.delete([draft.id])
                        dismiss()
                    }
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm) {
                        store.update(draft)
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct GroupEditor: View {
    var isNew: Bool

    @Environment(ReminderStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ReminderGroup

    init(group: ReminderGroup, isNew: Bool) {
        _draft = State(initialValue: group)
        self.isNew = isNew
    }

    static let symbols = [
        "list.bullet", "person.fill", "briefcase.fill", "cart.fill", "house.fill", "heart.fill",
        "star.fill", "book.fill", "graduationcap.fill", "dumbbell.fill", "fork.knife", "airplane",
        "car.fill", "gift.fill", "pawprint.fill", "leaf.fill", "creditcard.fill", "hammer.fill",
        "music.note", "gamecontroller.fill", "film.fill", "lightbulb.fill", "bag.fill", "cross.case.fill",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 16) {
                        GroupBadge(color: draft.color, symbol: draft.symbol, size: 72)
                            .shadow(color: draft.color.color.opacity(0.4), radius: 12, y: 6)
                        TextField("Group Name", text: $draft.name)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                            .padding(12)
                            .background(.background.secondary, in: .rect(cornerRadius: 14))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                Section("Color") {
                    grid(GroupColor.allCases, id: \.self) { color in
                        Circle()
                            .fill(color.gradient)
                            .frame(width: 34, height: 34)
                            .overlay {
                                if color == draft.color {
                                    Circle().strokeBorder(.background, lineWidth: 3).padding(3)
                                }
                            }
                            .onTapGesture { withAnimation(.spring) { draft.color = color } }
                    }
                }
                Section("Icon") {
                    grid(Self.symbols, id: \.self) { symbol in
                        Image(systemName: symbol)
                            .font(.body.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .foregroundStyle(symbol == draft.symbol ? .white : .primary)
                            .background(symbol == draft.symbol ? AnyShapeStyle(draft.color.gradient) : AnyShapeStyle(.fill.tertiary), in: .circle)
                            .onTapGesture { withAnimation(.spring) { draft.symbol = symbol } }
                    }
                }
            }
            .navigationTitle(isNew ? "New Group" : "Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save", role: .confirm) {
                        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
                        store.saveGroup(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func grid<Item, ID: Hashable, Cell: View>(
        _ items: [Item], id: KeyPath<Item, ID>, @ViewBuilder cell: @escaping (Item) -> Cell
    ) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 10)], spacing: 10) {
            ForEach(items, id: id) { cell($0) }
        }
        .padding(.vertical, 6)
    }
}

/// The hidden folder that finished reminders move into. Only reachable from the ••• menu.
struct DoneView: View {
    @Environment(ReminderStore.self) private var store
    @State private var confirmClear = false

    var body: some View {
        let db = store.database
        let byDay = Dictionary(grouping: db.doneReminders) { Calendar.current.startOfDay(for: $0.completedAt ?? .distantPast) }

        List {
            ForEach(byDay.keys.sorted(by: >), id: \.self) { day in
                Section {
                    ForEach(byDay[day] ?? []) { reminder in
                        ReminderRow(
                            reminder: reminder,
                            group: db.group(id: reminder.groupID),
                            accent: db.group(id: reminder.groupID)?.color ?? .blue
                        )
                        .swipeActions(edge: .leading) {
                            Button("Restore", systemImage: "arrow.uturn.backward") { store.setCompleted(reminder.id, false) }
                                .tint(.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) { store.delete([reminder.id]) }
                        }
                    }
                } header: {
                    Text(dayTitle(day))
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.spring, value: db.doneReminders.map(\.id))
        .overlay {
            if db.doneReminders.isEmpty {
                ContentUnavailableView("Nothing Done Yet", systemImage: "archivebox", description: Text("Tap a circle to finish a reminder and it lands here."))
            }
        }
        .navigationTitle("Done")
        .toolbar {
            if !db.doneReminders.isEmpty {
                Button("Clear All", role: .destructive) { confirmClear = true }
            }
        }
        .confirmationDialog("Delete all \(db.doneReminders.count) finished reminders?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Done", role: .destructive) { store.clearDone() }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
