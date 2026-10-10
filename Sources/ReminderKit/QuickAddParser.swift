import Foundation

/// Parses quick-add text like `gym tomorrow 7am !high #work *`.
///
/// Understood tokens (anywhere in the text, case-insensitive):
/// - Priority: `!`, `!!`, `!!!`, `!low`, `!med`/`!medium`, `!high`, `!1` to `!3`
/// - Flag: `*` or `!flag`
/// - Group: `#name` (matched by the caller against group names, prefix allowed)
/// - Day: `today`, `tonight`, `tomorrow`/`tmrw`/`tmr`, weekday names (`fri`, `next monday`),
///   `weekend`, `next week`, `next month`, `in 3 days`, `in 2 weeks`, `oct 15`, `15 october`, `10/15`
/// - Time: `7am`, `7:30 pm`, `19:00`, `at 7`, `noon`, `midnight`, `morning`, `afternoon`,
///   `evening`, `in 2 hours`, `in 30 min`
/// Connecting words right before a date/time (`at`, `on`, `by`, `due`) are dropped too.
public struct QuickAddParser: Sendable {
    public struct Result: Equatable, Sendable {
        public var title: String
        public var dueDate: Date?
        public var hasTime: Bool
        public var priority: Priority
        public var isFlagged: Bool
        public var listHint: String?
    }

    public var calendar: Calendar
    public var now: Date

    public init(calendar: Calendar = .current, now: Date = .now) {
        self.calendar = calendar
        self.now = now
    }

    public func parse(_ text: String) -> Result {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var consumed = Set<Int>()
        var priority = Priority.none
        var isFlagged = false
        var listHint: String?
        var day: Date?
        var time: (hour: Int, minute: Int)?
        var offsetDate: Date? // "in 2 hours" is an exact moment

        var index = 0
        while index < tokens.count {
            let raw = tokens[index]
            let word = Self.normalize(raw)

            // Single-token markers.
            if let p = Self.priority(from: raw) {
                priority = p
                consumed.insert(index)
                index += 1
                continue
            }
            if raw == "*" || word == "!flag" {
                isFlagged = true
                consumed.insert(index)
                index += 1
                continue
            }
            if raw.hasPrefix("#"), raw.count > 1 {
                let name = String(raw.dropFirst())
                if name.lowercased() == "flag" || name.lowercased() == "flagged" {
                    isFlagged = true
                } else {
                    listHint = name
                }
                consumed.insert(index)
                index += 1
                continue
            }

            // Multi-token date/time phrases. Each matcher returns how many tokens it used.
            if let (date, isMoment, length) = matchRelativeOffset(tokens, at: index) {
                if isMoment { offsetDate = date } else { day = date }
                consumeWithPreposition(&consumed, from: index, length: length, tokens: tokens)
                index += length
                continue
            }
            if let (dayValue, defaultTime, length) = matchDay(tokens, at: index) {
                day = dayValue
                if let defaultTime, time == nil { time = defaultTime }
                consumeWithPreposition(&consumed, from: index, length: length, tokens: tokens)
                index += length
                continue
            }
            if let (timeValue, length) = matchTime(tokens, at: index) {
                time = timeValue
                consumeWithPreposition(&consumed, from: index, length: length, tokens: tokens)
                index += length
                continue
            }
            index += 1
        }

        let title = tokens.indices
            .filter { !consumed.contains($0) }
            .map { tokens[$0] }
            .joined(separator: " ")

        var dueDate: Date?
        var hasTime = false
        if let offsetDate {
            // "in 2 hours" is an exact moment and wins over any other day/time words.
            dueDate = offsetDate
            hasTime = true
        } else if let time {
            let base = day ?? calendar.startOfDay(for: now)
            var candidate = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: base)
            // A bare time that already passed today means tomorrow.
            if day == nil, let c = candidate, c <= now {
                candidate = calendar.date(byAdding: .day, value: 1, to: c)
            }
            dueDate = candidate
            hasTime = true
        } else if let day {
            dueDate = calendar.startOfDay(for: day)
        }

