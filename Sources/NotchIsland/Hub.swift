import AppKit
import Carbon.HIToolbox

// MARK: - Hub: what every island shares, and one island per display

final class Hub: NSObject {
    let nowPlaying = NowPlaying(), meetings = Meetings(), net = NetSpeed()
    let downloads = Downloads(), focus = FocusTimer()
    // Snapshot runs get an empty, throwaway planner so they never touch your tasks
    let planner = Planner(dir: CommandLine.arguments.contains("--snapshot")
        ? FileManager.default.temporaryDirectory.appendingPathComponent("NotchIsland-snapshot-\(UUID())")
        : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Notch Island"))
    var alerting: Todo?  // the task whose time has come, until you snooze it or tick it off
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
            if let a = self.alerting, self.planner.todo(a.id)?.done != false { self.endAlert() }
            self.islands.forEach { $0.expanded.today.reload() }
        }
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

    @objc func openSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow { [unowned self] p in self.islands.forEach { $0.apply(p) } } }
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

    func snoozeAlert() {
        guard let a = alerting else { return }
        endAlert()
        planner.snooze(a.id)
    }

    func completeAlert() {
        guard let a = alerting else { return }
        planner.setDone(a.id, true)  // ends the alert via onChange
        islands.forEach { $0.mascot.cheer() }
    }

    private func endAlert() {
        alerting = nil
        islands.forEach { $0.alertEnded() }
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
        let p = readPower(), pluggedIn = p.plugged && !power.plugged, powerChanged = p != power
        power = p
        if n % 30 == 0 { meetings.refresh() }
        if planner.rollOver() { islands.forEach { $0.expanded.willOpen() } }  // midnight: a new day's list and note
        if alerting == nil, let t = planner.nextAlert() {
            alerting = t
            NSSound(named: "Hero")?.play()
            islands.forEach { $0.showAlert() }
        }
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
            if focus.running {
                i.expanded.showFocus(focus)
                i.updateEars()
            }
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
