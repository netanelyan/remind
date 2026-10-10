import SwiftUI

extension GroupColor {
    public var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .graphite: .gray
        }
    }

    /// A soft two-stop gradient for cards and icon badges.
    public var gradient: LinearGradient {
        LinearGradient(colors: [color.opacity(0.95), color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Reminder {
    /// Short due text like "Today", "Tue 7:30 PM" or "Oct 15", without dashes.
    public func dueText(now: Date = .now, calendar: Calendar = .current) -> String? {
        guard let dueDate else { return nil }
        let time = hasTime ? dueDate.formatted(date: .omitted, time: .shortened) : nil
        let day: String
        if calendar.isDateInToday(dueDate) {
            day = "Today"
        } else if calendar.isDateInTomorrow(dueDate) {
            day = "Tomorrow"
        } else if calendar.isDateInYesterday(dueDate) {
            day = "Yesterday"
        } else if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: dueDate).day,
                  (2...6).contains(days) {
            day = dueDate.formatted(.dateTime.weekday(.abbreviated))
        } else if calendar.isDate(dueDate, equalTo: now, toGranularity: .year) {
            day = dueDate.formatted(.dateTime.month(.abbreviated).day())
        } else {
            day = dueDate.formatted(.dateTime.month(.abbreviated).day().year())
        }
        if let time { return day == "Today" ? time : "\(day) \(time)" }
        return day
    }
}
