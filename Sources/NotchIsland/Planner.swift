// Tasks and the daily note. Everything stays on this Mac, in ~/Library/Application Support/Notch Island:
// tasks.json, and one plain-text file per day in Notes/.
import Foundation

struct Todo: Codable, Equatable {
    var id = UUID()
    var title: String
    var day: String        // "2026-11-02": the day whose list it's on
    var due: Date?         // when the notch rings; nil for a plain to-do
    var done = false
    var rang = false       // its alert went off (or came too late to bother)
}

private let keyFormat: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
    return f
}()

/// "2026-11-02" for a date, in the Mac's time zone.
func dayKey(_ d: Date) -> String { keyFormat.string(from: d) }
/// The key for `offset` days from today.
func dayKey(in offset: Int) -> String { dayKey(Calendar.current.date(byAdding: .day, value: offset, to: Date())!) }
/// How many days from today `key` is.
func dayOffset(_ key: String) -> Int {
    let cal = Calendar.current
    guard let d = keyFormat.date(from: key) else { return 0 }
    return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: d).day ?? 0
}

/// Reminders keep whole seconds, so they read back from tasks.json exactly as they went in.
private func whole(_ d: Date?) -> Date? { d.map { Date(timeIntervalSinceReferenceDate: $0.timeIntervalSinceReferenceDate.rounded()) } }

final class Planner {
    private(set) var todos: [Todo] = []
    var onChange: () -> Void = {}
    let dir: URL
    private var file: URL { dir.appendingPathComponent("tasks.json") }
    private var today = ""
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    init(dir: URL) {
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("Notes"), withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: file) {
            if let t = try? Self.decoder.decode([Todo].self, from: data) { todos = t } else {
                // Unreadable (hand-edited?): set it aside instead of overwriting it on the next save
                let aside = dir.appendingPathComponent("tasks-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.moveItem(at: file, to: aside)
            }
        }
        rollOver()
    }

    /// Unfinished tasks from earlier days move onto today's list, so nothing slips away until it's done.
    /// Call it once a second; it only does something on a new day. True when the day changed.
    @discardableResult
    func rollOver() -> Bool {
        let now = dayKey(Date())
        guard now != today else { return false }
        today = now
        var moved = false
        for i in todos.indices where !todos[i].done && todos[i].day < now { todos[i].day = now; moved = true }
        if moved { changed() }
        return true
    }

