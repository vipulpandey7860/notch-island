// Notch Island: a Dynamic Island for the MacBook notch. File shelf, now playing, battery, next meeting.
// Build & run: ./build.sh run
import AppKit

// MARK: - Main

signal(SIGPIPE, SIG_IGN)  // the now-playing helper can exit any time; writing to it must not kill us
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = IslandController()

// `NotchIsland --snapshot DIR` renders every state to DIR/*.png and quits
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    controller.frozen = true
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
        controller.expanded.setDragging(true)
        try? await Task.sleep(for: .seconds(0.6))
        controller.snapshot(dir.appendingPathComponent("7-drop.png"))
        NSApp.terminate(nil)
    }
}

app.run()
