// A Pomodoro: 25 minutes of focus, then a 5-minute break.
import AppKit

final class FocusTimer {
    enum Phase { case focus, rest }
    // TODO: let Settings choose the lengths
    static let focusLength: Double = 25 * 60, restLength: Double = 5 * 60

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
