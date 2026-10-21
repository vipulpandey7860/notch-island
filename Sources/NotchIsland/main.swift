// Notch Island: a Dynamic Island for the MacBook notch. File shelf, now playing, battery, next meeting.
// Build & run: ./build.sh run
import AppKit

// MARK: - Main

signal(SIGPIPE, SIG_IGN)  // the now-playing helper can exit any time; writing to it must not kill us
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let hub = Hub()

// `NotchIsland --snapshot DIR` renders every state to DIR/*.png and quits
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    let controller = hub.islands.first(where: \.hasNotch) ?? hub.islands[0]
    hub.frozen = true
    hub.islands.forEach { $0.mascot.freeze() }
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(2))  // let now playing and the calendar arrive
        let shots: [(String, IslandController.Mode)] = [("1-music", .music), ("2-peek", .peek), ("3-charging", .charging),
                                                  ("4-meeting", .meeting), ("5-expanded", .expanded)]
        for (name, m) in shots {
            if m == .expanded { controller.expand() } else { controller.setMode(m, force: true) }
            try? await Task.sleep(for: .seconds(1.2))
            controller.snapshot(dir.appendingPathComponent("\(name).png"))
        }
        controller.addFiles(["/System/Applications/Music.app", "/System/Applications/Calculator.app", "/etc/hosts"].map(URL.init(fileURLWithPath:)))
        try? await Task.sleep(for: .seconds(1))
        controller.snapshot(dir.appendingPathComponent("6-shelf.png"))
        controller.expanded.setDragging(controller.expanded.airDrop.convert(NSPoint(x: 30, y: 30), to: nil))
        try? await Task.sleep(for: .seconds(0.6))
        controller.snapshot(dir.appendingPathComponent("7-drop-airdrop.png"))
        controller.expanded.showMeeting("Design review · in 4m", color: .systemPurple,
                                        join: URL(string: "https://meet.google.com/abc-defg-hij"))
        try? await Task.sleep(for: .seconds(0.3))
        controller.snapshot(dir.appendingPathComponent("7b-join.png"))

        // The robot in each kind of spot, around the resting island
        controller.expanded.setDragging(nil)
        controller.collapse()
        try? await Task.sleep(for: .seconds(1))
        let m = controller.mascot
        let poses: [(String, Mascot.Spot, Mascot.Frame)] = [
            ("8-robot-floor", .init(surface: .floorL, pos: m.range(.floorL).upperBound - 6), .look),
            ("9-robot-wall", .init(surface: .wallL, pos: m.range(.wallL).upperBound), .walk1),
            ("10-robot-ceiling", .init(surface: .ceiling, pos: m.range(.ceiling).lowerBound + 30), .stand),
            ("11-robot-sit", .init(surface: .floorR, pos: m.range(.floorR).lowerBound + 8), .sit),
            ("12-robot-sleep", .init(surface: .floorR, pos: m.range(.floorR).lowerBound + 8), .stretch),
            ("13-robot-dance-a", .init(surface: .floorL, pos: m.range(.floorL).upperBound - 12), .danceA),
            ("14-robot-dance-b", .init(surface: .floorL, pos: m.range(.floorL).upperBound - 12), .danceB),
            ("15-robot-wave", .init(surface: .floorL, pos: m.range(.floorL).upperBound - 12), .wave1),
            ("16-robot-work", .init(surface: .floorL, pos: m.range(.floorL).upperBound - 12), .work1),
        ]
        for (name, spot, frame) in poses {
            m.place(spot, frame)
            try? await Task.sleep(for: .seconds(0.4))
            controller.snapshot(dir.appendingPathComponent("\(name).png"))
        }

        // Resting states: the focus countdown, and download progress
        controller.focus.start()
        try? await Task.sleep(for: .seconds(1.2))
        controller.snapshot(dir.appendingPathComponent("17-focus.png"))
        controller.focus.stop()
        controller.setMode(.download, force: true)
        try? await Task.sleep(for: .seconds(1.2))
        controller.snapshot(dir.appendingPathComponent("18-download.png"))
        NSApp.terminate(nil)
    }
}

app.run()
