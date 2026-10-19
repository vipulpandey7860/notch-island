import AppKit

// MARK: - Expanded island (laid out top-down: player, then the shelf row only when it's needed)

final class ExpandedView: FlippedView {
    static let width: CGFloat = 640, playerHeight: CGFloat = 160, fullHeight: CGFloat = 274

    let art = artView(nil, NSRect(x: 24, y: 44, width: 92, height: 92), radius: 16)
    let title = label("", 15, .semibold)
    let artist = label("", 12, .regular, white(0.55))
    let source = label("", 11, .medium, white(0.35))
    let bars = BarsView(frame: NSRect(x: 132, y: 88, width: 15, height: 12))
    let progress = ProgressBar(frame: NSRect(x: 132, y: 116, width: 484, height: 12))
    // The robot walks on the bar: its top edge (y 120 here) is 12pt up from the rider view's bottom
    let rider = RiderView(frame: NSRect(x: 120, y: 84, width: 508, height: 48), barX: 12, barWidth: 484, floorY: 12)
    let elapsed = label("", 10, .medium, white(0.45), mono: true)
    let remaining = label("", 10, .medium, white(0.45), mono: true)
    let cal = NSImageView(image: sym("calendar", 11))
    let meeting = label("", 12, .medium, white(0.65))
    let join = PillButton("Join", symbol: "video.fill", color: .systemGreen, width: 58)
    private var joinURL: URL?
    let net = label("↓0 KB/s  ↑0 KB/s", 11, .medium, white(0.6), mono: true)
    let batt = NSImageView()
    let pct = label("", 12, .medium, white(0.65))
    // Shelf row: shown only while a file drag is on or the shelf holds files
    let shelfRow = FlippedView(frame: NSRect(x: 0, y: 160, width: 640, height: 114))
    let shelfTitle = label("Shelf", 12, .semibold, white(0.6))
    let dragAll = DragOutView(frame: NSRect(x: 538, y: 7, width: 78, height: 22))
    let grid = FlippedView(frame: NSRect(x: 24, y: 36, width: 592, height: 62))
    let drop = DropZoneView(frame: NSRect(x: 24, y: 36, width: 592, height: 62))
    private var play: IconButton!
    private var shownArt: NSImage?, shownPlaying: Bool?
    private(set) var dragging = false
    private unowned let c: IslandController

    init(frame: NSRect, c: IslandController) {
        self.c = c
        super.init(frame: frame)
        let w = frame.width

        // Header band, either side of the notch
        cal.contentTintColor = white(0.55); cal.frame = NSRect(x: 24, y: 9, width: 14, height: 14)
        put(meeting, 44, 16, 180)
        meeting.lineBreakMode = .byTruncatingMiddle  // a long title gives way before "in 4m" does
        join.frame.origin.y = 6
        join.isHidden = true
        join.action = { [unowned self] in if let url = self.joinURL { NSWorkspace.shared.open(url) } }
        put(pct, w - 58, 16, 34, align: .right)
        batt.contentTintColor = white(0.65); batt.frame = NSRect(x: w - 88, y: 8, width: 28, height: 16)
        put(net, w - 248, 16, 150, align: .right)

        // Now playing: art left, controls on the title row with the player app under them,
        // progress underneath (kept clear above for the robot)
        art.layer!.backgroundColor = white(0.08).cgColor
        art.contentTintColor = white(0.3)  // only tints the "nothing playing" note
        put(title, 132, 60, 350); put(artist, 132, 80, 350); put(source, 496, 94, 120, align: .right)  // clear of the robot's antenna near the end of a song
        put(elapsed, 132, 140, 60); put(remaining, 556, 140, 60, align: .right)
        let prev = IconButton("backward.fill", size: 32, point: 15, label: "Previous track") { c.nowPlaying.prev() }
        prev.frame.origin = NSPoint(x: 494, y: 54)
        play = IconButton("play.fill", size: 38, point: 20, label: "Play") { c.nowPlaying.toggle() }
        play.frame.origin = NSPoint(x: 535, y: 51)
        let next = IconButton("forward.fill", size: 32, point: 15, label: "Next track") { c.nowPlaying.next() }
        next.frame.origin = NSPoint(x: 582, y: 54)
        progress.onSeek = { f in
            if let t = c.nowPlaying.track { c.nowPlaying.seek(Double(f) * t.duration) }
        }

        // Shelf row
        let divider = NSView(frame: NSRect(x: 24, y: 0, width: 592, height: 1))
        divider.wantsLayer = true; divider.layer!.backgroundColor = white(0.08).cgColor
        put(shelfTitle, 24, 18, 160)
        let dl = label("Drag all", 11, .semibold, white(0.85)); put(dl, 0, 11, 78, align: .center)
        dragAll.addSubview(dl)
        dragAll.wantsLayer = true; dragAll.layer!.cornerRadius = 11; dragAll.layer!.backgroundColor = white(0.12).cgColor
        dragAll.toolTip = "Drag every file out at once"
        dragAll.setAccessibilityLabel("Drag all files")
        dragAll.onGone = { c.removeFiles($0) }
        ([divider, shelfTitle, dragAll, grid, drop] as [NSView]).forEach(shelfRow.addSubview)
        shelfRow.alphaValue = 0; shelfRow.isHidden = true

        ([cal, meeting, join, pct, batt, net, art, title, artist, bars, source, progress, rider, elapsed, remaining,
          prev, play, next, shelfRow] as [NSView]).forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ t: Track?) {
        if t?.artwork !== shownArt || t == nil {
            if shownArt != nil || t?.artwork != nil { art.layer?.add(CATransition(), forKey: "swap") }
            shownArt = t?.artwork
            art.image = t?.artwork ?? sym("music.note", 30, .regular)
            art.imageScaling = t?.artwork == nil ? .scaleNone : .scaleProportionallyUpOrDown
        }
        title.stringValue = t?.title ?? "Nothing playing"
        artist.stringValue = t?.artist ?? ""
        source.stringValue = t?.app ?? ""
        bars.isHidden = t == nil
        bars.color = t?.accent ?? .white
        bars.frame.origin.x = 616 - ceil(source.fittingSize.width) - 21  // just left of the app name
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
        guard d > 0 else { return }
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
        // TODO: only one row of 7 tiles fits; add scrolling for more ("Drag all" still carries every file)
        for (i, url) in files.prefix(7).enumerated() {
            let v = FileItemView(url: url) { [c] in c.removeFiles([url]) }
            v.onGone = { [c] in c.removeFiles($0) }
            v.frame.origin = NSPoint(x: CGFloat(i) * 76, y: 0)
            grid.addSubview(v)
        }
        shelfTitle.stringValue = files.isEmpty ? "Shelf" : "Shelf · \(files.count)"
        dragAll.files = files; dragAll.isHidden = files.isEmpty
        drop.isHidden = !files.isEmpty && !dragging
    }

    func setDragging(_ on: Bool) {
        dragging = on
        drop.setActive(on)
        drop.isHidden = !on && !c.files.isEmpty
    }

    /// Fades the shelf row; the controller grows or shrinks the island to match.
    func setShelfRow(_ on: Bool, animated: Bool = true) {
        guard animated else { shelfRow.alphaValue = on ? 1 : 0; shelfRow.isHidden = !on; return }
        if on { shelfRow.isHidden = false }
        fade(shelfRow, to: on ? 1 : 0, delay: on ? 0.08 : 0, duration: on ? 0.25 : 0.12)
        if !on { after(0.15) { [weak self] in if let self, !self.c.shelfShown { self.shelfRow.isHidden = true } } }
    }
}
