import ReminderKit
import SwiftUI
import UIKit

@main
struct HelloAppApp: App {
    @State private var store = ReminderStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .onAppear {
                    Notifications.requestAuthorization()
                    Notifications.reschedule(for: store.database)
                }
                .onChange(of: scenePhase) { _, phase in
                    // The widget may have completed things while the app was in the background.
                    if phase == .active { store.reload() }
                }
        }
    }
}

/// The smart views. Done is deliberately not one of them: it is a hidden folder.
enum Scope: Hashable {
    case today, scheduled, flagged, all
    case group(UUID)

    static let smart: [Scope] = [.today, .scheduled, .flagged, .all]

    func title(in db: ReminderDatabase) -> String {
        switch self {
        case .today: "Today"
        case .scheduled: "Scheduled"
        case .flagged: "Flagged"
        case .all: "All"
        case .group(let id): db.group(id: id)?.name ?? "Group"
        }
    }

    func symbol(in db: ReminderDatabase) -> String {
        switch self {
        case .today: "sun.max.fill"
        case .scheduled: "calendar"
        case .flagged: "flag.fill"
        case .all: "tray.full.fill"
        case .group(let id): db.group(id: id)?.symbol ?? "list.bullet"
        }
    }

    func color(in db: ReminderDatabase) -> GroupColor {
        switch self {
        case .today: .orange
        case .scheduled: .red
        case .flagged: .yellow
        case .all: .graphite
        case .group(let id): db.group(id: id)?.color ?? .blue
        }
    }

    func reminders(in db: ReminderDatabase, now: Date = .now) -> [Reminder] {
        let active = db.activeReminders
        switch self {
        case .today: return active.filter { $0.isDueTodayOrOverdue(now: now) }
        case .scheduled: return active.filter { $0.dueDate != nil }
        case .flagged: return active.filter(\.isFlagged)
        case .all: return active
        case .group(let id): return active.filter { $0.groupID == id }
        }
    }

    /// The group new reminders land in when quick add has no `#group`.
    var defaultGroup: UUID? {
        if case .group(let id) = self { return id }
        return nil
    }
}

enum Route: Hashable {
    case scope(Scope)
    case done
}

struct HomeView: View {
    @Environment(ReminderStore.self) private var store
    @State private var path: [Route] = []
    @State private var editingGroup: ReminderGroup?
    @State private var groupToDelete: ReminderGroup?

    private var db: ReminderDatabase { store.database }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(Scope.smart, id: \.self) { scope in
                            NavigationLink(value: Route.scope(scope)) {
                                SmartCard(
                                    title: scope.title(in: db),
                                    symbol: scope.symbol(in: db),
                                    color: scope.color(in: db),
                                    count: scope.reminders(in: db).count
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(db.sortedGroups) { group in
                        NavigationLink(value: Route.scope(.group(group.id))) {
                            GroupRow(group: group, count: Scope.group(group.id).reminders(in: db).count)
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { groupToDelete = group }
                            Button("Edit", systemImage: "pencil") { editingGroup = group }
                                .tint(.indigo)
                        }
                        .contextMenu {
                            Button("Edit Group", systemImage: "pencil") { editingGroup = group }
                            Button("Delete Group", systemImage: "trash", role: .destructive) { groupToDelete = group }
                        }
                    }
                    .onMove { store.moveGroups(from: $0, to: $1) }
                } header: {
                    HStack {
                        Text("Groups")
                        Spacer()
                        Button("New Group", systemImage: "plus.circle.fill") {
                            editingGroup = ReminderGroup(name: "", color: .blue, symbol: "list.bullet", sortOrder: 0)
                        }
                        .labelStyle(.iconOnly)
                        .font(.title3)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Remind")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More", systemImage: "ellipsis") {
                        // The Done folder is hidden from the main screen and only reachable here.
                        Button {
                            path.append(.done)
                        } label: {
                            Label("Done (\(db.doneReminders.count))", systemImage: "archivebox")
                        }
                        Picker(selection: Binding(get: { db.widgetGrouping }, set: { store.setWidgetGrouping($0) })) {
                            ForEach(Grouping.allCases, id: \.self) { grouping in
                                Label(grouping.label, systemImage: grouping.symbol).tag(grouping)
                            }
                        } label: {
                            Label("Widget Groups By", systemImage: "rectangle.3.group")
                        }
                        .pickerStyle(.menu)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            .safeAreaInset(edge: .bottom) {
                QuickAddBar(defaultGroup: nil, defaultsToToday: false)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .scope(let scope): ReminderListView(scope: scope)
                case .done: DoneView()
                }
            }
            .sheet(item: $editingGroup) { group in
                GroupEditor(group: group, isNew: db.group(id: group.id) == nil)
            }
            .confirmationDialog(
                "Delete \"\(groupToDelete?.name ?? "")\"?",
                isPresented: Binding(get: { groupToDelete != nil }, set: { if !$0 { groupToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete Group and Its Reminders", role: .destructive) {
                    if let id = groupToDelete?.id { store.deleteGroup(id) }
                }
            } message: {
                Text("This also removes its finished items from Done.")
            }
            .onOpenURL(perform: handle)
        }
    }

    /// Widget taps arrive here, because widget buttons can't run code in place under xtool.
    /// The app does the action and goes straight back to the Home Screen; the widget shows the
    /// result. A reminder finished by mistake can be restored from Done.
    private func handle(_ url: URL) {
        store.reload()
        switch WidgetLink(url: url) {
        case .complete(let id):
            store.setCompleted(id, true)
        case .toggleGrouping:
            store.setWidgetGrouping(store.database.widgetGrouping.toggled)
        case .open, nil:
            return
        }
        Task {
            // A short beat so iOS has finished bringing the app forward; suspending mid launch is ignored.
            try? await Task.sleep(for: .milliseconds(150))
            HomeScreen.go()
        }
    }
}

enum HomeScreen {
    /// Sends the app to the background, the same as swiping home. `suspend` is a private
    /// UIApplication method: App Store review rejects it, but sideloaded builds can use it.
    @MainActor static func go() {
        UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
    }
}

struct SmartCard: View {
    var title: String
    var symbol: String
    var color: GroupColor
    var count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(color.gradient, in: .circle)
                Spacer()
                Text(count, format: .number)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.background.secondary)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [color.color.opacity(0.18), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .animation(.spring, value: count)
    }
}

struct GroupRow: View {
    var group: ReminderGroup
    var count: Int

    var body: some View {
        HStack(spacing: 12) {
            GroupBadge(color: group.color, symbol: group.symbol, size: 32)
            Text(group.name)
                .font(.body.weight(.medium))
            Spacer()
            Text(count, format: .number)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(.vertical, 2)
    }
}

struct GroupBadge: View {
    var color: GroupColor
    var symbol: String
    var size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .circle)
    }
}
