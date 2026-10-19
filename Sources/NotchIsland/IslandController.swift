import AppKit

// MARK: - IslandController

final class IslandController: NSObject {
    enum Mode { case idle, music, peek, charging, meeting, expanded }
    static let win = NSSize(width: 760, height: 330)

    let notchW: CGFloat, notchH: CGFloat
    let panel: IslandPanel
    let root = RootView(frame: NSRect(origin: .zero, size: IslandController.win))
    let bg = CAShapeLayer(), glow = CAGradientLayer(), glowMask = CAShapeLayer()
    var expanded: ExpandedView!
    let nowPlaying = NowPlaying(), meetings = Meetings(), net = NetSpeed()
    let mascot = Mascot()
    var power = readPower()
    var files: [URL] = []
    var mode = Mode.idle
    var collapsedViews: [NSView] = [], liveArt: [NSImageView] = []
    var revert, expandWork, collapseWork, poll: Task<Void, Never>?
    var dragChange = 0, fileDrag = false, gen = 0
    var flashedMeeting: String?
    var frozen = false  // snapshot mode: ignore the mouse
    var shelfShown = false
    var wantsShelf: Bool { fileDrag || expanded.dragging || !files.isEmpty }
    var playing: Bool { nowPlaying.track?.playing ?? false }
    /// What the island shows at rest: ears while music plays or files are held, otherwise hidden in the notch.
    var base: Mode { playing || !files.isEmpty ? .music : .idle }

    var cx: CGFloat { Self.win.width / 2 }
    var top: CGFloat { Self.win.height }
    var expandedFrame: CGRect {
        CGRect(x: cx - ExpandedView.width / 2, y: top - ExpandedView.fullHeight, width: ExpandedView.width, height: ExpandedView.fullHeight)
    }

