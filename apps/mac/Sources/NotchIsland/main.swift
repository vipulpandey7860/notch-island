// Notch Island: a Dynamic Island for the MacBook notch. File shelf, now playing, battery, next meeting.
// Build & run: ./build.sh run
import AppKit

// MARK: - Main

signal(SIGPIPE, SIG_IGN)  // the now-playing helper can exit any time; writing to it must not kill us
let args = CommandLine.arguments
if args.contains("--selftest") { Updater.selfTest(); Planner.selfTest(); exit(0) }  // dates, rollover, agents, updates

// Release tooling, used by release.sh
if args.contains("--new-update-key") {
    let k = Updater.newKey()
    print(k.secret); print(k.public)
    exit(0)
}
if let i = args.firstIndex(of: "--sign-update"), i + 1 < args.count {  // the secret key comes on stdin
    let data = try! Data(contentsOf: URL(fileURLWithPath: args[i + 1]))
    print(try! Updater.sign(data, secret: readLine() ?? ""))
    exit(0)
}
// `--try-update FEED PUBLIC_KEY APP`: installs FEED's release over the copy at APP without relaunching (a dev check)
if let i = args.firstIndex(of: "--try-update"), i + 3 < args.count {
    Task {
        do {
            let r = try await Updater.latest(from: URL(string: args[i + 1])!)
            try await Updater.install(r, key: Updater.publicKey(args[i + 2])!, into: URL(fileURLWithPath: args[i + 3]), relaunch: false)
            print("installed \(r.version)")
            exit(0)
        } catch {
            print("failed: \(error.localizedDescription)")
            exit(1)
        }
    }
    RunLoop.main.run()
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let hub = Hub()

// `NotchIsland --snapshot DIR` renders every state to DIR/*.png and quits
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    let controller = hub.islands.first(where: \.hasNotch) ?? hub.islands[0]
    hub.frozen = true
    hub.islands.forEach { $0.mascot.freeze() }
    // Some tasks and a note (the snapshot planner is a throwaway one), one of them already overdue
    let p = hub.planner, today = dayKey(Date())
    p.add("Call the bank about the card", on: today).map { p.remind($0.id, at: Date().addingTimeInterval(-50 * 60)) }
    _ = p.nextAlert()  // rung already, so it doesn't pop up mid-run
    p.add("Prep slides for design review", on: today).map { p.remind($0.id, at: Date().addingTimeInterval(40 * 60)) }
    p.add("Pay electricity bill", on: today).map { p.remind($0.id, at: Date().addingTimeInterval(3 * 3600)) }
    p.add("Gym", on: today)
    p.add("Reply to Sam’s email", on: today).map { p.setDone($0.id, true) }
    p.setNote("Lead the review with the notch demo\nWeekly recap every Friday?\nEmail Sam about the API friday", today)
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(2))  // let now playing and the calendar arrive
        let shots: [(String, IslandController.Mode)] = [("1-music", .music), ("2-peek", .peek), ("3-charging", .charging),
                                                  ("4-meeting", .meeting), ("5-expanded", .expanded)]
        for (name, m) in shots {
            if m == .expanded { controller.expand() } else { controller.setMode(m, force: true) }
            try? await Task.sleep(for: .seconds(1.2))
            controller.snapshot(dir.appendingPathComponent("\(name).png"))
        }
        // Typing a task: the line above the box says what will be saved
        let today = controller.expanded.today
        today.field.stringValue = "Call mom tomorrow at 5pm"
        today.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        try? await Task.sleep(for: .seconds(0.4))
        controller.snapshot(dir.appendingPathComponent("5b-typing.png"))
        today.field.stringValue = ""
        today.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        // A task comes due
        let prep = p.list(dayKey(Date())).todo.first { $0.title.hasPrefix("Prep") }!
        hub.raise(hub.taskHeadsUp(prep))
        controller.collapse()
        try? await Task.sleep(for: .seconds(1.2))
        controller.snapshot(dir.appendingPathComponent("5c-alert.png"))
        hub.dismiss("task:\(prep.id)")
        controller.expand()
        try? await Task.sleep(for: .seconds(1))
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

        // A timer you typed
        hub.timers.start("Tea", seconds: 240)
        try? await Task.sleep(for: .seconds(1.2))
        controller.snapshot(dir.appendingPathComponent("19-timer.png"))
        hub.timers.items.forEach { hub.timers.stop($0.id) }

        // Claude Code at work, then asking to run something, through the real socket
        let sock = "/tmp/notch-island-snap-\(getpid()).sock"
        hub.agents.start(path: sock)
        func hook(_ json: String) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            p.arguments = ["-s", "-m", "20", "-H", "Expect:", "--unix-socket", sock, "--data-binary", json, "http://localhost/claude"]
            p.standardOutput = FileHandle.nullDevice
            try? p.run()
        }
        hook(#"{"session_id":"s","cwd":"/Users/me/notch-island","hook_event_name":"UserPromptSubmit"}"#)
        try? await Task.sleep(for: .seconds(1.5))
        controller.snapshot(dir.appendingPathComponent("20-agent.png"))
        hook(#"{"session_id":"s","cwd":"/Users/me/notch-island","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"swift build -c release"}}"#)
        try? await Task.sleep(for: .seconds(1.5))
        controller.snapshot(dir.appendingPathComponent("21-agent-ask.png"))
        hub.alerting?.buttons[0].action()  // Allow
        try? await Task.sleep(for: .seconds(1))
        controller.expand()
        try? await Task.sleep(for: .seconds(1))
        controller.snapshot(dir.appendingPathComponent("21b-agents-pill.png"))
        controller.collapse()
        try? await Task.sleep(for: .seconds(1))
        controller.note("checkmark.circle.fill", .systemGreen, "Claude finished", "notch-island · 4 min")
        try? await Task.sleep(for: .seconds(1))
        controller.snapshot(dir.appendingPathComponent("22-agent-done.png"))
        unlink(sock)

        // The Clips tab, with what was copied (added directly: your clipboard isn't touched)
        hub.clips.add(.text("https://github.com/vipulpandey7860/notch-island"))
        hub.clips.add(.file(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")))
        hub.clips.add(.text("brew install --cask notch-island"))
        controller.expand()
        controller.expanded.note.show(clips: true)
        try? await Task.sleep(for: .seconds(1.2))
        controller.snapshot(dir.appendingPathComponent("23-clips.png"))

        // Settings
        let settings = SettingsWindow(onChange: { _ in }, checkForUpdates: {})
        settings.setFrameOrigin(NSPoint(x: -4000, y: -4000))  // on screen as far as AppKit knows, out of sight
        settings.orderFrontRegardless()
        try? await Task.sleep(for: .seconds(0.6))
        if let v = settings.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("24-settings.png"))
        }
        NSApp.terminate(nil)
    }
}

app.run()