    /// To do (timed first, by time) and done, for one day's list.
    func list(_ day: String) -> (todo: [Todo], done: [Todo]) {
        let mine = todos.filter { $0.day == day }
        return (mine.filter { !$0.done }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }, mine.filter(\.done))
    }

    func todo(_ id: UUID) -> Todo? { todos.first { $0.id == id } }

    /// Adds what you typed; a day or time in it ("tomorrow 5pm") decides where it goes, otherwise `day`.
    @discardableResult
    func add(_ text: String, on day: String) -> Todo? {
        let p = Parse(text)
        guard !p.title.isEmpty else { return nil }
        let t = Todo(title: p.title, day: p.day.map(dayKey) ?? day, due: whole(p.due))
        todos.append(t)
        changed()
        return t
    }

    /// Retitles a task; a day or time in the new text moves it too.
    func edit(_ id: UUID, to text: String) {
        let p = Parse(text)
        guard !p.title.isEmpty else { return }
        update(id) { t in
            t.title = p.title
            if let d = p.day { t.day = dayKey(d); t.due = whole(p.due); t.rang = false }
        }
    }

    /// Sets or clears the reminder; a reminder on another day moves the task there.
    func remind(_ id: UUID, at d: Date?) {
        update(id) { t in
            t.due = whole(d); t.rang = false
            if let d { t.day = dayKey(d) }
        }
    }

    /// Moves a task to another day's list, keeping its reminder's time of day.
    func move(_ id: UUID, to day: String) {
        update(id) { t in
            t.day = day
            guard let due = t.due, let d = keyFormat.date(from: day) else { return }
            let c = Calendar.current.dateComponents([.hour, .minute], from: due)
            t.due = Calendar.current.date(bySettingHour: c.hour!, minute: c.minute!, second: 0, of: d)
            t.rang = false
        }
    }

    func snooze(_ id: UUID, minutes: Double = 5) { remind(id, at: Date().addingTimeInterval(minutes * 60)) }
    func setDone(_ id: UUID, _ done: Bool) { update(id) { $0.done = done } }
    func delete(_ id: UUID) { todos.removeAll { $0.id == id }; changed() }

    /// The next task whose time has come, marked as rung. Ones more than an hour late (the Mac was off or asleep)
    /// are marked too but stay quiet: they're on the list as overdue.
    func nextAlert(now: Date = Date()) -> Todo? {
        var hit: Todo?, marked = false
        for i in todos.indices where !todos[i].done && !todos[i].rang {
            guard let due = todos[i].due, due <= now else { continue }
            let stale = now.timeIntervalSince(due) > 3600
            guard stale || hit == nil else { continue }  // others ring after this one's dealt with
            todos[i].rang = true; marked = true
            if !stale { hit = todos[i] }
        }
        if marked { save() }
        return hit
    }

    // MARK: The daily note

    func note(_ day: String) -> String { (try? String(contentsOf: noteURL(day), encoding: .utf8)) ?? "" }

    func setNote(_ text: String, _ day: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try? FileManager.default.removeItem(at: noteURL(day)) }
        else { try? text.write(to: noteURL(day), atomically: true, encoding: .utf8) }
    }

    private func noteURL(_ day: String) -> URL { dir.appendingPathComponent("Notes/\(day).txt") }

    // MARK: Saving

    private func update(_ id: UUID, _ f: (inout Todo) -> Void) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        f(&todos[i])
        changed()
    }

    private func changed() { save(); onChange() }

    private func save() {
        guard let data = try? Self.encoder.encode(todos) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

// MARK: - Reading a day and time out of what you typed

/// "Call mom tomorrow at 5pm" → "Call mom", due tomorrow 17:00. A day without a time ("friday") only picks the list.
struct Parse {
    var title = "", day: Date?, due: Date?
    var ranges: [NSRange] = []  // the words that were read as the date

    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    // NSDataDetector doesn't read "in 20 min" or "in 2 hours"
    private static let relative = try! NSRegularExpression(pattern: #"\bin (\d{1,3}) ?(m|mins?|minutes?|h|hrs?|hours?)\b"#,
                                                           options: .caseInsensitive)
    // A day on its own comes back at noon; these mean a time was really given
    private static let timeWords = try! NSRegularExpression(
        pattern: #"\d ?(am|pm)\b|\d:\d\d|\b(noon|midnight|tonight|morning|afternoon|evening)\b"#, options: .caseInsensitive)

    init(_ text: String, now: Date = Date()) {
        let s = text as NSString, cal = Calendar.current
        if let m = Self.relative.firstMatch(in: text, range: NSRange(location: 0, length: s.length)) {
            let n = Double(s.substring(with: m.range(at: 1)))!, hours = s.substring(with: m.range(at: 2)).lowercased().hasPrefix("h")
            due = now.addingTimeInterval(n * (hours ? 3600 : 60))
            ranges = [m.range]
        } else if let m = Self.detector.firstMatch(in: text, range: NSRange(location: 0, length: s.length)), let d = m.date {
            ranges = [m.range]
            let phrase = s.substring(with: m.range)
            if Self.timeWords.firstMatch(in: phrase, range: NSRange(location: 0, length: (phrase as NSString).length)) != nil {
                // "at 1pm" typed after 1pm means tomorrow, unless you said today
                let passed = d < now && cal.isDate(d, inSameDayAs: now) && !phrase.lowercased().contains("today")
                due = passed ? cal.date(byAdding: .day, value: 1, to: d) : d
            } else {
                day = cal.startOfDay(for: d)
            }
        }
        if let due { day = cal.startOfDay(for: due) }

        var t = s
        for r in ranges.reversed() { t = t.replacingCharacters(in: r, with: " ") as NSString }
        var words = (t as String).split(whereSeparator: \.isWhitespace)
        // Drop a word the date leaves dangling: "dentist on", "report due by"
        while let w = words.last, !ranges.isEmpty, ["on", "at", "by", "due"].contains(w.lowercased()) { words.removeLast() }
        title = words.joined(separator: " ")
    }
}

extension Parse {
    private static let timerPattern = try! NSRegularExpression(
        pattern: #"^\s*(.*?)\s*(?:for\s+)?(\d{1,3})\s*(s|secs?|seconds?|m|mins?|minutes?|h|hrs?|hours?)\s*$"#, options: .caseInsensitive)

    /// "tea 4 min" is a 4-minute timer called "tea". "call mom in 20 min" isn't: that's a task with a reminder.
    static func timer(_ text: String) -> (label: String, seconds: Double)? {
        let s = text as NSString
        guard let m = timerPattern.firstMatch(in: text, range: NSRange(location: 0, length: s.length)) else { return nil }
        var words = s.substring(with: m.range(at: 1)).split(separator: " ").map(String.init)
        if words.last?.lowercased() == "in" { return nil }
        if words.first?.lowercased() == "timer" { words.removeFirst() }
        let n = Double(s.substring(with: m.range(at: 2)))!, unit = s.substring(with: m.range(at: 3)).lowercased()
        let seconds = n * (unit.hasPrefix("h") ? 3600 : unit.hasPrefix("m") ? 60 : 1)
        guard seconds > 0, seconds <= 24 * 3600 else { return nil }
        let label = words.joined(separator: " ")
        return (label.isEmpty ? "Timer" : label.prefix(1).uppercased() + label.dropFirst(), seconds)
    }
}

// MARK: - Self-check: `NotchIsland --selftest`

extension Planner {
    static func selfTest() {
        let cal = Calendar.current, now = Date()
        func day(_ d: Date?) -> Int? { d.map { cal.dateComponents([.day], from: cal.startOfDay(for: now), to: $0).day! } }

        var p = Parse("Call mom tomorrow at 5pm")
        precondition(p.title == "Call mom" && day(p.due) == 1 && cal.component(.hour, from: p.due!) == 17, "\(p)")
        p = Parse("dentist on friday 9am")
        precondition(p.title == "dentist" && cal.component(.weekday, from: p.due!) == 6 && cal.component(.hour, from: p.due!) == 9, "\(p)")
        p = Parse("Email Sam about the API friday")
        precondition(p.title == "Email Sam about the API" && p.due == nil && cal.component(.weekday, from: p.day!) == 6, "\(p)")
        p = Parse("stretch in 20 min", now: now)
        precondition(p.title == "stretch" && p.due == now.addingTimeInterval(1200), "\(p)")
        p = Parse("call bank at 1pm", now: cal.date(bySettingHour: 23, minute: 0, second: 0, of: now)!)
        precondition(p.title == "call bank" && day(p.due) == 1 && cal.component(.hour, from: p.due!) == 13, "\(p)")  // 1pm has gone
        p = Parse("read 20 pages")
        precondition(p.title == "read 20 pages" && p.day == nil && p.due == nil, "\(p)")
        precondition(Parse.timer("tea 4 min")! == ("Tea", 240), "timer")
        precondition(Parse.timer("timer 90s")! == ("Timer", 90) && Parse.timer("pasta for 1 hour")! == ("Pasta", 3600), "timer")
        precondition(Parse.timer("call mom in 20 min") == nil && Parse.timer("read 20 pages") == nil, "not timers")
        precondition(durationText(240) == "4 min" && durationText(5400) == "1 h 30 min", "durations")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NotchIsland-selftest-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let pl = Planner(dir: dir)
        let old = pl.add("old chore", on: dayKey(in: -2))!, gone = pl.add("finished", on: dayKey(in: -2))!
        pl.setDone(gone.id, true)
        pl.today = ""; pl.rollOver()
        precondition(pl.todo(old.id)!.day == dayKey(Date()) && pl.todo(gone.id)!.day == dayKey(in: -2), "rollover")

        let soon = pl.add("ring me in 1 min", on: dayKey(Date()))!, late = pl.add("late", on: dayKey(Date()))!
        pl.remind(late.id, at: now.addingTimeInterval(-7200))
        precondition(pl.nextAlert(now: now) == nil && pl.todo(late.id)!.rang, "a two-hour-old reminder stays quiet")
        precondition(pl.nextAlert(now: now.addingTimeInterval(61))?.id == soon.id, "rings when due")
        precondition(pl.nextAlert(now: now.addingTimeInterval(62)) == nil, "rings once")
        precondition(Planner(dir: dir).todos == pl.todos, "saved and read back")
        Agents.selfTest(in: dir)
        print("selftest ok")
    }
}
