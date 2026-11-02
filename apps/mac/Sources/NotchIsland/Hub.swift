import AppKit
import Carbon.HIToolbox

/// Something that needs an answer: a task coming due, a timer ringing, a coding agent asking permission. The
/// collapsed island shows the first one in the queue until you press one of its buttons.
struct HeadsUp {
    struct Button {
        let title: String, symbol: String, color: NSColor
        let action: () -> Void
    }
    let id: String
    let title: String, detail: String
    let badge: String      // the symbol in the robot's corner
    let sound: String?
    let buttons: [Button]
}

// MARK: - Hub: what every island shares, and one island per display

final class Hub: NSObject {
    let nowPlaying = NowPlaying(), meetings = Meetings(), net = NetSpeed()
    let downloads = Downloads(), focus = FocusTimer(), timers = Timers(), agents = Agents(), clips = Clips()
    let updater = Updater()
    // Snapshot runs get an empty, throwaway planner so they never touch your tasks
    let planner = Planner(dir: CommandLine.arguments.contains("--snapshot")
        ? FileManager.default.temporaryDirectory.appendingPathComponent("NotchIsland-snapshot-\(UUID())")
        : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Notch Island"))
    var alerts: [HeadsUp] = []  // waiting for an answer, oldest first
    var alerting: HeadsUp? { alerts.first }
    var power = readPower()
    var files: [URL] = []
    var islands: [IslandController] = []
    var dragChange = 0, fileDrag = false
    var flashedMeeting: String?
    var frozen = false  // snapshot mode: ignore the mouse
    let menu = NSMenu()
    var focusItem: NSMenuItem!
    var settingsWindow: SettingsWindow?

    override init() {
        super.init()
        Pref.registerDefaults()

        // Right-click the open island
        // TODO: a way to reach this menu while the island is collapsed
        focusItem = menu.addItem(withTitle: "Start Focus Timer", action: #selector(toggleFocus), keyEquivalent: "")
        focusItem.target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Sponsor Notch Island…", action: #selector(sponsor), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Notch Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")

        nowPlaying.onChange = { [unowned self] isNew in self.islands.forEach { $0.trackChanged(isNew) } }
        meetings.onChange = { [unowned self] in self.islands.forEach { $0.showMeeting() } }
        focus.onChange = { [unowned self] in
            self.focusItem.title = self.focus.running ? "Stop Focus Timer" : "Start Focus Timer"
            self.islands.forEach { $0.focusChanged() }
        }
        downloads.onChange = { [unowned self] in self.islands.forEach { $0.updateMascotMood(); $0.refreshResting() } }
        downloads.onFinished = { [unowned self] url in
            self.addFiles([url])
            self.islands.forEach { $0.mascot.cheer() }
        }
        planner.onChange = { [unowned self] in
            // Ticked off or deleted from the list while its alert was up
            let gone = self.alerts.filter { a in
                guard a.id.hasPrefix("task:"), let id = UUID(uuidString: String(a.id.dropFirst(5))) else { return false }
                return self.planner.todo(id)?.done != false
            }
            gone.forEach { self.dismiss($0.id) }
            self.islands.forEach { $0.expanded.today.reload() }
        }
        timers.onChange = { [unowned self] in self.islands.forEach { $0.timersChanged() } }
        timers.onRing = { [unowned self] t in
            let id = "timer:\(t.id)"
            self.raise(HeadsUp(id: id, title: t.label, detail: "Time's up", badge: "timer", sound: "Glass", buttons: [
                .init(title: "+1 min", symbol: "plus", color: white(0.18)) { [unowned self] in
                    self.dismiss(id); self.timers.start(t.label, seconds: 60)
                },
                .init(title: "Done", symbol: "checkmark", color: .systemOrange) { [unowned self] in self.dismiss(id) },
            ]))
        }
        agents.onChange = { [unowned self] in self.islands.forEach { $0.agentsChanged() } }
        agents.onNote = { [unowned self] title, detail, done in
            self.islands.forEach { $0.note(done ? "checkmark.circle.fill" : "ellipsis.bubble.fill", done ? .systemGreen : .systemOrange, title, detail) }
            if done { self.islands.forEach { $0.mascot.cheer() } }
        }
        agents.onRequest = { [unowned self] r in
            let id = "agent:\(r.id)"
            func answer(_ allow: Bool?) { self.dismiss(id); self.agents.answer(r.id, allow: allow) }
            // Allow only when the notch shows the whole request; otherwise you read it where it's shown in full
            let allow = HeadsUp.Button(title: "Allow", symbol: "checkmark", color: .systemGreen) { answer(true) }
            let rest: [HeadsUp.Button] = [.init(title: "Deny", symbol: "xmark", color: .systemRed) { answer(false) },
                                          .init(title: "In terminal", symbol: "terminal", color: white(0.18)) { answer(nil) }]
            self.raise(HeadsUp(id: id, title: r.summary,
                               detail: r.complete ? "Claude Code · \(r.project)" : "Claude Code · \(r.project) · see it all in the terminal",
                               badge: "hand.raised.fill", sound: "Ping", buttons: r.complete ? [allow] + rest : rest))
        }
        agents.onRequestGone = { [unowned self] id in self.dismiss("agent:\(id)") }
        clips.onChange = { [unowned self] in self.islands.forEach { $0.expanded.note.clipsChanged() } }
        clips.onScreenshot = { [unowned self] url in
            self.islands.forEach { $0.note("camera.viewfinder", .systemBlue, "Screenshot", "In Clips: open the island to drag it out") }
        }
        if !CommandLine.arguments.contains("--snapshot") { agents.start(); clips.start() }
        registerHotKey()

        layoutIslands()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                               queue: .main) { [unowned self] _ in self.layoutIslands() }
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [unowned self] in
            self.globalMouse($0)
        }
        Task { @MainActor [unowned self] in
            var n = 0
            while true {
                try? await Task.sleep(for: .seconds(1))
                n += 1
                self.tick(n)
            }
        }
        nowPlaying.start()
        meetings.start()
        downloads.start()
    }

    /// Displays came, went, moved or changed resolution (the lid closing, a monitor plugged in): islands whose
    /// display is unchanged stay as they are, the rest are rebuilt.
    func layoutIslands() {
        let screens = NSScreen.screens
        islands.removeAll { i in
            guard !screens.contains(where: i.fits) else { return false }
            i.close()
            return true
        }
        for s in screens where !islands.contains(where: { $0.fits(s) }) {
            islands.append(IslandController(hub: self, screen: s))
        }
    }

    // MARK: Menu and settings

    @objc func toggleFocus() {
        if focus.running { focus.stop() } else { focus.start() }
    }

    @objc func checkForUpdates() { Task { await updater.check(manual: true) } }

    @objc func sponsor() { NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/vipulpandey7860")!) }

    @objc func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(onChange: { [unowned self] p in self.islands.forEach { $0.apply(p) } },
                                            checkForUpdates: { [unowned self] in self.checkForUpdates() })
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Tasks

    /// ⌥N from anywhere opens the island under the cursor with the task box ready.
    /// TODO: ⌥N types "˜" (for ñ) on some layouts; make the shortcut changeable in Settings
    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, me in
            let hub = Unmanaged<Hub>.fromOpaque(me!).takeUnretainedValue()
            DispatchQueue.main.async { hub.quickAdd() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(optionKey), EventHotKeyID(signature: 0x4E49_534C, id: 1),  // "NISL"
                            GetApplicationEventTarget(), 0, &ref)
    }

    func quickAdd() {
        let p = NSEvent.mouseLocation
        (islands.first { $0.screenFrame.contains(p) } ?? islands.first)?.openForTyping()
    }

    // MARK: Heads-ups

    func raise(_ h: HeadsUp) {
        alerts.append(h)
        guard alerts.count == 1 else { return }  // it waits its turn
        show()
    }

    func dismiss(_ id: String) {
        let wasShowing = alerting?.id == id
        alerts.removeAll { $0.id == id }
        guard wasShowing else { return }
        if alerting != nil { show() } else { islands.forEach { $0.alertEnded() } }
    }

    private func show() {
        if let s = alerting?.sound { NSSound(named: s)?.play() }
        islands.forEach { $0.showAlert() }
    }

    func taskHeadsUp(_ t: Todo) -> HeadsUp {
        let id = "task:\(t.id)"
        return HeadsUp(id: id, title: t.title, detail: "Due \(dueText(t.due ?? Date()))", badge: "bell.fill", sound: "Hero", buttons: [
            .init(title: "5 min", symbol: "moon.zzz.fill", color: white(0.18)) { [unowned self] in
                self.dismiss(id); self.planner.snooze(t.id)
            },
            .init(title: "Done", symbol: "checkmark", color: .systemOrange) { [unowned self] in
                self.planner.setDone(t.id, true)  // dismisses it via onChange
                self.islands.forEach { $0.mascot.cheer() }
            },
        ])
    }

    // MARK: Mouse

    func globalMouse(_ e: NSEvent) {
        let pb = NSPasteboard(name: .drag)
        switch e.type {
        case .leftMouseDown: dragChange = pb.changeCount; fileDrag = false
        case .leftMouseDragged where !fileDrag:
            // a new drag that carries files (not a window or text drag)
            fileDrag = pb.changeCount != dragChange && pb.types?.contains(.fileURL) == true
        case .leftMouseUp: fileDrag = false
        default: break
        }
        for i in islands {
            if e.type == .mouseMoved { i.mascot.cursor(at: i.panel.convertPoint(fromScreen: NSEvent.mouseLocation)) }
            i.mascot.setWatching(fileDrag)
            i.trackMouse()
            i.refreshShelf()
        }
    }

    // MARK: Data

    func tick(_ n: Int) {
        let s = net.sample()
        focus.tick()
        timers.tick()
        clips.poll()
        let p = readPower(), pluggedIn = p.plugged && !power.plugged, powerChanged = p != power
        power = p
        if n % 30 == 0 { meetings.refresh() }
        // A minute after launch, then once a day
        if (n == 60 || n % 86_400 == 0), Pref.checkForUpdates.isOn, !frozen { Task { await updater.check() } }
        if planner.rollOver() { islands.forEach { $0.expanded.willOpen() } }  // midnight: a new day's list and note
        // One task alert at a time; more come due once it's answered
        if !alerts.contains(where: { $0.id.hasPrefix("task:") }), let t = planner.nextAlert() { raise(taskHeadsUp(t)) }
        // Heads-up 5 minutes before a meeting, once per event
        var meetingSoon = false
        if Pref.showMeetings.isOn, let e = meetings.next, let id = e.eventIdentifier, id != flashedMeeting,
           (1...300).contains(e.startDate.timeIntervalSinceNow) {
            flashedMeeting = id
            meetingSoon = true
        }

        for i in islands {
            i.expanded.tick(nowPlaying.track)
            i.expanded.net.stringValue = "↓\(rate(s.down))  ↑\(rate(s.up))"
            if focus.running || timers.next != nil { i.expanded.showCountdowns() }
            if focus.running || timers.next != nil || !agents.sessions.isEmpty { i.updateEars() }
            if powerChanged { i.expanded.showPower(p) }
            if pluggedIn { i.flash(.charging, 3.5); i.mascot.pluggedIn() }
            i.mascot.tired = p.hasBattery && !p.plugged && p.level < 20
            if n % 30 != 0 { i.showMeeting() }
            if n % 30 == 0, i.mode == .expanded { i.expanded.today.reload() }  // tasks turn overdue as time passes
            if meetingSoon { i.flash(.meeting, 8); i.mascot.meetingSoon() }
        }
    }

    func addFiles(_ urls: [URL]) {
        let new = urls.filter { !files.contains($0) }
        guard !new.isEmpty else { return }
        files += new
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        islands.forEach { $0.shelfChanged() }
    }

    func removeFiles(_ urls: [URL]) {
        files.removeAll(where: urls.contains)
        islands.forEach { $0.shelfChanged() }
    }
}
