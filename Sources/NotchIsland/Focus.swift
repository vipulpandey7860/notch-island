// The focus timer (a Pomodoro: focus, then a break; lengths in Settings), and the timers you type ("tea 4 min").
import AppKit

final class FocusTimer {
    enum Phase { case focus, rest }
    static var focusLength: Double { Double(UserDefaults.standard.integer(forKey: "focusMinutes")) * 60 }
    static var restLength: Double { Double(UserDefaults.standard.integer(forKey: "breakMinutes")) * 60 }

    private(set) var phase: Phase?
    private(set) var ends = Date()
    var onChange: () -> Void = {}

    var running: Bool { phase != nil }
    var remaining: Double { max(0, ends.timeIntervalSinceNow) }

    func start() {
        phase = .focus
        ends = Date().addingTimeInterval(Self.focusLength)
        onChange()
    }

    func stop() {
        phase = nil
        onChange()
    }

    /// Call once a second: rings and moves on to the break when focus ends, then finishes.
    func tick() {
        guard let p = phase, remaining <= 0 else { return }
        NSSound(named: "Glass")?.play()
        if p == .focus {
            phase = .rest
            ends = Date().addingTimeInterval(Self.restLength)
        } else {
            phase = nil
        }
        onChange()
    }
}

/// Timers you start by typing "tea 4 min" in the task box. Several can run; the island shows the one ending soonest.
final class Timers {
    struct Item {
        let id = UUID()
        let label: String
        let ends: Date
    }
    private(set) var items: [Item] = []
    var onChange: () -> Void = {}
    var onRing: (Item) -> Void = { _ in }

    var next: Item? { items.min { $0.ends < $1.ends } }

    func start(_ label: String, seconds: Double) {
        items.append(Item(label: label, ends: Date().addingTimeInterval(seconds)))
        onChange()
    }

    func stop(_ id: UUID) {
        items.removeAll { $0.id == id }
        onChange()
    }

    /// Call once a second: rings the ones that are up.
    func tick() {
        let now = Date(), up = items.filter { $0.ends <= now }
        guard !up.isEmpty else { return }
        items.removeAll { $0.ends <= now }
        onChange()
        up.forEach(onRing)
    }
}

/// "45 s", "4 min", "1 h 30 min".
func durationText(_ s: Double) -> String {
    let t = Int(s.rounded()), h = t / 3600, m = t % 3600 / 60
    if t < 60 { return "\(t) s" }
    if h == 0 { return "\(m) min" }
    return m == 0 ? "\(h) h" : "\(h) h \(m) min"
}