    override init() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main!
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            notchW = r.minX - l.maxX; notchH = screen.safeAreaInsets.top
        } else {
            // TODO: external and non-notch displays just get a notch-sized pill; size and place the island per screen
            notchW = 180; notchH = 24
        }
        let f = screen.frame
        panel = IslandPanel(NSRect(x: f.midX - Self.win.width / 2, y: f.maxY - Self.win.height,
                                  width: Self.win.width, height: Self.win.height))
        super.init()

        panel.contentView = root
        root.wantsLayer = true
        let p = path(.idle)
        bg.path = p; bg.shadowPath = p; glowMask.path = p
        bg.fillColor = NSColor.black.cgColor
        bg.shadowColor = NSColor.black.cgColor; bg.shadowRadius = 20; bg.shadowOffset = CGSize(width: 0, height: -8); bg.shadowOpacity = 0
        glow.type = .radial; glow.frame = root.bounds; glow.mask = glowMask; glow.opacity = 0
        root.layer!.insertSublayer(glow, at: 0)
        root.layer!.insertSublayer(bg, at: 0)
        // The robot sits under the island's layers, so a growing island simply covers it
        UserDefaults.standard.register(defaults: ["showMascot": true])
        mascot.topY = top
        mascot.world = restingRect(.idle)
        mascot.mouse = { [unowned self] in self.panel.mouseLocationOutsideOfEventStream }
        mascot.container.isHidden = !UserDefaults.standard.bool(forKey: "showMascot")
        root.layer!.insertSublayer(mascot.container, at: 0)

        expanded = ExpandedView(frame: expandedFrame, c: self)
        expanded.alphaValue = 0; expanded.isHidden = true
        expanded.rider.isHidden = mascot.container.isHidden
        root.addSubview(expanded)
        root.onDrag = { [unowned self] in self.expanded.setDragging($0); self.refreshShelf() }
        root.onDrop = { [unowned self] in
            self.fileDrag = false  // the drop's mouse-up lands in our window, so the global monitor never sees it
            self.mascot.setWatching(false)
            self.addFiles($0)
        }
        let menu = NSMenu()
        // TODO: add "Open at Login" (SMAppService.mainApp) and a way to reach this menu while collapsed
        let robot = menu.addItem(withTitle: "Show Mascot", action: #selector(toggleMascot(_:)), keyEquivalent: "")
        robot.target = self
        robot.state = mascot.container.isHidden ? .off : .on
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Notch Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        root.menu = menu  // right-click the open island

        nowPlaying.onChange = { [unowned self] in self.trackChanged($0) }
        meetings.onChange = { [unowned self] in self.showMeeting() }
        expanded.show(nil)
        expanded.showPower(power)
        expanded.showShelf(files)
        showMeeting()
        tintGlow()
        panel.orderFrontRegardless()

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
        mascot.start()
        updateMascotMood()
    }

    func updateMascotMood() {
        let mood: Mascot.Mood = playing ? .party : files.isEmpty ? .asleep : .calm
        mascot.setMood(mood, accent: nowPlaying.track?.accent ?? .white)
    }

    @objc func toggleMascot(_ item: NSMenuItem) {
        let on = item.state != .on
        item.state = on ? .on : .off
        UserDefaults.standard.set(on, forKey: "showMascot")
        mascot.setVisible(on)
        expanded.rider.isHidden = !on
        if on, mode == .expanded { mascot.pause() }  // it's riding the bar right now
    }

    // MARK: Geometry

    func spec(_ m: Mode) -> (w: CGFloat, h: CGFloat, r: CGFloat, f: CGFloat) {
        switch m {
        case .idle: return (notchW - 8, notchH - 4, 8, 0)  // tucked behind the hardware notch
        case .music: return (notchW + 2 * (playing && !files.isEmpty ? 64 : 40), notchH, 10, 6)
        case .charging: return (notchW + 2 * 104, notchH, 10, 6)
        case .meeting: return (notchW + 2 * 110, notchH, 10, 6)
        case .peek: return (notchW + 2 * 100, notchH + 52, 22, 8)
        case .expanded: return (ExpandedView.width, shelfShown ? ExpandedView.fullHeight : ExpandedView.playerHeight, 30, 12)
        }
    }
    func rect(_ m: Mode) -> CGRect {
        let s = spec(m)
        return CGRect(x: cx - s.w / 2, y: top - s.h, width: s.w, height: s.h)
    }
    func path(_ m: Mode) -> CGPath {
        let s = spec(m)
        return islandPath(rect(m), radius: s.r, flare: s.f)
    }
    func hot(_ m: Mode) -> CGRect { panel.convertToScreen(rect(m)).insetBy(dx: -10, dy: -10) }

    /// What the robot walks around at rest: the island with its ears, or the bare hardware notch.
    func restingRect(_ m: Mode) -> CGRect {
        m == .music ? rect(.music) : CGRect(x: cx - notchW / 2, y: top - notchH, width: notchW, height: notchH)
    }

    /// Morph the island to `m`'s shape: bounce when growing, settle without overshoot when shrinking.
    func reshape(to m: Mode, growing: Bool) {
        let p = path(m), b: CGFloat = growing ? 0.22 : 0
        animate(bg, "path", to: p, bounce: b); animate(bg, "shadowPath", to: p, bounce: b); animate(glowMask, "path", to: p, bounce: b)
    }

    // MARK: Modes

    func setMode(_ m: Mode, force: Bool = false) {
        guard m != mode || force else { return }
        let was = mode, s0 = spec(was), s1 = spec(m)
        mode = m
        if m == .idle || m == .music { mascot.setWorld(restingRect(m)) }
        let open = m == .expanded
        reshape(to: m, growing: s1.w * s1.h > s0.w * s0.h)
        animate(bg, "shadowOpacity", to: Float(open ? 0.6 : 0), spring: false)
        animate(glow, "opacity", to: Float(open ? 1 : 0), spring: false)

        for v in collapsedViews {
            fade(v, to: 0, duration: 0.1)
            after(0.15) { v.removeFromSuperview() }
        }
        liveArt = []
        collapsedViews = collapsedContent(m)
        for v in collapsedViews {
            v.alphaValue = 0
            root.addSubview(v)
            fade(v, to: 1, delay: 0.12, duration: 0.22)
        }

        gen += 1
        let g = gen, home = expandedFrame.origin
        if open {
            // The robot hops inside to ride the progress bar
            mascot.pause()
            expanded.rider.setActive(true)
            expanded.rider.update(nowPlaying.track)
            expanded.isHidden = false
            expanded.setFrameOrigin(NSPoint(x: home.x, y: home.y + (reduceMotion ? 0 : 10)))
            after(0.07) {
                guard g == self.gen else { return }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.3
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.expanded.animator().alphaValue = 1
                    self.expanded.animator().setFrameOrigin(home)
                }
            }
        } else if was == .expanded {
            mascot.resume()
            expanded.rider.setActive(false)
            NSAnimationContext.runAnimationGroup { $0.duration = 0.1; self.expanded.animator().alphaValue = 0 }
            after(0.12) { if g == self.gen { self.expanded.isHidden = true } }
        }
    }

    func collapsedContent(_ m: Mode) -> [NSView] {
        let r = rect(m), cy = top - notchH / 2
        switch m {
        case .idle, .expanded:
            return []
        case .music:
            if let t = nowPlaying.track, t.playing {
                let art = artView(t.artwork, NSRect(x: r.minX + 11, y: cy - 10, width: 20, height: 20), radius: 5)
                liveArt.append(art)
                let bars = BarsView(frame: NSRect(x: r.maxX - 26, y: cy - 6, width: 15, height: 12))
                bars.color = t.accent; bars.setPlaying(true)
                guard !files.isEmpty else { return [art, bars] }
                return [art, bars, pill("\(files.count)", NSRect(x: bars.frame.minX - 30, y: cy - 8, width: 22, height: 16))]
            }
            // Only files held: a tray on the left, the count on the right
            let tray = NSImageView(image: sym("tray.full.fill", 12))
            tray.contentTintColor = white(0.85)
            tray.frame = NSRect(x: r.minX + 11, y: cy - 8, width: 20, height: 16)
            return [tray, pill("\(files.count)", NSRect(x: r.maxX - 33, y: cy - 8, width: 22, height: 16))]
        case .charging:
            let bolt = NSImageView(image: sym("bolt.fill", 11))
            bolt.contentTintColor = .systemGreen
            bolt.frame = NSRect(x: r.minX + 12, y: cy - 7, width: 12, height: 14)
            let text = label(power.charging ? "Charging" : "Plugged in", 12, .semibold); put(text, r.minX + 28, cy, 76)
            let batt = BatteryView(frame: NSRect(x: r.maxX - 38, y: cy - 6, width: 25, height: 12))
            let pct = label("\(power.level)%", 12, .semibold, .systemGreen); put(pct, batt.frame.minX - 46, cy, 40, align: .right)
            let level = CGFloat(power.level) / 100
            after(0.2) { batt.charge(to: level) }
            return [bolt, text, pct, batt]
        case .meeting:
            guard let e = meetings.next else { return [] }
            let dot = NSView(frame: NSRect(x: r.minX + 14, y: cy - 3.5, width: 7, height: 7))
            dot.wantsLayer = true; dot.layer!.cornerRadius = 3.5; dot.layer!.backgroundColor = e.calendar.color.cgColor
            let name = label(e.title ?? "Event", 12, .semibold); put(name, r.minX + 27, cy, 76)
            let soon = label(when(e.startDate), 12, .semibold, .systemOrange); put(soon, r.maxX - 74, cy, 60, align: .right)
            return [dot, name, soon]
        case .peek:
            guard let t = nowPlaying.track else { return [] }
            let art = artView(t.artwork, NSRect(x: r.minX + 16, y: r.minY + 9, width: 36, height: 36), radius: 9)
            liveArt.append(art)
            let bars = BarsView(frame: NSRect(x: r.maxX - 33, y: r.minY + 21, width: 15, height: 12))
            bars.color = t.accent; bars.setPlaying(t.playing)
            let x = art.frame.maxX + 10, w = bars.frame.minX - 10 - x
            let ti = label(t.title, 13, .semibold); put(ti, x, r.minY + 35, w)
            let ar = label(t.artist, 11, .regular, white(0.55)); put(ar, x, r.minY + 18, w)
            return [art, bars, ti, ar]
        }
    }

    /// Shows a collapsed state for a few seconds, then falls back to `base`.
    func flash(_ m: Mode, _ seconds: Double) {
        guard mode != .expanded else { return }
        setMode(m, force: true)
        revert?.cancel()
        revert = after(seconds) { [unowned self] in if self.mode == m { self.setMode(self.base) } }
    }

    func tintGlow() {
        let a = nowPlaying.track?.accent ?? .clear, r = rect(.expanded), W = Self.win.width, H = Self.win.height
        glow.colors = [a.withAlphaComponent(0.4).cgColor, a.withAlphaComponent(0.1).cgColor, a.withAlphaComponent(0).cgColor]
        glow.locations = [0, 0.45, 1]
        let c = CGPoint(x: (r.minX + 70) / W, y: (r.maxY - 90) / H)  // centred on the album art
        glow.startPoint = c
        glow.endPoint = CGPoint(x: c.x + 340 / W, y: c.y + 230 / H)
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
        mascot.setWatching(fileDrag)
        trackMouse()
        refreshShelf()
    }

    func trackMouse() {
        guard !frozen else { return }
        let p = NSEvent.mouseLocation
        if mode == .expanded {
            if hot(.expanded).contains(p) { collapseWork?.cancel(); collapseWork = nil }
            else if collapseWork == nil { collapseWork = after(0.25) { [unowned self] in self.collapse() } }
        } else if hot(mode).contains(p) {
            if fileDrag { expand() }
            else if expandWork == nil {
                // short dwell so sweeping across the menu bar doesn't pop it open
                expandWork = after(0.12) { [unowned self] in
                    self.expandWork = nil
                    if self.hot(self.mode).contains(NSEvent.mouseLocation) { self.expand() }
                }
            }
        } else {
            expandWork?.cancel(); expandWork = nil
        }
    }

    func expand() {
        guard mode != .expanded else { return }
        expandWork?.cancel(); expandWork = nil
        files.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        expanded.showShelf(files)
        shelfShown = wantsShelf
        expanded.setShelfRow(shelfShown, animated: false)
        panel.ignoresMouseEvents = false
        setMode(.expanded)
        // REVIEW: our own window gets no global mouse events, so the cursor is polled at 30 Hz while open (stops on collapse)
        poll = Task { @MainActor [unowned self] in
            while !Task.isCancelled {
                self.trackMouse()
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    func collapse() {
        collapseWork = nil
        poll?.cancel(); poll = nil
        panel.ignoresMouseEvents = true
        expanded.setDragging(false)
        setMode(base)
    }

    /// While open, grows the island to reveal the shelf row (or shrinks it away) when the need changes.
    func refreshShelf() {
        guard mode == .expanded, wantsShelf != shelfShown else { return }
        shelfShown = wantsShelf
        reshape(to: .expanded, growing: shelfShown)
        expanded.setShelfRow(shelfShown)
    }

    // MARK: Data

    func trackChanged(_ isNew: Bool) {
        let t = nowPlaying.track
        expanded.show(t)
        tintGlow()
        updateMascotMood()
        for v in liveArt where v.image !== t?.artwork {  // artwork often lands a beat after the title
            v.layer?.add(CATransition(), forKey: "swap")
            v.image = t?.artwork
        }
        guard mode != .expanded else { return }
        if isNew, t?.playing == true { flash(.peek, 3) }
        else if mode == .idle || mode == .music { setMode(base) }
    }

    func tick(_ n: Int) {
        expanded.tick(nowPlaying.track)
        let s = net.sample()
        expanded.net.stringValue = "↓\(rate(s.down))  ↑\(rate(s.up))"

        let p = readPower(), pluggedIn = p.plugged && !power.plugged
        if p != power { power = p; expanded.showPower(p) }
        if pluggedIn { flash(.charging, 3.5); mascot.pluggedIn() }

        if n % 30 == 0 { meetings.refresh() } else { showMeeting() }
        // Heads-up 5 minutes before a meeting, once per event
        if let e = meetings.next, let id = e.eventIdentifier, id != flashedMeeting,
           (1...300).contains(e.startDate.timeIntervalSinceNow) {
            flashedMeeting = id
            flash(.meeting, 8)
            mascot.meetingSoon()
        }
    }

    func showMeeting() {
        guard !frozen else { return }  // snapshot mode stages its own
        if let e = meetings.next {
            // Joinable from 10 minutes before until it ends
            let joinable = e.startDate.timeIntervalSinceNow < 600 && e.endDate > Date()
            expanded.showMeeting("\(e.title ?? "Event") · \(when(e.startDate))", color: e.calendar.color,
                                 join: joinable ? meetings.link : nil)
        } else {
            expanded.showMeeting(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), color: nil)
        }
    }

    func addFiles(_ urls: [URL]) {
        let new = urls.filter { !files.contains($0) }
        guard !new.isEmpty else { return }
        files += new
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        expanded.showShelf(files)
        refreshShelf()
        updateMascotMood()
    }

    func removeFiles(_ urls: [URL]) {
        files.removeAll(where: urls.contains)
        expanded.showShelf(files)
        refreshShelf()
        updateMascotMood()
        if mode == .music || mode == .idle { setMode(base, force: true) }  // refresh the count, or tuck away
    }

    // MARK: Snapshot (dev check)

    /// Renders the island over a fake menu bar to a PNG. Needs no screen-recording permission.
    func snapshot(_ url: URL) {
        let s = Self.win, scale: CGFloat = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s.width * scale), pixelsHigh: Int(s.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(NSColor(srgbRed: 0.42, green: 0.45, blue: 0.40, alpha: 1).cgColor)  // wallpaper-ish
        ctx.fill(CGRect(origin: .zero, size: s))
        ctx.setFillColor(NSColor(white: 0.25, alpha: 1).cgColor)  // menu bar
        ctx.fill(CGRect(x: 0, y: top - notchH, width: s.width, height: notchH))
        ctx.setFillColor(NSColor.black.cgColor)  // hardware notch
        ctx.addPath(islandPath(CGRect(x: cx - notchW / 2, y: top - notchH, width: notchW, height: notchH), radius: 8, flare: 0))
        ctx.fillPath()
        root.layer!.render(in: ctx)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
