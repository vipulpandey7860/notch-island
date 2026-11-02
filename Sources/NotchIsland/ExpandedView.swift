import AppKit

// MARK: - Expanded island, laid out top-down: a header either side of the notch, three cards (today's tasks,
// the day's note, now playing), then the shelf only when it's needed

final class ExpandedView: FlippedView {
    static let width: CGFloat = 900, shortHeight: CGFloat = 304, fullHeight: CGFloat = 422

    let today: TodayCard
    let note: NoteCard
    let player = FlippedView(frame: NSRect(x: 659, y: 40, width: 227, height: 250))
    private let tint = CAGradientLayer()  // the player card picks up the artwork's colour
    let art = artView(nil, NSRect(x: 14, y: 14, width: 76, height: 76), radius: 12)
    let title = label("", 13.5, .semibold)
    let artist = label("", 12, .regular, white(0.55))
    let source = label("", 11, .medium, white(0.35))
    let bars = BarsView(frame: NSRect(x: 102, y: 62, width: 15, height: 12))
    let progress = ProgressBar(frame: NSRect(x: 14, y: 196, width: 199, height: 12))
    // The robot walks on the bar: its top edge (y 200 here) is 12pt up from the rider view's bottom
    let rider = RiderView(frame: NSRect(x: 2, y: 164, width: 223, height: 48), barX: 12, barWidth: 199, floorY: 12)
    let elapsed = label("", 10, .medium, white(0.45), mono: true)
    let remaining = label("", 10, .medium, white(0.45), mono: true)
    let cal = NSImageView(image: sym("calendar", 11))
    let meeting = label("", 12, .medium, white(0.65))
    let join = PillButton("Join", symbol: "video.fill", color: .systemGreen, width: 58)
    private var joinURL: URL?
    let net = label("↓0 KB/s  ↑0 KB/s", 11, .medium, white(0.6), mono: true)
    let batt = NSImageView()
    let pct = label("", 12, .medium, white(0.65))
    // Shelf card: shown only while a file drag is on or the shelf holds files
    let shelfRow = FlippedView(frame: NSRect(x: 14, y: 300, width: 872, height: 108))
    let shelfTitle = label("Shelf", 12, .semibold, white(0.6))
    let dragAll = DragOutView(frame: NSRect(x: 778, y: 7, width: 78, height: 22))
    let grid = FlippedView(frame: NSRect(x: 16, y: 34, width: 840, height: 62))
    let drop = DropZoneView(frame: NSRect(x: 16, y: 34, width: 840, height: 62))
    // While a drag is on, the drop area splits: hold on the shelf, or send straight via AirDrop
    let airDrop = DropZoneView(frame: NSRect(x: 712, y: 34, width: 144, height: 62), symbol: "dot.radiowaves.left.and.right",
                               idle: "AirDrop", ready: "Send via AirDrop")
    let focusPill = PillButton("25:00", symbol: "timer", color: .systemOrange, width: 74)
    private var more: IconButton!
    private var play: IconButton!
    private var swipe: CGFloat = 0, swiped = false
    private var shownArt: NSImage?, shownPlaying: Bool?
    private(set) var dragging = false
    private unowned let c: IslandController