        return Result(
            title: title,
            dueDate: dueDate,
            hasTime: hasTime,
            priority: priority,
            isFlagged: isFlagged,
            listHint: listHint
        )
    }

    // MARK: - Matchers

    private static let prepositions: Set<String> = ["at", "on", "by", "due", "this"]

    private func consumeWithPreposition(_ consumed: inout Set<Int>, from start: Int, length: Int, tokens: [String]) {
        for i in start..<(start + length) { consumed.insert(i) }
        let before = start - 1
        if before >= 0, !consumed.contains(before), Self.prepositions.contains(Self.normalize(tokens[before])) {
            consumed.insert(before)
        }
    }

    /// `in 3 days`, `in 2 weeks`, `in 1 month` (a day) or `in 2 hours`, `in 30 min` (a moment).
    private func matchRelativeOffset(_ tokens: [String], at i: Int) -> (date: Date, isMoment: Bool, length: Int)? {
        guard Self.normalize(tokens[i]) == "in", i + 1 < tokens.count else { return nil }
        var amountToken = Self.normalize(tokens[i + 1])
        var unitToken: String?
        var length = 3
        // Allow "in 2h" / "in 30m" / "in 3d".
        if let match = amountToken.firstMatch(of: /^(\d+)([a-z]+)$/) {
            amountToken = String(match.1)
            unitToken = String(match.2)
            length = 2
        } else if i + 2 < tokens.count {
            unitToken = Self.normalize(tokens[i + 2])
        }
        let amount = Int(amountToken) ?? Self.numberWords[amountToken]
        guard let amount, let unitToken else { return nil }

        let component: Calendar.Component
        switch unitToken {
        case "min", "mins", "minute", "minutes", "m": component = .minute
        case "hour", "hours", "hr", "hrs", "h": component = .hour
        case "day", "days", "d": component = .day
        case "week", "weeks", "w", "wk", "wks": component = .weekOfYear
        case "month", "months", "mo": component = .month
        default: return nil
        }
        guard let date = calendar.date(byAdding: component, value: amount, to: now) else { return nil }
        if component == .minute || component == .hour {
            return (date, true, length)
        }
        return (calendar.startOfDay(for: date), false, length)
    }

    /// Returns the day, an optional default time ("tonight" → 8pm), and tokens used.
    private func matchDay(_ tokens: [String], at i: Int) -> (Date, (hour: Int, minute: Int)?, Int)? {
        let word = Self.normalize(tokens[i])
        let next = i + 1 < tokens.count ? Self.normalize(tokens[i + 1]) : nil
        let today = calendar.startOfDay(for: now)

        switch word {
        case "today", "tod": return (today, nil, 1)
        case "tonight": return (today, (20, 0), 1)
        case "tomorrow", "tmrw", "tmr", "tomorow", "tommorow":
            return (calendar.date(byAdding: .day, value: 1, to: today)!, nil, 1)
        case "weekend":
            return (nextWeekday(7, after: today, includingToday: true), nil, 1)
        case "next":
            guard let next else { return nil }
            if next == "week" {
                return (nextWeekday(2, after: today, includingToday: false), nil, 2) // next Monday
            }
            if next == "month" {
                return (calendar.date(byAdding: .month, value: 1, to: today)!, nil, 2)
            }
            if next == "weekend" {
                let thisSat = nextWeekday(7, after: today, includingToday: true)
                return (calendar.date(byAdding: .day, value: 7, to: thisSat)!, nil, 2)
            }
            if let weekday = Self.weekdays[next] {
                // "next friday" = the friday after the coming one if that's within 7 days? Most people
                // mean "the coming friday, not today", so treat like a plain weekday but never today.
                return (nextWeekday(weekday, after: today, includingToday: false), nil, 2)
            }
            return nil
        default:
            break
        }

        if let weekday = Self.weekdays[word] {
            return (nextWeekday(weekday, after: today, includingToday: true), nil, 1)
        }

        // "oct 15", "october 15th"
        if let month = Self.months[word], let next, let dayNumber = Self.dayNumber(next) {
            return (upcomingDate(month: month, day: dayNumber), nil, 2)
        }
        // "15 oct", "15th october"
        if let dayNumber = Self.dayNumber(word), let next, let month = Self.months[next] {
            return (upcomingDate(month: month, day: dayNumber), nil, 2)
        }
        // "10/15" (month/day or day/month by locale), optional "/2027"
        if let match = word.firstMatch(of: /^(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?$/) {
            let a = Int(match.1)!, b = Int(match.2)!
            let monthFirst = Self.isMonthFirst(calendar.locale ?? .current)
            let (month, dayNumber) = monthFirst ? (a, b) : (b, a)
            guard (1...12).contains(month), (1...31).contains(dayNumber) else { return nil }
            if let yearText = match.3, var year = Int(yearText) {
                if year < 100 { year += 2000 }
                if let date = calendar.date(from: DateComponents(year: year, month: month, day: dayNumber)) {
                    return (date, nil, 1)
                }
                return nil
            }
            return (upcomingDate(month: month, day: dayNumber), nil, 1)
        }
        return nil
    }

    private func matchTime(_ tokens: [String], at i: Int) -> ((hour: Int, minute: Int), Int)? {
        let word = Self.normalize(tokens[i])
        let next = i + 1 < tokens.count ? Self.normalize(tokens[i + 1]) : nil

        switch word {
        case "noon", "midday": return ((12, 0), 1)
        case "midnight": return ((23, 59), 1)
        case "morning": return ((9, 0), 1)
        case "afternoon": return ((15, 0), 1)
        case "evening": return ((18, 0), 1)
        case "eod": return ((17, 0), 1)
        default: break
        }

        // "7am", "7:30pm", "7.30pm"
        if let match = word.firstMatch(of: /^(\d{1,2})(?:[:.](\d{2}))?(am|pm|a|p)$/) {
            return Self.time(hour: Int(match.1)!, minute: match.2.flatMap { Int($0) } ?? 0, meridiem: String(match.3)).map { ($0, 1) }
        }
        // "7 am", "7:30 pm"
        if let match = word.firstMatch(of: /^(\d{1,2})(?:[:.](\d{2}))?$/), let next, ["am", "pm", "a.m.", "p.m."].contains(next) {
            return Self.time(hour: Int(match.1)!, minute: match.2.flatMap { Int($0) } ?? 0, meridiem: next).map { ($0, 2) }
        }
        // "19:00", "7:30" (24-hour style)
        if let match = word.firstMatch(of: /^(\d{1,2})[:.](\d{2})$/) {
            let hour = Int(match.1)!, minute = Int(match.2)!
            guard hour < 24, minute < 60 else { return nil }
            return ((hour, minute), 1)
        }
        // "at 7": a bare number only counts as a time after "at".
        if i > 0, Self.normalize(tokens[i - 1]) == "at", let hour = Int(word), (0...23).contains(hour) {
            let resolved: Int
            switch hour {
            case 1...6: resolved = hour + 12   // "at 5" → 5pm
            case 7...11: resolved = hour       // "at 8" → 8am
            default: resolved = hour
            }
            return ((resolved, 0), 1)
        }
        return nil
    }

    // MARK: - Helpers

    private func nextWeekday(_ weekday: Int, after day: Date, includingToday: Bool) -> Date {
        let current = calendar.component(.weekday, from: day)
        var delta = (weekday - current + 7) % 7
        if delta == 0 && !includingToday { delta = 7 }
        return calendar.date(byAdding: .day, value: delta, to: day)!
    }

    private func upcomingDate(month: Int, day: Int) -> Date {
        let today = calendar.startOfDay(for: now)
        var components = calendar.dateComponents([.year], from: today)
        components.month = month
        components.day = day
        if let date = calendar.date(from: components), date >= today {
            return date
        }
        components.year! += 1
        return calendar.date(from: components) ?? today
    }

    private static func time(hour: Int, minute: Int, meridiem: String) -> (hour: Int, minute: Int)? {
        guard (1...12).contains(hour), (0..<60).contains(minute) else { return nil }
        let isPM = meridiem.hasPrefix("p")
        var h = hour % 12
        if isPM { h += 12 }
        return (h, minute)
    }

    private static func priority(from raw: String) -> Priority? {
        switch raw.lowercased() {
        case "!", "!low", "!l", "!1": .low
        case "!!", "!med", "!medium", "!m", "!2": .medium
        case "!!!", "!high", "!h", "!3": .high
        case "!none", "!0": Priority.none
        default: nil
        }
    }

    private static func dayNumber(_ word: String) -> Int? {
        guard let match = word.firstMatch(of: /^(\d{1,2})(?:st|nd|rd|th)?$/), let n = Int(match.1), (1...31).contains(n) else {
            return nil
        }
        return n
    }

    /// Lowercases and strips trailing punctuation like commas.
    static func normalize(_ token: String) -> String {
        var t = token.lowercased()
        while let last = t.last, [",", ";"].contains(last) { t.removeLast() }
        return t
    }

    private static func isMonthFirst(_ locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: locale) ?? "M/d"
        guard let m = format.firstIndex(of: "M"), let d = format.firstIndex(of: "d") else { return true }
        return m < d
    }

    private static let weekdays: [String: Int] = [
        "sunday": 1, "sun": 1,
        "monday": 2, "mon": 2,
        "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4,
        "thursday": 5, "thu": 5, "thur": 5, "thurs": 5,
        "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7,
    ]

    private static let months: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3,
        "april": 4, "apr": 4, "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7,
        "august": 8, "aug": 8, "september": 9, "sep": 9, "sept": 9, "october": 10, "oct": 10,
        "november": 11, "nov": 11, "december": 12, "dec": 12,
    ]

    private static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    ]
}
