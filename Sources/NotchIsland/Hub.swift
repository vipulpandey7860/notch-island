import AppKit

// MARK: - Hub: what every island shares, and one island per display

final class Hub: NSObject {
    let nowPlaying = NowPlaying(), meetings = Meetings(), net = NetSpeed()
    let downloads = Downloads(), focus = FocusTimer()
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