    init(frame: NSRect, c: IslandController) {
        self.c = c
        today = TodayCard(frame: NSRect(x: 14, y: 40, width: 398, height: 250), planner: c.hub.planner)
        note = NoteCard(frame: NSRect(x: 422, y: 40, width: 227, height: 250), planner: c.hub.planner)
        super.init(frame: frame)
        let w = frame.width
        today.onEscape = { c.collapse() }
        note.text.onEscape = { c.collapse() }
        note.onTask = { [unowned self] in self.today.add($0, fromNote: true) }

        // Header band, either side of the notch
        cal.contentTintColor = white(0.55); cal.frame = NSRect(x: 24, y: 9, width: 14, height: 14)
        put(meeting, 44, 16, 180)
        meeting.lineBreakMode = .byTruncatingMiddle  // a long title gives way before "in 4m" does
        join.frame.origin.y = 6
        join.isHidden = true
        join.action = { [unowned self] in if let url = self.joinURL { NSWorkspace.shared.open(url) } }
        put(pct, w - 64, 16, 40, align: .right)  // wide enough for "100%"
        batt.contentTintColor = white(0.65); batt.frame = NSRect(x: w - 92, y: 8, width: 28, height: 16)
        put(net, w - 248, 16, 150, align: .right)
        // The focus countdown takes the network speed's place while it runs; click to stop
        focusPill.frame.origin = NSPoint(x: w - 92 - 8 - focusPill.frame.width, y: 6)
        focusPill.isHidden = true
        focusPill.toolTip = "Stop the focus timer"
        focusPill.action = { c.focus.stop() }

        // Player card: art and titles, controls, then the progress bar (kept clear above for the robot)
        styleCard(player)
        player.layer!.masksToBounds = true
        tint.frame = player.bounds
        tint.startPoint = CGPoint(x: 0, y: 0); tint.endPoint = CGPoint(x: 1, y: 1)
        player.layer!.insertSublayer(tint, at: 0)
        art.layer!.backgroundColor = white(0.08).cgColor
        art.contentTintColor = white(0.3)  // only tints the "nothing playing" note
        put(title, 102, 30, 111); put(artist, 102, 48, 111); put(source, 122, 68, 91)
        put(elapsed, 14, 222, 60); put(remaining, 153, 222, 60, align: .right)
        let prev = IconButton("backward.fill", size: 32, point: 15, label: "Previous track") { c.nowPlaying.prev() }
        prev.frame.origin = NSPoint(x: 55, y: 112)
        play = IconButton("play.fill", size: 38, point: 20, label: "Play") { c.nowPlaying.toggle() }
        play.frame.origin = NSPoint(x: 95, y: 109)
        let next = IconButton("forward.fill", size: 32, point: 15, label: "Next track") { c.nowPlaying.next() }
        next.frame.origin = NSPoint(x: 141, y: 112)
        progress.onSeek = { f in
            if let t = c.nowPlaying.track { c.nowPlaying.seek(Double(f) * t.duration) }
        }
        ([art, title, artist, bars, source, progress, rider, elapsed, remaining, prev, play, next] as [NSView]).forEach(player.addSubview)

        // Shelf card
        styleCard(shelfRow)
        put(shelfTitle, 16, 18, 160)
        let dl = label("Drag all", 11, .semibold, white(0.85)); put(dl, 0, 11, 78, align: .center)
        dragAll.addSubview(dl)
        dragAll.wantsLayer = true; dragAll.layer!.cornerRadius = 11; dragAll.layer!.backgroundColor = white(0.12).cgColor
        dragAll.toolTip = "Drag every file out at once"
        dragAll.setAccessibilityLabel("Drag all files")
        dragAll.onGone = { c.removeFiles($0) }
        more = IconButton("ellipsis.circle", size: 22, point: 14, label: "Shelf actions") { [unowned self] in
            _ = self.fileMenu(c.files, from: self.more).popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: self.more)
        }
        more.frame.origin = NSPoint(x: dragAll.frame.minX - 28, y: 7)
        airDrop.isHidden = true
        ([shelfTitle, more, dragAll, grid, drop, airDrop] as [NSView]).forEach(shelfRow.addSubview)
        shelfRow.alphaValue = 0; shelfRow.isHidden = true

        ([cal, meeting, join, pct, batt, net, focusPill, today, note, player, shelfRow] as [NSView]).forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// The island's opening: pick up what changed while it was shut.
    func willOpen() {
        today.reload()
        note.reload()
    }

    func show(_ t: Track?) {
        if t?.artwork !== shownArt || t == nil {
            if shownArt != nil || t?.artwork != nil { art.layer?.add(CATransition(), forKey: "swap") }
            shownArt = t?.artwork
            art.image = t?.artwork ?? sym("music.note", 30, .regular)
            art.imageScaling = t?.artwork == nil ? .scaleNone : .scaleProportionallyUpOrDown
        }
        let a = t?.accent ?? .clear
        tint.colors = [a.withAlphaComponent(0.3).cgColor, a.withAlphaComponent(0.05).cgColor]
        title.stringValue = t?.title ?? "Nothing playing"
        artist.stringValue = t?.artist ?? ""
        source.stringValue = t?.app ?? ""
        bars.isHidden = t == nil
        bars.color = t?.accent ?? .white
        // The bar stays as the robot's floor; only the times need a known length
        let timed = (t?.duration ?? 0) > 0
        [elapsed, remaining].forEach { $0.isHidden = !timed }
        if !timed { progress.fraction = 0 }
        let playing = t?.playing ?? false
        if playing != shownPlaying {
            shownPlaying = playing
            bars.setPlaying(playing)
            play.setSymbol(playing ? "pause.fill" : "play.fill", label: playing ? "Pause" : "Play")
        }
        tick(t)
    }

    /// Once a second while playing: move the bar, the times and the robot riding it.
    func tick(_ t: Track?) {
        if let t { showTime(t.position, t.duration) }
        rider.update(t)
    }

    func showTime(_ e: Double, _ d: Double) {
        guard d > 0, !progress.scrubbing else { return }
        progress.fraction = CGFloat(e / d)
        elapsed.stringValue = fmt(e); remaining.stringValue = "-" + fmt(d - e)
    }

    func showPower(_ p: Power) {
        batt.isHidden = !p.hasBattery; pct.isHidden = !p.hasBattery
        pct.stringValue = "\(p.level)%"
        let levels = ["battery.0percent", "battery.25percent", "battery.50percent", "battery.75percent", "battery.100percent"]
        batt.image = sym(p.plugged ? "battery.100percent.bolt" : levels[min(4, (p.level + 12) / 25)], 13, .regular)
    }

    /// `join` adds a Join button right after the text.
    func showMeeting(_ text: String, color: NSColor?, join url: URL? = nil) {
        meeting.stringValue = text
        cal.contentTintColor = color ?? white(0.55)
        joinURL = url
        join.isHidden = url == nil
        // The label hugs its text so the button sits just after it, both stopping short of the notch
        let room = (Self.width - c.notchW) / 2 - meeting.frame.minX - 10 - (url == nil ? 0 : join.frame.width + 8)
        meeting.frame.size.width = min(ceil(meeting.fittingSize.width), room)
        join.frame.origin.x = meeting.frame.maxX + 8
    }

    func showShelf(_ files: [URL]) {
        grid.subviews.forEach { $0.removeFromSuperview() }
        // TODO: only one row of 11 tiles fits; add scrolling for more ("Drag all" still carries every file)
        for (i, url) in files.prefix(11).enumerated() {
            let v = FileItemView(url: url) { [c] in c.removeFiles([url]) }
            v.onGone = { [c] in c.removeFiles($0) }
            v.onMenu = { [unowned self] view in self.fileMenu([url], from: view) }
            v.frame.origin = NSPoint(x: CGFloat(i) * 76, y: 0)
            grid.addSubview(v)
        }
        shelfTitle.stringValue = files.isEmpty ? "Shelf" : "Shelf · \(files.count)"
        dragAll.files = files; dragAll.isHidden = files.isEmpty
        more.isHidden = files.isEmpty
        drop.isHidden = !files.isEmpty && !dragging
    }

    /// A file drag is over the island at `point` (window coords), or has left (`nil`).
    func setDragging(_ point: NSPoint?) {
        dragging = point != nil
        let toAirDrop = point.map(isOverAirDrop) ?? false
        airDrop.isHidden = !dragging
        drop.setFrameSize(NSSize(width: dragging ? airDrop.frame.minX - 8 - drop.frame.minX : grid.frame.width, height: drop.frame.height))
        drop.setActive(dragging && !toAirDrop)
        airDrop.setActive(toAirDrop)
        drop.isHidden = !dragging && !c.files.isEmpty
    }

    func isOverAirDrop(_ windowPoint: NSPoint) -> Bool {
        airDrop.bounds.contains(airDrop.convert(windowPoint, from: nil))
    }

    /// Things to do with shelf files: a tile's right-click menu, and the "⋯" menu for all of them.
    func fileMenu(_ urls: [URL], from view: NSView) -> NSMenu {
        let m = NSMenu(), many = urls.count > 1
        m.addItem(ActionItem("AirDrop", symbol: "dot.radiowaves.left.and.right") { ShelfAction.airDrop(urls) })
        m.addItem(ActionItem("Share…", symbol: "square.and.arrow.up") { ShelfAction.share(urls, from: view) })
        m.addItem(ActionItem(many ? "Compress \(urls.count) Items" : "Compress", symbol: "doc.zipper") { [c] in
            ShelfAction.compress(urls) { zip in if let zip { c.addFiles([zip]) } }  // the archive joins the shelf
        })
        m.addItem(ActionItem(many ? "Copy Paths" : "Copy Path", symbol: "doc.on.doc") { ShelfAction.copyPaths(urls) })
        m.addItem(ActionItem("Show in Finder", symbol: "folder") { ShelfAction.reveal(urls) })
        m.addItem(.separator())
        m.addItem(ActionItem(many ? "Clear Shelf" : "Remove from Shelf", symbol: "xmark.circle") { [c] in c.removeFiles(urls) })
        return m
    }

    /// The focus countdown replaces the network speed while the timer runs.
    func showFocus(_ timer: FocusTimer) {
        focusPill.isHidden = !timer.running
        net.isHidden = timer.running || !Pref.showNetSpeed.isOn
        guard let phase = timer.phase else { return }
        focusPill.setTitle(fmt(timer.remaining))
        focusPill.setColor(phase == .focus ? .systemOrange : .systemGreen)
    }

    /// Two-finger swipe across the player card: left for the next track, right for the previous.
    override func scrollWheel(with e: NSEvent) {
        guard player.frame.contains(convert(e.locationInWindow, from: nil)) else { return }
        if e.phase == .began { swipe = 0; swiped = false }
        guard e.momentumPhase.isEmpty, !swiped, abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) else { return }
        swipe += e.scrollingDeltaX
        guard abs(swipe) > 60 else { return }
        swiped = true
        if swipe < 0 { c.nowPlaying.next() } else { c.nowPlaying.prev() }
    }

    /// Fades the shelf card; the controller grows or shrinks the island to match.
    func setShelfRow(_ on: Bool, animated: Bool = true) {
        guard animated else { shelfRow.alphaValue = on ? 1 : 0; shelfRow.isHidden = !on; return }
        if on { shelfRow.isHidden = false }
        fade(shelfRow, to: on ? 1 : 0, delay: on ? 0.08 : 0, duration: on ? 0.25 : 0.12)
        if !on { after(0.15) { [weak self] in if let self, !self.c.shelfShown { self.shelfRow.isHidden = true } } }
    }
}
